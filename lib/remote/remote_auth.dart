import 'dart:convert';
import 'dart:typed_data';

import 'remote_bytes.dart';
import 'remote_crypto.dart';
import 'remote_errors.dart';
import 'remote_identity.dart';
import 'remote_limits.dart';
import 'remote_state_store.dart';

class RemotePreAuthProof {
  const RemotePreAuthProof({
    required this.timestampMs,
    required this.nonce,
    required this.mac,
  });

  final int timestampMs;
  final Uint8List nonce;
  final Uint8List mac;
}

/// Pair-scoped gate used before any authenticated metadata is exchanged.
class RemotePreAuthGate {
  RemotePreAuthGate({RemoteCrypto? crypto, RemoteClock? clock})
    : crypto = crypto ?? RemoteCrypto(),
      clock = clock ?? const SystemRemoteClock();

  final RemoteCrypto crypto;
  final RemoteClock clock;
  final Map<String, int> _replayKeys = <String, int>{};

  Future<RemotePreAuthProof> create({
    required List<int> pairKey,
    required List<int> context,
  }) async {
    _checkPairKey(pairKey);
    _checkContext(context);
    final timestampMs = clock.now.toUtc().millisecondsSinceEpoch;
    final nonce = crypto.random.bytes(32);
    final mac = await crypto.hmacSha256(
      secret: pairKey,
      message: _message(timestampMs, nonce, context),
    );
    return RemotePreAuthProof(timestampMs: timestampMs, nonce: nonce, mac: mac);
  }

  Future<void> verify({
    required List<int> pairKey,
    required List<int> context,
    required RemotePreAuthProof proof,
  }) async {
    _checkPairKey(pairKey);
    _checkContext(context);
    if (proof.nonce.length != 32 || proof.mac.length != 32) {
      throw const RemoteException(
        RemoteFailureCode.authenticationFailed,
        'pre-authentication proof has an invalid length',
      );
    }
    final nowMs = clock.now.toUtc().millisecondsSinceEpoch;
    if (proof.timestampMs < 0 || proof.timestampMs > 0x7fffffffffffffff) {
      throw const RemoteException(
        RemoteFailureCode.authenticationExpired,
        'pre-authentication proof timestamp is invalid',
      );
    }
    _pruneReplayKeys(nowMs);
    if ((nowMs - proof.timestampMs).abs() >
        RemoteLimits.preAuthClockSkew.inMilliseconds) {
      throw const RemoteException(
        RemoteFailureCode.authenticationExpired,
        'pre-authentication proof is outside the accepted time window',
      );
    }
    final replayKey = base64Url.encode(<int>[
      ...proof.nonce,
      ..._uint64(proof.timestampMs),
    ]);
    if (_replayKeys.containsKey(replayKey)) {
      throw const RemoteException(
        RemoteFailureCode.replayDetected,
        'pre-authentication proof has already been used',
      );
    }
    final expected = await crypto.hmacSha256(
      secret: pairKey,
      message: _message(proof.timestampMs, proof.nonce, context),
    );
    if (!remoteConstantTimeEquals(expected, proof.mac)) {
      throw const RemoteException(
        RemoteFailureCode.authenticationFailed,
        'pre-authentication proof is invalid',
      );
    }
    if (_replayKeys.length >= RemoteLimits.maxReplayEntries) {
      throw const RemoteException(
        RemoteFailureCode.authenticationFailed,
        'pre-authentication replay protection is temporarily full',
      );
    }
    _replayKeys[replayKey] =
        proof.timestampMs + RemoteLimits.preAuthClockSkew.inMilliseconds;
  }

  List<int> _message(int timestampMs, List<int> nonce, List<int> context) {
    final writer = RemoteByteWriter()
      ..writeBytes(<int>[0x41, 0x56, 0x50, 0x41, 0x31]);
    writer.writeUint64(timestampMs);
    writer.writeBytes(nonce);
    writer.writeLengthPrefixedBytes(
      context,
      maxBytes: RemoteLimits.maxIdentifierBytes,
    );
    return writer.takeBytes();
  }

  void _checkPairKey(List<int> key) {
    if (key.length != 32) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'pre-authentication key must be 256 bits',
      );
    }
  }

  void _checkContext(List<int> context) {
    if (context.isEmpty || context.length > RemoteLimits.maxIdentifierBytes) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'pre-authentication context is outside the configured bound',
      );
    }
  }

  List<int> _uint64(int value) {
    final writer = RemoteByteWriter()..writeUint64(value);
    return writer.takeBytes();
  }

  void _pruneReplayKeys(int nowMs) {
    _replayKeys.removeWhere((_, expiresAtMs) => expiresAtMs < nowMs);
  }
}

class RemoteAuthChallenge {
  RemoteAuthChallenge({
    required this.sessionId,
    required this.peerDeviceId,
    required List<int> serverNonce,
    required List<int> serverPublicKey,
    required this.issuedAt,
    required this.expiresAt,
  }) : _serverNonce = Uint8List.fromList(serverNonce),
       _serverPublicKey = Uint8List.fromList(serverPublicKey);

  final String sessionId;
  final String peerDeviceId;
  final Uint8List _serverNonce;
  final Uint8List _serverPublicKey;
  final DateTime issuedAt;
  final DateTime expiresAt;

  Uint8List get serverNonce => Uint8List.fromList(_serverNonce);
  Uint8List get serverPublicKey => Uint8List.fromList(_serverPublicKey);
}

class RemoteAuthResponse {
  RemoteAuthResponse({
    required this.peerDeviceId,
    required List<int> peerPublicKey,
    required List<int> clientNonce,
    required List<int> signature,
  }) : peerPublicKey = Uint8List.fromList(peerPublicKey),
       clientNonce = Uint8List.fromList(clientNonce),
       signature = Uint8List.fromList(signature);

  final String peerDeviceId;
  final Uint8List peerPublicKey;
  final Uint8List clientNonce;
  final Uint8List signature;
}

class RemoteAuthAcceptance {
  RemoteAuthAcceptance({required this.sessionId, required List<int> signature})
    : signature = Uint8List.fromList(signature);

  final String sessionId;
  final Uint8List signature;
}

class RemoteClientHello {
  RemoteClientHello({required this.peerDeviceId, required this.proof});

  final String peerDeviceId;
  final RemotePreAuthProof proof;
}

/// Wire payloads for the pre-authentication and mutual-authentication frames.
///
/// These records intentionally carry only the minimum pairing and
/// cryptographic material required to complete the handshake. Application
/// metadata, resource identifiers, and media information are not part of the
/// unauthenticated or authentication phases.
class RemoteAuthPayloadCodec {
  const RemoteAuthPayloadCodec();

  Uint8List encodeClientHello({
    required String peerDeviceId,
    required RemotePreAuthProof proof,
  }) {
    final deviceId = remoteSafeIdentifier(peerDeviceId);
    if (proof.nonce.length != 32 || proof.mac.length != 32) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'pre-authentication proof has an invalid length',
      );
    }
    final writer = RemoteByteWriter();
    writer.writeLengthPrefixedBytes(
      utf8.encode(deviceId),
      maxBytes: RemoteLimits.maxIdentifierBytes,
    );
    writer
      ..writeUint64(proof.timestampMs)
      ..writeBytes(proof.nonce)
      ..writeBytes(proof.mac);
    return writer.takeBytes();
  }

  RemoteClientHello decodeClientHello(List<int> payload) {
    final reader = RemoteByteReader(payload);
    final peerDeviceId = _readIdentifier(reader);
    final proof = RemotePreAuthProof(
      timestampMs: reader.readUint64(),
      nonce: reader.readBytes(32, maxBytes: 32),
      mac: reader.readBytes(32, maxBytes: 32),
    );
    reader.requireDone();
    return RemoteClientHello(peerDeviceId: peerDeviceId, proof: proof);
  }

  Uint8List encodeServerHello(RemoteAuthChallenge challenge) {
    final sessionId = remoteSafeIdentifier(challenge.sessionId);
    final peerDeviceId = remoteSafeIdentifier(challenge.peerDeviceId);
    if (challenge.serverNonce.length != 32 ||
        challenge.serverPublicKey.length != 32) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'authentication challenge has an invalid key or nonce length',
      );
    }
    final issuedAtMs = _dateMilliseconds(challenge.issuedAt);
    final expiresAtMs = _dateMilliseconds(challenge.expiresAt);
    if (expiresAtMs <= issuedAtMs ||
        expiresAtMs - issuedAtMs > RemoteLimits.authTimeout.inMilliseconds) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'authentication challenge lifetime is invalid',
      );
    }
    final writer = RemoteByteWriter()
      ..writeLengthPrefixedBytes(
        utf8.encode(sessionId),
        maxBytes: RemoteLimits.maxIdentifierBytes,
      )
      ..writeLengthPrefixedBytes(
        utf8.encode(peerDeviceId),
        maxBytes: RemoteLimits.maxIdentifierBytes,
      )
      ..writeBytes(challenge.serverNonce)
      ..writeBytes(challenge.serverPublicKey)
      ..writeUint64(issuedAtMs)
      ..writeUint64(expiresAtMs);
    return writer.takeBytes();
  }

  RemoteAuthChallenge decodeServerHello(List<int> payload) {
    final reader = RemoteByteReader(payload);
    final sessionId = _readIdentifier(reader);
    final peerDeviceId = _readIdentifier(reader);
    final serverNonce = reader.readBytes(32, maxBytes: 32);
    final serverPublicKey = reader.readBytes(32, maxBytes: 32);
    final issuedAt = _readDate(reader.readUint64());
    final expiresAt = _readDate(reader.readUint64());
    reader.requireDone();
    if (!expiresAt.isAfter(issuedAt) ||
        expiresAt.difference(issuedAt) > RemoteLimits.authTimeout) {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'authentication challenge lifetime is invalid',
      );
    }
    return RemoteAuthChallenge(
      sessionId: sessionId,
      peerDeviceId: peerDeviceId,
      serverNonce: serverNonce,
      serverPublicKey: serverPublicKey,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
  }

  Uint8List encodeAuthenticate(RemoteAuthResponse response) {
    final peerDeviceId = remoteSafeIdentifier(response.peerDeviceId);
    if (response.peerPublicKey.length != 32 ||
        response.clientNonce.length != 32 ||
        response.signature.length != 64) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'authentication response has an invalid key, nonce, or signature length',
      );
    }
    final writer = RemoteByteWriter()
      ..writeLengthPrefixedBytes(
        utf8.encode(peerDeviceId),
        maxBytes: RemoteLimits.maxIdentifierBytes,
      )
      ..writeBytes(response.peerPublicKey)
      ..writeBytes(response.clientNonce)
      ..writeBytes(response.signature);
    return writer.takeBytes();
  }

  RemoteAuthResponse decodeAuthenticate(List<int> payload) {
    final reader = RemoteByteReader(payload);
    final response = RemoteAuthResponse(
      peerDeviceId: _readIdentifier(reader),
      peerPublicKey: reader.readBytes(32, maxBytes: 32),
      clientNonce: reader.readBytes(32, maxBytes: 32),
      signature: reader.readBytes(64, maxBytes: 64),
    );
    reader.requireDone();
    return response;
  }

  Uint8List encodeAuthenticated(RemoteAuthAcceptance acceptance) {
    final sessionId = remoteSafeIdentifier(acceptance.sessionId);
    if (acceptance.signature.length != 64) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'authentication acceptance has an invalid signature length',
      );
    }
    final writer = RemoteByteWriter()
      ..writeLengthPrefixedBytes(
        utf8.encode(sessionId),
        maxBytes: RemoteLimits.maxIdentifierBytes,
      )
      ..writeBytes(acceptance.signature);
    return writer.takeBytes();
  }

  RemoteAuthAcceptance decodeAuthenticated(List<int> payload) {
    final reader = RemoteByteReader(payload);
    final acceptance = RemoteAuthAcceptance(
      sessionId: _readIdentifier(reader),
      signature: reader.readBytes(64, maxBytes: 64),
    );
    reader.requireDone();
    return acceptance;
  }

  String _readIdentifier(RemoteByteReader reader) {
    final bytes = reader.readLengthPrefixedBytes(
      maxBytes: RemoteLimits.maxIdentifierBytes,
    );
    try {
      return remoteSafeIdentifier(utf8.decode(bytes));
    } on FormatException {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'remote authentication identifier is not valid UTF-8',
      );
    }
  }

  int _dateMilliseconds(DateTime value) {
    final milliseconds = value.toUtc().millisecondsSinceEpoch;
    if (milliseconds < 0) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'authentication timestamp is invalid',
      );
    }
    return milliseconds;
  }

  DateTime _readDate(int milliseconds) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    } on Object {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'authentication timestamp is outside the supported range',
      );
    }
  }
}

/// Bounded abuse controls shared by the authentication boundary.
///
/// A source is never logged or exposed in diagnostics. It is only used as a
/// short-lived bucket for failed authentication attempts.
class RemoteAbuseGuard {
  int _activeUnauthenticated = 0;
  final Map<String, List<DateTime>> _failures = <String, List<DateTime>>{};

  int get activeUnauthenticated => _activeUnauthenticated;

  bool tryAcquireUnauthenticated(String source, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    _prune(current);
    final bucket = _bucket(source);
    if (_activeUnauthenticated >= RemoteLimits.maxUnauthenticatedSessions ||
        (_failures[bucket]?.length ?? 0) >=
            RemoteLimits.maxAuthFailuresPerSource) {
      return false;
    }
    _activeUnauthenticated++;
    return true;
  }

  void releaseUnauthenticated() {
    if (_activeUnauthenticated > 0) {
      _activeUnauthenticated--;
    }
  }

  void recordAuthenticationFailure(String source, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    _prune(current);
    final bucket = _bucket(source);
    final failures = _failures.putIfAbsent(bucket, () => <DateTime>[]);
    failures.add(current);
    while (_failures.length > RemoteLimits.maxReplayEntries) {
      _failures.remove(_failures.keys.first);
    }
  }

  bool isThrottled(String source, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    _prune(current);
    return (_failures[_bucket(source)]?.length ?? 0) >=
        RemoteLimits.maxAuthFailuresPerSource;
  }

  void _prune(DateTime now) {
    final cutoff = now.subtract(RemoteLimits.authFailureWindow);
    _failures.removeWhere((_, failures) {
      failures.removeWhere((failure) => failure.isBefore(cutoff));
      return failures.isEmpty;
    });
  }

  String _bucket(String source) {
    if (source.isEmpty) {
      return 'unknown';
    }
    if (source.length > RemoteLimits.maxIdentifierBytes) {
      return 'oversized';
    }
    return source;
  }
}

typedef RemotePeerResolver =
    Future<RemotePairedDeviceMetadata?> Function(String deviceId);

/// Mutual Ed25519 transcript authentication with fresh nonces and one-shot
/// challenges. Pairing metadata is resolved by the caller, so this class does
/// not keep a second copy of remote secrets.
class RemoteAuthenticator {
  RemoteAuthenticator({
    required this.localIdentity,
    required this.resolvePeer,
    RemoteCrypto? crypto,
    RemoteClock? clock,
    RemoteRandom? random,
    RemoteAbuseGuard? abuseGuard,
  }) : crypto = crypto ?? localIdentity.crypto,
       clock = clock ?? const SystemRemoteClock(),
       random = random ?? SecureRemoteRandom(),
       abuseGuard = abuseGuard ?? RemoteAbuseGuard();

  final RemoteIdentityManager localIdentity;
  final RemotePeerResolver resolvePeer;
  final RemoteCrypto crypto;
  final RemoteClock clock;
  final RemoteRandom random;
  final RemoteAbuseGuard abuseGuard;
  final Map<String, RemoteAuthChallenge> _pending =
      <String, RemoteAuthChallenge>{};
  final Map<String, String> _challengeSources = <String, String>{};

  Future<RemoteAuthChallenge> issueChallenge({
    required String peerDeviceId,
    String source = 'unknown',
  }) async {
    final peer = await resolvePeer(peerDeviceId);
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
    final local = await localIdentity.loadOrCreate();
    final now = clock.now.toUtc();
    _prunePending(now);
    if (!abuseGuard.tryAcquireUnauthenticated(source, now: now)) {
      throw const RemoteException(
        RemoteFailureCode.authenticationFailed,
        'authentication source or global session limit is temporarily exhausted',
      );
    }
    try {
      final challenge = RemoteAuthChallenge(
        sessionId: base64Url.encode(random.bytes(16)).replaceAll('=', ''),
        peerDeviceId: peerDeviceId,
        serverNonce: random.bytes(32),
        serverPublicKey: Uint8List.fromList(local.publicKeyBytes),
        issuedAt: now,
        expiresAt: now.add(RemoteLimits.authTimeout),
      );
      _pending[challenge.sessionId] = challenge;
      _challengeSources[challenge.sessionId] = source;
      while (_pending.length > RemoteLimits.maxReplayEntries) {
        final oldest = _pending.keys.first;
        _pending.remove(oldest);
        final oldSource = _challengeSources.remove(oldest);
        if (oldSource != null) {
          abuseGuard.releaseUnauthenticated();
        }
      }
      return challenge;
    } on Object {
      abuseGuard.releaseUnauthenticated();
      rethrow;
    }
  }

  Future<RemoteAuthResponse> createResponse({
    required RemoteAuthChallenge challenge,
    required RemoteIdentityRecord peerIdentity,
    required List<int> channelBinding,
  }) async {
    _checkChannelBinding(channelBinding);
    if (clock.now.toUtc().isAfter(challenge.expiresAt)) {
      throw const RemoteException(
        RemoteFailureCode.authenticationExpired,
        'authentication challenge has expired',
      );
    }
    final clientNonce = random.bytes(32);
    final signature = await peerIdentity.sign(
      _transcript(
        challenge,
        peerIdentity.publicKeyBytes,
        clientNonce,
        channelBinding,
      ),
      crypto: crypto,
    );
    return RemoteAuthResponse(
      peerDeviceId: challenge.peerDeviceId,
      peerPublicKey: Uint8List.fromList(peerIdentity.publicKeyBytes),
      clientNonce: clientNonce,
      signature: Uint8List.fromList(signature),
    );
  }

  Future<void> verifyResponse({
    required RemoteAuthChallenge challenge,
    required RemoteAuthResponse response,
    required List<int> channelBinding,
  }) async {
    _checkChannelBinding(channelBinding);
    final source = _challengeSources.remove(challenge.sessionId);
    final pending = _pending.remove(challenge.sessionId);
    if (pending == null || !_matchesChallenge(pending, challenge)) {
      if (source != null) {
        abuseGuard.recordAuthenticationFailure(source, now: clock.now);
        abuseGuard.releaseUnauthenticated();
      }
      throw const RemoteException(
        RemoteFailureCode.replayDetected,
        'authentication challenge is unknown or already used',
      );
    }
    try {
      if (clock.now.toUtc().isAfter(pending.expiresAt)) {
        throw const RemoteException(
          RemoteFailureCode.authenticationExpired,
          'authentication challenge has expired',
        );
      }
      if (response.peerDeviceId != pending.peerDeviceId ||
          response.peerPublicKey.length != 32 ||
          response.clientNonce.length != 32 ||
          response.signature.length != 64) {
        throw const RemoteException(
          RemoteFailureCode.authenticationFailed,
          'authentication response shape is invalid',
        );
      }
      final peer = await resolvePeer(response.peerDeviceId);
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
      late final List<int> expectedPublicKey;
      try {
        expectedPublicKey = base64Url.decode(
          base64Url.normalize(peer.publicKey),
        );
      } on FormatException {
        throw const RemoteException(
          RemoteFailureCode.stateCorrupt,
          'paired peer public key metadata is malformed',
        );
      }
      if (!remoteConstantTimeEquals(
        expectedPublicKey,
        response.peerPublicKey,
      )) {
        throw const RemoteException(
          RemoteFailureCode.authenticationFailed,
          'authentication response key does not match pairing metadata',
        );
      }
      final valid = await crypto.verify(
        _transcript(
          pending,
          response.peerPublicKey,
          response.clientNonce,
          channelBinding,
        ),
        publicKeyBytes: response.peerPublicKey,
        signatureBytes: response.signature,
      );
      if (!valid) {
        throw const RemoteException(
          RemoteFailureCode.authenticationFailed,
          'authentication transcript signature is invalid',
        );
      }
    } on RemoteException catch (error) {
      if (source != null &&
          (error.code == RemoteFailureCode.authenticationFailed ||
              error.code == RemoteFailureCode.authenticationExpired ||
              error.code == RemoteFailureCode.replayDetected ||
              error.code == RemoteFailureCode.unknownPeer ||
              error.code == RemoteFailureCode.revokedPeer)) {
        abuseGuard.recordAuthenticationFailure(source, now: clock.now);
      }
      rethrow;
    } finally {
      if (source != null) {
        abuseGuard.releaseUnauthenticated();
      }
    }
  }

  /// Releases a challenge when a transport or peer failure happens before
  /// [verifyResponse] can consume it. This prevents an aborted connection
  /// from occupying an unauthenticated-session slot until timeout.
  void cancelChallenge(RemoteAuthChallenge challenge) {
    final pending = _pending.remove(challenge.sessionId);
    final source = _challengeSources.remove(challenge.sessionId);
    if (pending != null && source != null) {
      abuseGuard.releaseUnauthenticated();
    }
  }

  void _prunePending(DateTime now) {
    final expired = _pending.entries
        .where((entry) => now.isAfter(entry.value.expiresAt))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final sessionId in expired) {
      _pending.remove(sessionId);
      final source = _challengeSources.remove(sessionId);
      if (source != null) {
        abuseGuard.releaseUnauthenticated();
      }
    }
  }

  bool _matchesChallenge(
    RemoteAuthChallenge expected,
    RemoteAuthChallenge actual,
  ) {
    return expected.sessionId == actual.sessionId &&
        expected.peerDeviceId == actual.peerDeviceId &&
        expected.issuedAt.toUtc().millisecondsSinceEpoch ==
            actual.issuedAt.toUtc().millisecondsSinceEpoch &&
        expected.expiresAt.toUtc().millisecondsSinceEpoch ==
            actual.expiresAt.toUtc().millisecondsSinceEpoch &&
        remoteConstantTimeEquals(expected.serverNonce, actual.serverNonce) &&
        remoteConstantTimeEquals(
          expected.serverPublicKey,
          actual.serverPublicKey,
        );
  }

  Future<RemoteAuthAcceptance> createAcceptance({
    required RemoteAuthChallenge challenge,
    required RemoteAuthResponse response,
    required List<int> channelBinding,
  }) async {
    _checkChannelBinding(channelBinding);
    final local = await localIdentity.loadOrCreate();
    final signature = await local.sign(
      _transcript(
        challenge,
        response.peerPublicKey,
        response.clientNonce,
        channelBinding,
      ),
      crypto: crypto,
    );
    return RemoteAuthAcceptance(
      sessionId: challenge.sessionId,
      signature: Uint8List.fromList(signature),
    );
  }

  Future<bool> verifyAcceptance({
    required RemoteAuthChallenge challenge,
    required RemoteAuthResponse response,
    required RemoteAuthAcceptance acceptance,
    required List<int> expectedServerPublicKey,
    required List<int> channelBinding,
  }) async {
    _checkChannelBinding(channelBinding);
    if (acceptance.sessionId != challenge.sessionId ||
        expectedServerPublicKey.length != 32 ||
        acceptance.signature.length != 64) {
      return false;
    }
    return crypto.verify(
      _transcript(
        challenge,
        response.peerPublicKey,
        response.clientNonce,
        channelBinding,
      ),
      publicKeyBytes: expectedServerPublicKey,
      signatureBytes: acceptance.signature,
    );
  }

  List<int> _transcript(
    RemoteAuthChallenge challenge,
    List<int> peerPublicKey,
    List<int> clientNonce,
    List<int> channelBinding,
  ) {
    final writer = RemoteByteWriter()
      ..writeBytes(<int>[0x41, 0x56, 0x41, 0x55, 0x31]);
    writer.writeUint8(RemoteLimits.protocolVersion);
    writer.writeLengthPrefixedBytes(
      utf8.encode(challenge.sessionId),
      maxBytes: RemoteLimits.maxIdentifierBytes,
    );
    writer.writeLengthPrefixedBytes(
      utf8.encode(challenge.peerDeviceId),
      maxBytes: RemoteLimits.maxIdentifierBytes,
    );
    writer.writeBytes(challenge.serverNonce);
    writer.writeBytes(clientNonce);
    writer.writeBytes(challenge.serverPublicKey);
    writer.writeBytes(peerPublicKey);
    writer.writeLengthPrefixedBytes(
      channelBinding,
      maxBytes: RemoteLimits.channelBindingBytes,
    );
    return writer.takeBytes();
  }

  void _checkChannelBinding(List<int> channelBinding) {
    if (channelBinding.length != RemoteLimits.channelBindingBytes) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'remote channel binding has an invalid length',
      );
    }
  }
}
