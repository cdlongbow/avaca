import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto_hash;

import 'remote_bytes.dart';
import 'remote_crypto.dart';
import 'remote_endpoint.dart';
import 'remote_errors.dart';
import 'remote_limits.dart';

class RemoteDiscoveryRecord {
  const RemoteDiscoveryRecord({
    required this.sequence,
    required this.expiresAt,
    required this.endpoints,
  });

  final int sequence;
  final DateTime expiresAt;
  final List<RemoteEndpoint> endpoints;
}

class RemoteDiscoveryEnvelope {
  const RemoteDiscoveryEnvelope({
    required this.namespace,
    required this.ciphertext,
  });

  final String namespace;
  final RemoteCiphertext ciphertext;
}

abstract interface class RemoteDiscovery {
  Future<void> publish(RemoteDiscoveryEnvelope envelope);
  Future<List<RemoteDiscoveryEnvelope>> lookup(String namespace);
  Future<void> withdraw(String namespace);
  Future<void> close();
}

/// DHT/relay integration is intentionally unavailable in the production
/// composition until an implementation has passed its independent proof.
class UnavailableRemoteDiscovery implements RemoteDiscovery {
  const UnavailableRemoteDiscovery();

  @override
  Future<void> publish(RemoteDiscoveryEnvelope envelope) async {
    throw const RemoteException(
      RemoteFailureCode.unsupported,
      'remote discovery publication is not enabled in this phase',
    );
  }

  @override
  Future<List<RemoteDiscoveryEnvelope>> lookup(String namespace) async {
    throw const RemoteException(
      RemoteFailureCode.unsupported,
      'remote discovery lookup is not enabled in this phase',
    );
  }

  @override
  Future<void> withdraw(String namespace) async {
    throw const RemoteException(
      RemoteFailureCode.unsupported,
      'remote discovery withdrawal is not enabled in this phase',
    );
  }

  @override
  Future<void> close() async {}
}

class RemoteDiscoveryCodec {
  RemoteDiscoveryCodec({RemoteCrypto? crypto, RemoteClock? clock})
    : crypto = crypto ?? RemoteCrypto(),
      clock = clock ?? const SystemRemoteClock();

  static const _recordMagic = <int>[0x41, 0x56, 0x52, 0x44];
  static const _envelopeMagic = <int>[0x41, 0x56, 0x45, 0x31];
  static const _aadPrefix = <int>[
    0x41,
    0x56,
    0x41,
    0x43,
    0x41,
    0x2d,
    0x52,
    0x44,
    0x2d,
    0x31,
  ];

  final RemoteCrypto crypto;
  final RemoteClock clock;
  final RemoteEndpointCodec _endpointCodec = const RemoteEndpointCodec();

  Uint8List encodeRecord(RemoteDiscoveryRecord record) {
    if (record.sequence <= 0 ||
        record.endpoints.length > RemoteLimits.maxDiscoveryEndpoints) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'discovery record sequence or endpoint count is invalid',
      );
    }
    final writer = RemoteByteWriter()..writeBytes(_recordMagic);
    writer.writeUint8(RemoteLimits.protocolVersion);
    writer.writeUint64(record.sequence);
    writer.writeUint64(record.expiresAt.toUtc().millisecondsSinceEpoch);
    writer.writeUint8(record.endpoints.length);
    for (final endpoint in record.endpoints) {
      _endpointCodec.write(writer, endpoint);
    }
    final bytes = writer.takeBytes();
    if (bytes.length > RemoteLimits.maxDiscoveryRecordBytes) {
      throw const RemoteException(
        RemoteFailureCode.frameTooLarge,
        'discovery record exceeds the bounded payload size',
      );
    }
    return bytes;
  }

  RemoteDiscoveryRecord decodeRecord(List<int> encoded) {
    if (encoded.length > RemoteLimits.maxDiscoveryRecordBytes) {
      throw const RemoteException(
        RemoteFailureCode.frameTooLarge,
        'discovery record exceeds the bounded payload size',
      );
    }
    final reader = RemoteByteReader(encoded);
    final magic = reader.readBytes(
      _recordMagic.length,
      maxBytes: _recordMagic.length,
    );
    if (!remoteConstantTimeEquals(magic, _recordMagic) ||
        reader.readUint8() != RemoteLimits.protocolVersion) {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'discovery record header is invalid',
      );
    }
    final sequence = reader.readUint64();
    final expiresAtMs = reader.readUint64();
    final endpointCount = reader.readUint8();
    if (sequence <= 0 || endpointCount > RemoteLimits.maxDiscoveryEndpoints) {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'discovery record sequence or endpoint count is invalid',
      );
    }
    final endpoints = <RemoteEndpoint>[];
    for (var index = 0; index < endpointCount; index++) {
      endpoints.add(_endpointCodec.read(reader));
    }
    reader.requireDone();
    return RemoteDiscoveryRecord(
      sequence: sequence,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMs, isUtc: true),
      endpoints: List<RemoteEndpoint>.unmodifiable(endpoints),
    );
  }

  Future<RemoteDiscoveryEnvelope> seal({
    required List<int> pairSecret,
    required RemoteDiscoveryRecord record,
  }) async {
    final now = clock.now.toUtc();
    if (record.expiresAt.isBefore(now) ||
        record.expiresAt.isAfter(
          now.add(
            RemoteLimits.discoveryLifetime + RemoteLimits.discoveryClockSkew,
          ),
        )) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'discovery record expiry is outside the allowed window',
      );
    }
    final key = await crypto.deriveKey(
      secret: pairSecret,
      info: 'AVACA-REMOTE/DISCOVERY/V1'.codeUnits,
    );
    try {
      final namespace = await _namespaceFor(key);
      final aad = _aad(namespace);
      final ciphertext = await crypto.seal(
        key: key,
        cleartext: encodeRecord(record),
        aad: aad,
      );
      return RemoteDiscoveryEnvelope(
        namespace: namespace,
        ciphertext: ciphertext,
      );
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Future<RemoteDiscoveryRecord> open({
    required List<int> pairSecret,
    required RemoteDiscoveryEnvelope envelope,
    int minimumSequence = 0,
  }) async {
    final key = await crypto.deriveKey(
      secret: pairSecret,
      info: 'AVACA-REMOTE/DISCOVERY/V1'.codeUnits,
    );
    try {
      final expectedNamespace = await _namespaceFor(key);
      if (envelope.namespace != expectedNamespace) {
        throw const RemoteException(
          RemoteFailureCode.authenticationFailed,
          'discovery namespace does not match the pairing',
        );
      }
      final cleartext = await crypto.open(
        key: key,
        ciphertext: envelope.ciphertext,
        aad: _aad(envelope.namespace),
      );
      final record = decodeRecord(cleartext);
      final now = clock.now.toUtc();
      if (record.expiresAt.isBefore(now)) {
        throw const RemoteException(
          RemoteFailureCode.expiredDiscovery,
          'discovery record has expired',
        );
      }
      if (record.sequence <= minimumSequence) {
        throw const RemoteException(
          RemoteFailureCode.staleDiscovery,
          'discovery record is older than the accepted sequence',
        );
      }
      return record;
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Uint8List encodeEnvelope(RemoteDiscoveryEnvelope envelope) {
    final namespaceBytes = utf8.encode(envelope.namespace);
    if (namespaceBytes.isEmpty ||
        namespaceBytes.length > 64 ||
        envelope.ciphertext.nonce.length != 12 ||
        envelope.ciphertext.mac.length != 16 ||
        envelope.ciphertext.cipherText.length >
            RemoteLimits.maxDiscoveryRecordBytes) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'discovery envelope is outside the fixed bounds',
      );
    }
    final writer = RemoteByteWriter()..writeBytes(_envelopeMagic);
    writer.writeUint8(RemoteLimits.protocolVersion);
    writer.writeUint8(namespaceBytes.length);
    writer.writeBytes(namespaceBytes);
    writer.writeBytes(envelope.ciphertext.nonce);
    writer.writeUint16(envelope.ciphertext.cipherText.length);
    writer.writeBytes(envelope.ciphertext.cipherText);
    writer.writeBytes(envelope.ciphertext.mac);
    final encoded = writer.takeBytes();
    if (encoded.length > RemoteLimits.maxDiscoveryEnvelopeBytes) {
      throw const RemoteException(
        RemoteFailureCode.frameTooLarge,
        'discovery envelope exceeds the bounded wire size',
      );
    }
    return encoded;
  }

  RemoteDiscoveryEnvelope decodeEnvelope(List<int> encoded) {
    if (encoded.length > RemoteLimits.maxDiscoveryEnvelopeBytes) {
      throw const RemoteException(
        RemoteFailureCode.frameTooLarge,
        'discovery envelope exceeds the bounded wire size',
      );
    }
    final reader = RemoteByteReader(encoded);
    final magic = reader.readBytes(
      _envelopeMagic.length,
      maxBytes: _envelopeMagic.length,
    );
    if (!remoteConstantTimeEquals(magic, _envelopeMagic) ||
        reader.readUint8() != RemoteLimits.protocolVersion) {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'discovery envelope header is invalid',
      );
    }
    final namespaceLength = reader.readUint8();
    final namespaceBytes = reader.readBytes(namespaceLength, maxBytes: 64);
    final nonce = reader.readBytes(12, maxBytes: 12);
    final ciphertextLength = reader.readUint16();
    final ciphertext = reader.readBytes(
      ciphertextLength,
      maxBytes: RemoteLimits.maxDiscoveryRecordBytes,
    );
    final mac = reader.readBytes(16, maxBytes: 16);
    reader.requireDone();
    try {
      final namespace = utf8.decode(namespaceBytes);
      if (namespace.isEmpty) {
        throw const RemoteException(
          RemoteFailureCode.malformedFrame,
          'discovery namespace is empty',
        );
      }
      return RemoteDiscoveryEnvelope(
        namespace: namespace,
        ciphertext: RemoteCiphertext(
          nonce: nonce,
          cipherText: ciphertext,
          mac: mac,
        ),
      );
    } on FormatException {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'discovery namespace is not valid UTF-8',
      );
    }
  }

  Future<String> _namespaceFor(List<int> key) async {
    final digest = crypto_hash.sha256.convert(<int>[
      ...key,
      ...'AVACA-REMOTE/NAMESPACE/V1'.codeUnits,
    ]).bytes;
    return base64Url.encode(digest.sublist(0, 20)).replaceAll('=', '');
  }

  Uint8List _aad(String namespace) =>
      Uint8List.fromList(<int>[..._aadPrefix, ...utf8.encode(namespace)]);
}
