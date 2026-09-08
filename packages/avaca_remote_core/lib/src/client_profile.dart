import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../avaca_remote_core.dart';

/// The only persisted connection material understood by the v2 client.
/// Secrets and certificate pins are copied on input and never appear in the
/// object string representation or diagnostic fields.
final class AvacaRemoteClientProfile {
  AvacaRemoteClientProfile({
    required this.serverId,
    required this.clientId,
    required this.host,
    required this.port,
    required List<int> leafCertificateSha256,
    required List<int> pairingSecret,
  }) : _leafCertificateSha256 = Uint8List.fromList(leafCertificateSha256),
       _pairingSecret = Uint8List.fromList(pairingSecret) {
    _checkIdentifier(serverId, 'server id');
    _checkIdentifier(clientId, 'client id');
    _checkHost(host);
    if (port < 1 || port > 65535) {
      throw const FormatException('remote profile port is invalid');
    }
    if (_leafCertificateSha256.length != 32) {
      throw const FormatException('remote profile certificate pin is invalid');
    }
    if (_pairingSecret.length != 32) {
      throw const FormatException('remote profile pairing secret is invalid');
    }
  }

  final String serverId;
  final String clientId;
  final String host;
  final int port;
  final Uint8List _leafCertificateSha256;
  final Uint8List _pairingSecret;

  Uint8List get leafCertificateSha256 =>
      Uint8List.fromList(_leafCertificateSha256);

  Uint8List get pairingSecret => Uint8List.fromList(_pairingSecret);

  AvacaRemoteEndpoint get endpoint =>
      AvacaRemoteEndpoint(host: host, port: port);

  /// Wipes this in-memory profile.  Callers must drop all copies returned by
  /// the getters as soon as the connection attempt has completed.
  void dispose() {
    _pairingSecret.fillRange(0, _pairingSecret.length, 0);
    _leafCertificateSha256.fillRange(0, _leafCertificateSha256.length, 0);
  }

  @override
  String toString() =>
      'AvacaRemoteClientProfile(serverId: $serverId, clientId: $clientId, '
      'host: $host, port: $port, leafCertificateSha256: [redacted], '
      'pairingSecret: [redacted])';

  static void _checkIdentifier(String value, String label) {
    if (value.isEmpty ||
        value.length > 256 ||
        !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(value)) {
      throw FormatException('$label is invalid');
    }
  }

  static void _checkHost(String value) {
    if (value.isEmpty ||
        value.length > 255 ||
        value.contains(RegExp(r'[\u0000-\u0020\u007f]')) ||
        value.contains('/') ||
        value.contains('\\')) {
      throw const FormatException('remote profile host is invalid');
    }
  }
}

/// A human-transferable invitation.  It contains no catalog data and is
/// accepted only by an authenticated v2 Server that can atomically consume
/// its invitation id.
final class AvacaPairingInvitation {
  AvacaPairingInvitation({
    required this.serverId,
    required this.clientId,
    required this.host,
    required this.port,
    required List<int> leafCertificateSha256,
    required List<int> pairingSecret,
    required DateTime expiresAt,
    required this.invitationId,
  }) : _leafCertificateSha256 = Uint8List.fromList(leafCertificateSha256),
       _pairingSecret = Uint8List.fromList(pairingSecret),
       expiresAt = expiresAt.toUtc() {
    // Reuse the profile validation without creating a second long-lived
    // secret-bearing object.
    AvacaRemoteClientProfile(
      serverId: serverId,
      clientId: clientId,
      host: host,
      port: port,
      leafCertificateSha256: _leafCertificateSha256,
      pairingSecret: _pairingSecret,
    ).dispose();
    if (invitationId.isEmpty ||
        invitationId.length > 128 ||
        !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(invitationId)) {
      throw const FormatException('pairing invitation id is invalid');
    }
  }

  final String serverId;
  final String clientId;
  final String host;
  final int port;
  final Uint8List _leafCertificateSha256;
  final Uint8List _pairingSecret;
  final DateTime expiresAt;
  final String invitationId;

  Uint8List get leafCertificateSha256 =>
      Uint8List.fromList(_leafCertificateSha256);

  Uint8List get pairingSecret => Uint8List.fromList(_pairingSecret);

  AvacaRemoteClientProfile toProfile() => AvacaRemoteClientProfile(
    serverId: serverId,
    clientId: clientId,
    host: host,
    port: port,
    leafCertificateSha256: _leafCertificateSha256,
    pairingSecret: _pairingSecret,
  );

  void dispose() {
    _pairingSecret.fillRange(0, _pairingSecret.length, 0);
    _leafCertificateSha256.fillRange(0, _leafCertificateSha256.length, 0);
  }
}

/// Canonical `AVACA-PAIR-V2.` invitation codec.  Key order and unpadded
/// base64url are part of the import contract so the same code produces the
/// same QR payload on Windows and Android.
final class AvacaPairingInvitationCodec {
  AvacaPairingInvitationCodec({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const prefix = 'AVACA-PAIR-V2.';
  static const maxLifetime = Duration(minutes: 10);
  static const _keys = <String>[
    'serverId',
    'clientId',
    'host',
    'port',
    'certPin',
    'secret',
    'expiry',
    'invitationId',
  ];

  final DateTime Function() _clock;

  AvacaPairingInvitation issue({
    required String serverId,
    required String clientId,
    required String host,
    required int port,
    required List<int> leafCertificateSha256,
    required List<int> pairingSecret,
    Duration lifetime = maxLifetime,
    String? invitationId,
  }) {
    if (lifetime <= Duration.zero || lifetime > maxLifetime) {
      throw const FormatException('pairing invitation lifetime is invalid');
    }
    return AvacaPairingInvitation(
      serverId: serverId,
      clientId: clientId,
      host: host,
      port: port,
      leafCertificateSha256: leafCertificateSha256,
      pairingSecret: pairingSecret,
      expiresAt: _clock().toUtc().add(lifetime),
      invitationId: invitationId ?? _randomId(),
    );
  }

  String encode(AvacaPairingInvitation invitation) {
    final expiry = invitation.expiresAt.toUtc().millisecondsSinceEpoch;
    final now = _clock().toUtc();
    if (!invitation.expiresAt.isAfter(now) ||
        invitation.expiresAt.isAfter(now.add(maxLifetime))) {
      throw const FormatException('pairing invitation is outside its lifetime');
    }
    final profile = invitation.toProfile();
    profile.dispose();
    final payload = <String, Object?>{
      'serverId': invitation.serverId,
      'clientId': invitation.clientId,
      'host': invitation.host,
      'port': invitation.port,
      'certPin': _encodeBytes(invitation.leafCertificateSha256),
      'secret': _encodeBytes(invitation.pairingSecret),
      'expiry': expiry,
      'invitationId': invitation.invitationId,
    };
    final json = jsonEncode(payload);
    final encoded = base64UrlEncode(utf8.encode(json)).replaceAll('=', '');
    return '$prefix$encoded';
  }

  AvacaPairingInvitation decode(String code) {
    if (!code.startsWith(prefix)) {
      throw const FormatException('pairing invitation prefix is invalid');
    }
    final encoded = code.substring(prefix.length);
    if (encoded.isEmpty ||
        encoded.contains('=') ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(encoded)) {
      throw const FormatException('pairing invitation encoding is invalid');
    }
    late final String json;
    try {
      final bytes = base64Url.decode(base64Url.normalize(encoded));
      if (base64UrlEncode(bytes).replaceAll('=', '') != encoded) {
        throw const FormatException('pairing invitation is not canonical');
      }
      json = utf8.decode(bytes);
    } on Object {
      throw const FormatException('pairing invitation payload is invalid');
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on Object {
      throw const FormatException('pairing invitation JSON is invalid');
    }
    if (decoded is! Map) {
      throw const FormatException('pairing invitation JSON is not an object');
    }
    final map = decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
    if (!_keysEqual(map.keys.toList(growable: false))) {
      throw const FormatException('pairing invitation keys are not canonical');
    }
    final serverId = _string(map['serverId']);
    final clientId = _string(map['clientId']);
    final host = _string(map['host']);
    final port = map['port'];
    final expiry = map['expiry'];
    final invitationId = _string(map['invitationId']);
    if (port is! int || expiry is! int || expiry < 0) {
      throw const FormatException('pairing invitation endpoint is invalid');
    }
    final pin = _decodeBytes(map['certPin'], expectedLength: 32);
    final secret = _decodeBytes(map['secret'], expectedLength: 32);
    final invitation = AvacaPairingInvitation(
      serverId: serverId,
      clientId: clientId,
      host: host,
      port: port,
      leafCertificateSha256: pin,
      pairingSecret: secret,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiry, isUtc: true),
      invitationId: invitationId,
    );
    if (!invitation.expiresAt.isAfter(_clock().toUtc())) {
      invitation.dispose();
      throw const FormatException('pairing invitation has expired');
    }
    return invitation;
  }

  bool _keysEqual(List<String> actual) =>
      actual.length == _keys.length &&
      actual.asMap().entries.every((entry) => entry.value == _keys[entry.key]);

  String _randomId() => base64UrlEncode(
    List<int>.generate(16, (_) => math.Random.secure().nextInt(256)),
  ).replaceAll('=', '');

  String _encodeBytes(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  Uint8List _decodeBytes(Object? value, {required int expectedLength}) {
    if (value is! String || value.isEmpty || value.contains('=')) {
      throw const FormatException('pairing invitation bytes are invalid');
    }
    try {
      final bytes = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(value)),
      );
      if (bytes.length != expectedLength || _encodeBytes(bytes) != value) {
        throw const FormatException('pairing invitation bytes are invalid');
      }
      return bytes;
    } on Object {
      throw const FormatException('pairing invitation bytes are invalid');
    }
  }

  String _string(Object? value) {
    if (value is! String || value.isEmpty || value.length > 256) {
      throw const FormatException('pairing invitation string is invalid');
    }
    return value;
  }
}
