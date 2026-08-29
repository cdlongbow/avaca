import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'remote_bytes.dart';
import 'remote_crypto.dart';
import 'remote_errors.dart';
import 'remote_secret_store.dart';
import 'remote_state_store.dart';

const _identitySecretKey = 'identity-key-v1';
const _identitySecretFormatVersion = 1;

class RemoteIdentityRecord {
  RemoteIdentityRecord({
    required this.deviceId,
    required List<int> publicKeyBytes,
    required this.createdAt,
    required this.keyVersion,
    required SimpleKeyPairData keyPair,
  }) : _publicKeyBytes = Uint8List.fromList(publicKeyBytes),
       _keyPair = keyPair;

  final String deviceId;
  final Uint8List _publicKeyBytes;
  final DateTime createdAt;
  final int keyVersion;
  final SimpleKeyPairData _keyPair;

  Uint8List get publicKeyBytes => Uint8List.fromList(_publicKeyBytes);

  Future<List<int>> sign(
    List<int> message, {
    required RemoteCrypto crypto,
  }) async {
    final signature = await crypto.sign(message, keyPair: _keyPair);
    return Uint8List.fromList(signature.bytes);
  }

  void destroy() => _keyPair.destroy();
}

class RemoteIdentityManager {
  RemoteIdentityManager({
    required this.stateStore,
    required this.secretStore,
    RemoteCrypto? crypto,
    RemoteClock? clock,
  }) : crypto = crypto ?? RemoteCrypto(),
       clock = clock ?? const SystemRemoteClock();

  final RemoteStateStore stateStore;
  final RemoteSecretStore secretStore;
  final RemoteCrypto crypto;
  final RemoteClock clock;
  RemoteIdentityRecord? _cached;

  Future<RemoteIdentityRecord> loadOrCreate() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final state = await stateStore.load();
    final metadata = state.identity;
    if (metadata == null) {
      if (state.pairedDevices.isNotEmpty) {
        throw const RemoteException(
          RemoteFailureCode.stateCorrupt,
          'paired devices exist without a local identity',
        );
      }
      final material = await crypto.generateIdentityKeyMaterial();
      final deviceId = base64Url
          .encode(crypto.random.bytes(16))
          .replaceAll('=', '');
      final now = clock.now.toUtc();
      final identity = RemoteIdentityRecord(
        deviceId: deviceId,
        publicKeyBytes: material.publicKeyBytes,
        createdAt: now,
        keyVersion: 1,
        keyPair: crypto.keyPairFromBytes(
          privateKeyBytes: material.privateKeyBytes,
          publicKeyBytes: material.publicKeyBytes,
        ),
      );
      final secretBlob = _encodeSecret(
        privateKeyBytes: material.privateKeyBytes,
        publicKeyBytes: material.publicKeyBytes,
      );
      try {
        await secretStore.write(_identitySecretKey, secretBlob);
      } finally {
        secretBlob.fillRange(0, secretBlob.length, 0);
        material.privateKeyBytes.fillRange(
          0,
          material.privateKeyBytes.length,
          0,
        );
      }
      await stateStore.save(
        state.copyWith(
          identity: RemoteIdentityMetadata(
            deviceId: deviceId,
            publicKey: base64Url
                .encode(material.publicKeyBytes)
                .replaceAll('=', ''),
            createdAtMs: now.millisecondsSinceEpoch,
            keyVersion: 1,
          ),
        ),
      );
      _cached = identity;
      return identity;
    }

    final encoded = await secretStore.read(_identitySecretKey);
    if (encoded == null) {
      throw const RemoteException(
        RemoteFailureCode.secretStorageCorrupt,
        'local identity metadata exists but its protected key is missing',
      );
    }
    if (metadata.keyVersion != 1) {
      encoded.fillRange(0, encoded.length, 0);
      throw const RemoteException(
        RemoteFailureCode.secretStorageCorrupt,
        'local identity key version is unsupported',
      );
    }
    final material = _decodeSecret(encoded);
    encoded.fillRange(0, encoded.length, 0);
    final actualPublic = base64Url
        .encode(material.publicKeyBytes)
        .replaceAll('=', '');
    if (actualPublic != metadata.publicKey) {
      material.privateKeyBytes.fillRange(0, material.privateKeyBytes.length, 0);
      material.publicKeyBytes.fillRange(0, material.publicKeyBytes.length, 0);
      throw const RemoteException(
        RemoteFailureCode.secretStorageCorrupt,
        'protected local identity does not match public metadata',
      );
    }
    final identity = RemoteIdentityRecord(
      deviceId: metadata.deviceId,
      publicKeyBytes: Uint8List.fromList(material.publicKeyBytes),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        metadata.createdAtMs,
        isUtc: true,
      ),
      keyVersion: metadata.keyVersion,
      keyPair: crypto.keyPairFromBytes(
        privateKeyBytes: material.privateKeyBytes,
        publicKeyBytes: material.publicKeyBytes,
      ),
    );
    material.privateKeyBytes.fillRange(0, material.privateKeyBytes.length, 0);
    material.publicKeyBytes.fillRange(0, material.publicKeyBytes.length, 0);
    _cached = identity;
    return identity;
  }

  Future<void> dispose() async {
    _cached?.destroy();
    _cached = null;
    await secretStore.close();
  }

  Uint8List _encodeSecret({
    required List<int> privateKeyBytes,
    required List<int> publicKeyBytes,
  }) {
    final writer = RemoteByteWriter()..writeUint8(_identitySecretFormatVersion);
    writer.writeLengthPrefixedBytes(privateKeyBytes, maxBytes: 32);
    writer.writeLengthPrefixedBytes(publicKeyBytes, maxBytes: 32);
    return writer.takeBytes();
  }

  RemoteIdentityKeyMaterial _decodeSecret(List<int> encoded) {
    try {
      final reader = RemoteByteReader(encoded);
      if (reader.readUint8() != _identitySecretFormatVersion) {
        throw const RemoteException(
          RemoteFailureCode.secretStorageCorrupt,
          'unsupported local identity secret version',
        );
      }
      final privateKey = reader.readLengthPrefixedBytes(maxBytes: 32);
      final publicKey = reader.readLengthPrefixedBytes(maxBytes: 32);
      reader.requireDone();
      if (privateKey.length != 32 || publicKey.length != 32) {
        throw const RemoteException(
          RemoteFailureCode.secretStorageCorrupt,
          'local identity secret has invalid key lengths',
        );
      }
      return RemoteIdentityKeyMaterial(
        privateKeyBytes: privateKey,
        publicKeyBytes: publicKey,
      );
    } on RemoteException {
      rethrow;
    } on Object {
      throw const RemoteException(
        RemoteFailureCode.secretStorageCorrupt,
        'local identity secret is malformed',
      );
    }
  }
}
