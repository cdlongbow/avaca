import 'dart:convert';
import 'dart:typed_data';

import 'remote_bytes.dart';
import 'remote_crypto.dart';
import 'remote_errors.dart';
import 'remote_identity.dart';
import 'remote_limits.dart';
import 'remote_secret_store.dart';
import 'remote_state_store.dart';

const _pairingSecretFormatVersion = 1;

class RemotePairingSession {
  RemotePairingSession({
    required this.sessionId,
    required List<int> pairingSecret,
    required this.desktopDeviceId,
    required this.desktopPublicKey,
    required this.expiresAt,
  }) : _pairingSecret = Uint8List.fromList(pairingSecret);

  final String sessionId;
  final String desktopDeviceId;
  final Uint8List desktopPublicKey;
  final DateTime expiresAt;
  final Uint8List _pairingSecret;
  bool consumed = false;

  /// This value is intended for presenting a pairing code through a future UI.
  /// It is copied so callers cannot mutate the session's comparison value.
  Uint8List get pairingSecret => Uint8List.fromList(_pairingSecret);

  void consume() {
    consumed = true;
    _pairingSecret.fillRange(0, _pairingSecret.length, 0);
  }
}

class RemotePairingManager {
  RemotePairingManager({
    required this.stateStore,
    required this.secretStore,
    required this.identityManager,
    RemoteCrypto? crypto,
    RemoteClock? clock,
    RemoteRandom? random,
  }) : crypto = crypto ?? identityManager.crypto,
       clock = clock ?? const SystemRemoteClock(),
       random = random ?? SecureRemoteRandom();

  final RemoteStateStore stateStore;
  final RemoteSecretStore secretStore;
  final RemoteIdentityManager identityManager;
  final RemoteCrypto crypto;
  final RemoteClock clock;
  final RemoteRandom random;
  final Map<String, RemotePairingSession> _sessions =
      <String, RemotePairingSession>{};

  Future<RemotePairingSession> beginPairing({
    Duration lifetime = RemoteLimits.pairingLifetime,
  }) async {
    if (lifetime <= Duration.zero || lifetime > RemoteLimits.pairingLifetime) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'pairing lifetime is outside the allowed bound',
      );
    }
    final identity = await identityManager.loadOrCreate();
    final session = RemotePairingSession(
      sessionId: base64Url.encode(random.bytes(16)).replaceAll('=', ''),
      pairingSecret: random.bytes(32),
      desktopDeviceId: identity.deviceId,
      desktopPublicKey: identity.publicKeyBytes,
      expiresAt: clock.now.toUtc().add(lifetime),
    );
    _pruneSessions();
    _sessions[session.sessionId] = session;
    return session;
  }

  Future<RemotePairedDeviceMetadata> completePairing({
    required String sessionId,
    required List<int> pairingSecret,
    required String peerDeviceId,
    required List<int> peerPublicKey,
    String label = '',
  }) async {
    final session = _sessions[sessionId];
    if (session == null || session.consumed) {
      throw const RemoteException(
        RemoteFailureCode.pairingConsumed,
        'pairing session is unknown or already consumed',
      );
    }
    if (clock.now.toUtc().isAfter(session.expiresAt)) {
      session.consume();
      _sessions.remove(sessionId);
      throw const RemoteException(
        RemoteFailureCode.pairingExpired,
        'pairing session has expired',
      );
    }
    if (!remoteConstantTimeEquals(session._pairingSecret, pairingSecret)) {
      throw const RemoteException(
        RemoteFailureCode.authenticationFailed,
        'pairing proof did not match',
      );
    }
    if (peerDeviceId.isEmpty ||
        peerPublicKey.length != 32 ||
        label.length > 256) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'peer pairing metadata is invalid',
      );
    }
    final state = await stateStore.load();
    final existing = state.pairedDevices
        .where((device) => device.deviceId == peerDeviceId)
        .firstOrNull;
    if (existing != null && !existing.revoked) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'peer is already paired',
      );
    }
    if (existing == null &&
        state.pairedDevices.length >= RemoteLimits.maxPairedDevices) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'the configured paired-device limit has been reached',
      );
    }

    // Consume before any external write so a storage error cannot turn this
    // invitation into a reusable credential.
    session.consume();
    _sessions.remove(sessionId);
    final nowMs = clock.now.toUtc().millisecondsSinceEpoch;
    final metadata = RemotePairedDeviceMetadata(
      deviceId: peerDeviceId,
      publicKey: base64Url.encode(peerPublicKey).replaceAll('=', ''),
      label: label,
      pairedAtMs: nowMs,
      lastSeenAtMs: nowMs,
      revoked: false,
      keyVersion: 1,
    );
    final secretBlob = _encodePairSecret(pairingSecret);
    try {
      await secretStore.write(_secretKeyFor(peerDeviceId), secretBlob);
    } finally {
      secretBlob.fillRange(0, secretBlob.length, 0);
    }
    final devices = <RemotePairedDeviceMetadata>[
      for (final device in state.pairedDevices)
        if (device.deviceId != peerDeviceId) device,
      metadata,
    ];
    await stateStore.save(state.copyWith(pairedDevices: devices));
    return metadata;
  }

  Future<RemotePairedDeviceMetadata?> findPeer(String deviceId) async {
    final state = await stateStore.load();
    for (final device in state.pairedDevices) {
      if (device.deviceId == deviceId) {
        return device;
      }
    }
    return null;
  }

  Future<List<int>> readPairSecret(String deviceId) async {
    final peer = await findPeer(deviceId);
    if (peer == null) {
      throw const RemoteException(
        RemoteFailureCode.unknownPeer,
        'peer is not paired',
      );
    }
    if (peer.revoked) {
      throw const RemoteException(
        RemoteFailureCode.revokedPeer,
        'peer has been revoked',
      );
    }
    final blob = await secretStore.read(_secretKeyFor(deviceId));
    if (blob == null) {
      throw const RemoteException(
        RemoteFailureCode.secretStorageCorrupt,
        'paired peer metadata exists but its protected secret is missing',
      );
    }
    try {
      return _decodePairSecret(blob);
    } finally {
      blob.fillRange(0, blob.length, 0);
    }
  }

  Future<Uint8List> derivePairKey(
    String deviceId, {
    required String purpose,
  }) async {
    if (!RegExp(r'^[a-z0-9-]{1,64}$').hasMatch(purpose)) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'pair key purpose is invalid',
      );
    }
    final pairSecret = await readPairSecret(deviceId);
    try {
      return await crypto.deriveKey(
        secret: pairSecret,
        info: 'AVACA-REMOTE/PAIR/V1/$purpose'.codeUnits,
      );
    } finally {
      pairSecret.fillRange(0, pairSecret.length, 0);
    }
  }

  Future<void> revoke(String deviceId) async {
    final state = await stateStore.load();
    var found = false;
    final devices = <RemotePairedDeviceMetadata>[];
    for (final device in state.pairedDevices) {
      if (device.deviceId == deviceId) {
        found = true;
        devices.add(device.copyWith(revoked: true));
      } else {
        devices.add(device);
      }
    }
    if (!found) {
      throw const RemoteException(
        RemoteFailureCode.unknownPeer,
        'peer is not paired',
      );
    }
    await stateStore.save(state.copyWith(pairedDevices: devices));
    await secretStore.delete(_secretKeyFor(deviceId));
  }

  void _pruneSessions() {
    final now = clock.now.toUtc();
    _sessions.removeWhere(
      (_, session) => session.consumed || now.isAfter(session.expiresAt),
    );
    while (_sessions.length >= RemoteLimits.maxReplayEntries) {
      _sessions.remove(_sessions.keys.first);
    }
  }

  Uint8List _encodePairSecret(List<int> secret) {
    if (secret.length != 32) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'pair secret must be 256 bits',
      );
    }
    final writer = RemoteByteWriter()..writeUint8(_pairingSecretFormatVersion);
    writer.writeLengthPrefixedBytes(secret, maxBytes: 32);
    return writer.takeBytes();
  }

  Uint8List _decodePairSecret(List<int> encoded) {
    final reader = RemoteByteReader(encoded);
    if (reader.readUint8() != _pairingSecretFormatVersion) {
      throw const RemoteException(
        RemoteFailureCode.secretStorageCorrupt,
        'unsupported paired secret version',
      );
    }
    final secret = reader.readLengthPrefixedBytes(maxBytes: 32);
    reader.requireDone();
    if (secret.length != 32) {
      throw const RemoteException(
        RemoteFailureCode.secretStorageCorrupt,
        'paired secret has an invalid length',
      );
    }
    return secret;
  }

  String _secretKeyFor(String deviceId) {
    if (deviceId.isEmpty || !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(deviceId)) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'peer device id is not a safe storage identifier',
      );
    }
    return 'paired-${base64Url.encode(utf8.encode(deviceId)).replaceAll('=', '')}';
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
