import 'dart:convert';
import 'dart:typed_data';

/// Candidate-only data advertised by `_avaca-remote._udp`.
///
/// The TXT record deliberately has no pairing secret and is never sufficient
/// to create a trusted profile.  The invitation remains the authentication
/// and authorization boundary.
final class AvacaRemoteDiscoveryCandidate {
  AvacaRemoteDiscoveryCandidate({
    required this.protocolVersion,
    required this.serverId,
    required this.port,
    required List<int> leafCertificateSha256,
    required List<int> nonce,
  }) : leafCertificateSha256 = Uint8List.fromList(leafCertificateSha256),
       nonce = Uint8List.fromList(nonce) {
    if (protocolVersion != 2) {
      throw const FormatException('unsupported discovery protocol version');
    }
    if (serverId.isEmpty ||
        serverId.length > 256 ||
        !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(serverId)) {
      throw const FormatException('discovery server id is invalid');
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('discovery port is invalid');
    }
    if (this.leafCertificateSha256.length != 32 || this.nonce.length != 16) {
      throw const FormatException('discovery TXT bytes are invalid');
    }
  }

  static const serviceType = '_avaca-remote._udp';

  final int protocolVersion;
  final String serverId;
  final int port;
  final Uint8List leafCertificateSha256;
  final Uint8List nonce;

  Map<String, String> toTxt() => <String, String>{
    'v': protocolVersion.toString(),
    'serverId': serverId,
    'port': port.toString(),
    'certPin': _encode(leafCertificateSha256),
    'nonce': _encode(nonce),
  };

  /// Converts the candidate into an endpoint hint only.  The returned
  /// profile still needs the invitation's client id and secret, so this
  /// method intentionally cannot produce one.
  AvacaRemoteDiscoveryEndpoint endpoint(String host) =>
      AvacaRemoteDiscoveryEndpoint(host: host, port: port);

  static AvacaRemoteDiscoveryCandidate fromTxt(Map<String, String> txt) {
    final allowed = <String>{'v', 'serverId', 'port', 'certPin', 'nonce'};
    if (txt.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('discovery TXT contains an unknown field');
    }
    final version = int.tryParse(txt['v'] ?? '');
    final port = int.tryParse(txt['port'] ?? '');
    if (version == null || port == null) {
      throw const FormatException('discovery TXT endpoint is invalid');
    }
    return AvacaRemoteDiscoveryCandidate(
      protocolVersion: version,
      serverId: txt['serverId'] ?? '',
      port: port,
      leafCertificateSha256: _decode(txt['certPin'] ?? '', 32),
      nonce: _decode(txt['nonce'] ?? '', 16),
    );
  }

  static String _encode(List<int> value) =>
      base64UrlEncode(value).replaceAll('=', '');

  static Uint8List _decode(String value, int length) {
    if (value.isEmpty ||
        value.contains('=') ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw const FormatException('discovery TXT bytes are invalid');
    }
    try {
      final decoded = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(value)),
      );
      if (decoded.length != length || _encode(decoded) != value) {
        throw const FormatException('discovery TXT bytes are invalid');
      }
      return decoded;
    } on Object {
      throw const FormatException('discovery TXT bytes are invalid');
    }
  }
}

final class AvacaRemoteDiscoveryEndpoint {
  const AvacaRemoteDiscoveryEndpoint({required this.host, required this.port});

  final String host;
  final int port;
}

/// A platform discovery result.  Discovery supplies an endpoint candidate
/// only; it cannot create a client profile and never contains the pairing
/// secret.
final class AvacaRemoteDiscoveryEvent {
  const AvacaRemoteDiscoveryEvent({
    required this.candidate,
    required this.endpoint,
  });

  final AvacaRemoteDiscoveryCandidate candidate;
  final AvacaRemoteDiscoveryEndpoint endpoint;

  static AvacaRemoteDiscoveryEvent fromPlatformValue(Object? value) {
    if (value is! Map) {
      throw const FormatException('discovery platform event is invalid');
    }
    final host = value['host']?.toString().trim();
    if (host == null || host.isEmpty || host.length > 512) {
      throw const FormatException('discovery platform host is invalid');
    }
    final rawTxt = value['txt'];
    if (rawTxt is! Map) {
      throw const FormatException('discovery platform TXT is invalid');
    }
    final txt = <String, String>{};
    for (final entry in rawTxt.entries) {
      final key = entry.key?.toString();
      final text = entry.value?.toString();
      if (key == null || text == null || key.isEmpty || text.isEmpty) {
        throw const FormatException('discovery platform TXT is invalid');
      }
      txt[key] = text;
    }
    final candidate = AvacaRemoteDiscoveryCandidate.fromTxt(txt);
    final port = value['port'];
    if (port is! num ||
        !port.isFinite ||
        port != port.toInt() ||
        port.toInt() != candidate.port) {
      throw const FormatException('discovery platform port does not match TXT');
    }
    return AvacaRemoteDiscoveryEvent(
      candidate: candidate,
      endpoint: candidate.endpoint(host),
    );
  }
}

/// Platform discovery is an intentionally injected seam.  Windows supplies
/// DNS-SD and Android supplies `NsdManager`; both only yield candidates and
/// must not persist or trust them without a confirmed invitation.
abstract interface class AvacaRemoteDiscovery {
  Stream<AvacaRemoteDiscoveryCandidate> candidates();
}
