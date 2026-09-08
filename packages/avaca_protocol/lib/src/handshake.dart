import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../avaca_protocol.dart';

class AvacaClientHelloDto {
  const AvacaClientHelloDto({
    required this.clientId,
    required this.clientNonce,
    required this.proof,
  });

  final String clientId;
  final Uint8List clientNonce;
  final Uint8List proof;
}

class AvacaServerHelloDto {
  const AvacaServerHelloDto({
    required this.serverId,
    required this.clientId,
    required this.serverNonce,
    required this.proof,
  });

  final String serverId;
  final String clientId;
  final Uint8List serverNonce;
  final Uint8List proof;
}

class AvacaAuthenticatedDto {
  const AvacaAuthenticatedDto({
    required this.serverId,
    required this.clientId,
    required this.proof,
  });

  final String serverId;
  final String clientId;
  final Uint8List proof;
}

/// Pair-secret handshake helper.  Proofs bind the v2 pre-auth context and the
/// TLS/QUIC channel binding, so a captured pairing proof cannot be replayed on
/// another connection.  The secret is never serialized in any DTO.
class AvacaHandshakeCodec {
  const AvacaHandshakeCodec();

  static const nonceLength = 32;
  static const proofLength = 32;
  static const maxIdBytes = 256;
  static const controlDomain = 'AVACA-REMOTE-V2/CONTROL';
  static const playbackDomain = 'AVACA-REMOTE-V2/PLAYBACK';

  Uint8List encodeClientHello(AvacaClientHelloDto value) {
    _checkId(value.clientId);
    _checkBytes(value.clientNonce, nonceLength, 'client nonce');
    _checkBytes(value.proof, proofLength, 'client proof');
    return _encode({
      'clientId': value.clientId,
      'clientNonce': _b64(value.clientNonce),
      'proof': _b64(value.proof),
    });
  }

  AvacaClientHelloDto decodeClientHello(List<int> payload) {
    final map = _decode(payload);
    return AvacaClientHelloDto(
      clientId: _id(map['clientId']),
      clientNonce: _bytes(map['clientNonce'], nonceLength, 'client nonce'),
      proof: _bytes(map['proof'], proofLength, 'client proof'),
    );
  }

  Uint8List encodeServerHello(AvacaServerHelloDto value) {
    _checkId(value.serverId);
    _checkId(value.clientId);
    _checkBytes(value.serverNonce, nonceLength, 'server nonce');
    _checkBytes(value.proof, proofLength, 'server proof');
    return _encode({
      'serverId': value.serverId,
      'clientId': value.clientId,
      'serverNonce': _b64(value.serverNonce),
      'proof': _b64(value.proof),
    });
  }

  AvacaServerHelloDto decodeServerHello(List<int> payload) {
    final map = _decode(payload);
    return AvacaServerHelloDto(
      serverId: _id(map['serverId']),
      clientId: _id(map['clientId']),
      serverNonce: _bytes(map['serverNonce'], nonceLength, 'server nonce'),
      proof: _bytes(map['proof'], proofLength, 'server proof'),
    );
  }

  Uint8List encodeAuthenticated(AvacaAuthenticatedDto value) {
    _checkId(value.serverId);
    _checkId(value.clientId);
    _checkBytes(value.proof, proofLength, 'authentication proof');
    return _encode({
      'serverId': value.serverId,
      'clientId': value.clientId,
      'proof': _b64(value.proof),
    });
  }

  AvacaAuthenticatedDto decodeAuthenticated(List<int> payload) {
    final map = _decode(payload);
    return AvacaAuthenticatedDto(
      serverId: _id(map['serverId']),
      clientId: _id(map['clientId']),
      proof: _bytes(map['proof'], proofLength, 'authentication proof'),
    );
  }

  Uint8List clientProof({
    required List<int> secret,
    required String clientId,
    required List<int> clientNonce,
    required List<int> channelBinding,
    String domain = controlDomain,
  }) {
    _checkSecret(secret);
    _checkId(clientId);
    _checkBytes(clientNonce, nonceLength, 'client nonce');
    _checkBinding(channelBinding);
    _checkDomain(domain);
    return _mac(
      secret,
      _transcript('client-hello', domain, channelBinding, <List<int>>[
        utf8.encode(clientId),
        clientNonce,
      ]),
    );
  }

  Uint8List serverProof({
    required List<int> secret,
    required String serverId,
    required String clientId,
    required List<int> clientNonce,
    required List<int> serverNonce,
    required List<int> channelBinding,
    String domain = controlDomain,
  }) {
    _checkSecret(secret);
    _checkId(serverId);
    _checkId(clientId);
    _checkBytes(clientNonce, nonceLength, 'client nonce');
    _checkBytes(serverNonce, nonceLength, 'server nonce');
    _checkBinding(channelBinding);
    _checkDomain(domain);
    return _mac(
      secret,
      _transcript('server-hello', domain, channelBinding, <List<int>>[
        utf8.encode(serverId),
        utf8.encode(clientId),
        clientNonce,
        serverNonce,
      ]),
    );
  }

  Uint8List clientAcceptanceProof({
    required List<int> secret,
    required String serverId,
    required String clientId,
    required List<int> clientNonce,
    required List<int> serverNonce,
    required List<int> channelBinding,
    String domain = controlDomain,
  }) {
    _checkSecret(secret);
    _checkId(serverId);
    _checkId(clientId);
    _checkBytes(clientNonce, nonceLength, 'client nonce');
    _checkBytes(serverNonce, nonceLength, 'server nonce');
    _checkBinding(channelBinding);
    _checkDomain(domain);
    return _mac(
      secret,
      _transcript('authenticated', domain, channelBinding, <List<int>>[
        utf8.encode(serverId),
        utf8.encode(clientId),
        clientNonce,
        serverNonce,
      ]),
    );
  }

  bool constantTimeEquals(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = left.length > right.length ? left.length : right.length;
    for (var index = 0; index < length; index++) {
      difference |=
          (index < left.length ? left[index] : 0) ^
          (index < right.length ? right[index] : 0);
    }
    return difference == 0;
  }

  Uint8List _encode(Map<String, Object?> value) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(value)));
    if (bytes.length > AvacaFrameCodec.authMax) {
      throw const AvacaProtocolException('handshake payload exceeds its bound');
    }
    return bytes;
  }

  Map<String, Object?> _decode(List<int> payload) {
    if (payload.length > AvacaFrameCodec.authMax) {
      throw const AvacaProtocolException('handshake payload exceeds its bound');
    }
    try {
      final value = jsonDecode(utf8.decode(payload));
      if (value is! Map) {
        throw const AvacaProtocolException(
          'handshake payload is not an object',
        );
      }
      return value.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
    } on AvacaProtocolException {
      rethrow;
    } on Object {
      throw const AvacaProtocolException('handshake payload is malformed');
    }
  }

  String _id(Object? value) {
    if (value is! String || value.isEmpty || !_safe(value)) {
      throw const AvacaProtocolException('handshake identifier is invalid');
    }
    return value;
  }

  void _checkId(String value) {
    if (value.isEmpty || !_safe(value)) {
      throw const AvacaProtocolException('handshake identifier is invalid');
    }
  }

  bool _safe(String value) =>
      utf8.encode(value).length <= maxIdBytes &&
      !value.contains('\u0000') &&
      RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(value);

  Uint8List _bytes(Object? value, int length, String name) {
    if (value is! String) {
      throw AvacaProtocolException('$name is invalid');
    }
    try {
      final bytes = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(value)),
      );
      _checkBytes(bytes, length, name);
      return bytes;
    } on FormatException {
      throw AvacaProtocolException('$name encoding is invalid');
    }
  }

  String _b64(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

  void _checkBytes(List<int> bytes, int length, String name) {
    if (bytes.length != length) {
      throw AvacaProtocolException('$name must contain exactly $length bytes');
    }
  }

  void _checkSecret(List<int> secret) {
    if (secret.length < 32) {
      throw const AvacaProtocolException('pair secret is too short');
    }
  }

  void _checkBinding(List<int> binding) =>
      _checkBytes(binding, 32, 'channel binding');

  void _checkDomain(String domain) {
    if (domain != controlDomain && domain != playbackDomain) {
      throw const AvacaProtocolException('handshake domain is invalid');
    }
  }

  Uint8List _mac(List<int> secret, List<int> message) => Uint8List.fromList(
    crypto.Hmac(crypto.sha256, secret).convert(message).bytes,
  );

  List<int> _transcript(
    String label,
    String domain,
    List<int> binding,
    List<List<int>> fields,
  ) {
    final output = BytesBuilder(copy: false)
      ..add(utf8.encode(AvacaProtocol.preAuthContext))
      ..add(<int>[0]);
    _addField(output, utf8.encode(label));
    _addField(output, utf8.encode(domain));
    _addField(output, binding);
    for (final field in fields) {
      _addField(output, field);
    }
    return output.takeBytes();
  }

  void _addField(BytesBuilder output, List<int> field) {
    if (field.length > 0xffff) {
      throw const AvacaProtocolException(
        'handshake transcript field is too large',
      );
    }
    output
      ..add(<int>[(field.length >> 8) & 0xff, field.length & 0xff])
      ..add(field);
  }
}
