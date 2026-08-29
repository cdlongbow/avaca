import 'dart:convert';
import 'dart:io';

import 'remote_errors.dart';
import 'remote_limits.dart';

const _remoteStateSchemaVersion = 1;

class RemoteIdentityMetadata {
  const RemoteIdentityMetadata({
    required this.deviceId,
    required this.publicKey,
    required this.createdAtMs,
    required this.keyVersion,
  });

  final String deviceId;
  final String publicKey;
  final int createdAtMs;
  final int keyVersion;

  Map<String, Object> toJson() => <String, Object>{
    'deviceId': deviceId,
    'publicKey': publicKey,
    'createdAtMs': createdAtMs,
    'keyVersion': keyVersion,
  };

  static RemoteIdentityMetadata fromJson(Object? value) {
    if (value is! Map) {
      throw const RemoteException(
        RemoteFailureCode.stateCorrupt,
        'identity metadata is not an object',
      );
    }
    final deviceId = value['deviceId'];
    final publicKey = value['publicKey'];
    final createdAtMs = value['createdAtMs'];
    final keyVersion = value['keyVersion'];
    if (deviceId is! String ||
        publicKey is! String ||
        createdAtMs is! int ||
        keyVersion is! int ||
        deviceId.isEmpty ||
        publicKey.isEmpty ||
        createdAtMs < 0 ||
        keyVersion < 1) {
      throw const RemoteException(
        RemoteFailureCode.stateCorrupt,
        'identity metadata has invalid fields',
      );
    }
    return RemoteIdentityMetadata(
      deviceId: deviceId,
      publicKey: publicKey,
      createdAtMs: createdAtMs,
      keyVersion: keyVersion,
    );
  }
}

class RemotePairedDeviceMetadata {
  const RemotePairedDeviceMetadata({
    required this.deviceId,
    required this.publicKey,
    required this.label,
    required this.pairedAtMs,
    required this.lastSeenAtMs,
    required this.revoked,
    required this.keyVersion,
  });

  final String deviceId;
  final String publicKey;
  final String label;
  final int pairedAtMs;
  final int lastSeenAtMs;
  final bool revoked;
  final int keyVersion;

  RemotePairedDeviceMetadata copyWith({
    String? label,
    int? lastSeenAtMs,
    bool? revoked,
  }) => RemotePairedDeviceMetadata(
    deviceId: deviceId,
    publicKey: publicKey,
    label: label ?? this.label,
    pairedAtMs: pairedAtMs,
    lastSeenAtMs: lastSeenAtMs ?? this.lastSeenAtMs,
    revoked: revoked ?? this.revoked,
    keyVersion: keyVersion,
  );

  Map<String, Object> toJson() => <String, Object>{
    'deviceId': deviceId,
    'publicKey': publicKey,
    'label': label,
    'pairedAtMs': pairedAtMs,
    'lastSeenAtMs': lastSeenAtMs,
    'revoked': revoked,
    'keyVersion': keyVersion,
  };

  static RemotePairedDeviceMetadata fromJson(Object? value) {
    if (value is! Map) {
      throw const RemoteException(
        RemoteFailureCode.stateCorrupt,
        'paired device metadata is not an object',
      );
    }
    final deviceId = value['deviceId'];
    final publicKey = value['publicKey'];
    final label = value['label'];
    final pairedAtMs = value['pairedAtMs'];
    final lastSeenAtMs = value['lastSeenAtMs'];
    final revoked = value['revoked'];
    final keyVersion = value['keyVersion'];
    if (deviceId is! String ||
        publicKey is! String ||
        label is! String ||
        pairedAtMs is! int ||
        lastSeenAtMs is! int ||
        revoked is! bool ||
        keyVersion is! int ||
        deviceId.isEmpty ||
        publicKey.isEmpty ||
        pairedAtMs < 0 ||
        lastSeenAtMs < 0 ||
        keyVersion < 1) {
      throw const RemoteException(
        RemoteFailureCode.stateCorrupt,
        'paired device metadata has invalid fields',
      );
    }
    return RemotePairedDeviceMetadata(
      deviceId: deviceId,
      publicKey: publicKey,
      label: label,
      pairedAtMs: pairedAtMs,
      lastSeenAtMs: lastSeenAtMs,
      revoked: revoked,
      keyVersion: keyVersion,
    );
  }
}

class RemoteState {
  const RemoteState({
    this.remoteEnabled = false,
    this.identity,
    this.pairedDevices = const <RemotePairedDeviceMetadata>[],
    this.publicationSequence = 0,
    this.lastPublishedEndpointFingerprint,
  });

  final bool remoteEnabled;
  final RemoteIdentityMetadata? identity;
  final List<RemotePairedDeviceMetadata> pairedDevices;
  final int publicationSequence;
  final String? lastPublishedEndpointFingerprint;

  RemoteState copyWith({
    bool? remoteEnabled,
    RemoteIdentityMetadata? identity,
    bool clearIdentity = false,
    List<RemotePairedDeviceMetadata>? pairedDevices,
    int? publicationSequence,
    String? lastPublishedEndpointFingerprint,
    bool clearLastPublishedEndpointFingerprint = false,
  }) => RemoteState(
    remoteEnabled: remoteEnabled ?? this.remoteEnabled,
    identity: clearIdentity ? null : identity ?? this.identity,
    pairedDevices: pairedDevices ?? this.pairedDevices,
    publicationSequence: publicationSequence ?? this.publicationSequence,
    lastPublishedEndpointFingerprint: clearLastPublishedEndpointFingerprint
        ? null
        : lastPublishedEndpointFingerprint ??
              this.lastPublishedEndpointFingerprint,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': _remoteStateSchemaVersion,
    'remoteEnabled': remoteEnabled,
    'identity': identity?.toJson(),
    'pairedDevices': pairedDevices.map((device) => device.toJson()).toList(),
    'publicationSequence': publicationSequence,
    'lastPublishedEndpointFingerprint': lastPublishedEndpointFingerprint,
  };

  static RemoteState fromJson(Object? value) {
    if (value is! Map || value['schemaVersion'] != _remoteStateSchemaVersion) {
      throw const RemoteException(
        RemoteFailureCode.stateCorrupt,
        'unsupported or malformed remote state schema',
      );
    }
    final enabled = value['remoteEnabled'];
    final identityValue = value['identity'];
    final pairedValue = value['pairedDevices'];
    final sequence = value['publicationSequence'];
    final fingerprint = value['lastPublishedEndpointFingerprint'];
    if (enabled is! bool ||
        (identityValue != null && identityValue is! Map) ||
        pairedValue is! List ||
        pairedValue.length > RemoteLimits.maxPairedDevices ||
        sequence is! int ||
        sequence < 0 ||
        (fingerprint != null && fingerprint is! String)) {
      throw const RemoteException(
        RemoteFailureCode.stateCorrupt,
        'remote state has invalid fields',
      );
    }
    return RemoteState(
      remoteEnabled: enabled,
      identity: identityValue == null
          ? null
          : RemoteIdentityMetadata.fromJson(identityValue),
      pairedDevices: pairedValue
          .map(RemotePairedDeviceMetadata.fromJson)
          .toList(growable: false),
      publicationSequence: sequence,
      lastPublishedEndpointFingerprint: fingerprint as String?,
    );
  }
}

abstract interface class RemoteStateStore {
  Future<RemoteState> load();
  Future<void> save(RemoteState state);
}

class InMemoryRemoteStateStore implements RemoteStateStore {
  InMemoryRemoteStateStore([RemoteState? initial])
    : _state = initial ?? const RemoteState();

  RemoteState _state;

  @override
  Future<RemoteState> load() async => _state;

  @override
  Future<void> save(RemoteState state) async {
    _state = state;
  }
}

class FileRemoteStateStore implements RemoteStateStore {
  FileRemoteStateStore(Directory root)
    : _file = File('${root.path}${Platform.pathSeparator}state.json'),
      _backup = File('${root.path}${Platform.pathSeparator}state.json.bak');

  final File _file;
  final File _backup;

  @override
  Future<RemoteState> load() async {
    final source = await _file.exists()
        ? _file
        : (await _backup.exists() ? _backup : null);
    if (source == null) {
      return const RemoteState();
    }
    try {
      final decoded = jsonDecode(await source.readAsString());
      return RemoteState.fromJson(decoded);
    } on RemoteException {
      rethrow;
    } on Object {
      throw const RemoteException(
        RemoteFailureCode.stateCorrupt,
        'remote state cannot be decoded',
      );
    }
  }

  @override
  Future<void> save(RemoteState state) async {
    final parent = _file.parent;
    await parent.create(recursive: true);
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(jsonEncode(state.toJson()), flush: true);
    try {
      if (await _backup.exists()) {
        await _backup.delete();
      }
      if (await _file.exists()) {
        await _file.rename(_backup.path);
      }
      await temp.rename(_file.path);
      if (await _backup.exists()) {
        await _backup.delete();
      }
    } on Object {
      if (await temp.exists()) {
        await temp.delete();
      }
      if (!await _file.exists() && await _backup.exists()) {
        await _backup.rename(_file.path);
      }
      rethrow;
    }
  }
}
