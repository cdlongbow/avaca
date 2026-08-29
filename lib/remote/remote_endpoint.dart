import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'remote_bytes.dart';
import 'remote_errors.dart';
import 'remote_limits.dart';

enum RemoteEndpointKind {
  lanIpv4,
  lanIpv6,
  stunCandidate,
  pcpCandidate,
  natPmpCandidate,
  upnpCandidate,
}

class RemoteEndpoint {
  RemoteEndpoint({required this.host, required this.port, required this.kind}) {
    _validate();
  }

  final String host;
  final int port;
  final RemoteEndpointKind kind;

  bool get isLan =>
      kind == RemoteEndpointKind.lanIpv4 || kind == RemoteEndpointKind.lanIpv6;

  String get fingerprint {
    final bytes = utf8.encode('${kind.name}|$host|$port');
    return base64Url
        .encode(crypto.sha256.convert(bytes).bytes)
        .replaceAll('=', '');
  }

  void _validate() {
    final hostBytes = utf8.encode(host);
    if (host.isEmpty ||
        hostBytes.length > RemoteLimits.maxEndpointHostBytes ||
        host.contains('/') ||
        host.contains('\\') ||
        host.contains(RegExp(r'\s'))) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'endpoint host is invalid',
      );
    }
    if (port <= 0 || port > RemoteLimits.maxEndpointPort) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'endpoint port is invalid',
      );
    }
    final parsed = InternetAddress.tryParse(host);
    switch (kind) {
      case RemoteEndpointKind.lanIpv4:
        if (parsed == null ||
            parsed.type != InternetAddressType.IPv4 ||
            !_isLanIpv4(parsed.rawAddress)) {
          throw const RemoteException(
            RemoteFailureCode.invalidInput,
            'LAN IPv4 endpoint must be a private or link-local address',
          );
        }
      case RemoteEndpointKind.lanIpv6:
        if (parsed == null ||
            parsed.type != InternetAddressType.IPv6 ||
            !_isLanIpv6(parsed.rawAddress)) {
          throw const RemoteException(
            RemoteFailureCode.invalidInput,
            'LAN IPv6 endpoint must be a unique-local or link-local address',
          );
        }
      case RemoteEndpointKind.stunCandidate:
      case RemoteEndpointKind.pcpCandidate:
      case RemoteEndpointKind.natPmpCandidate:
      case RemoteEndpointKind.upnpCandidate:
        break;
    }
  }

  bool _isLanIpv4(List<int> bytes) {
    if (bytes.length != 4) {
      return false;
    }
    final isPrivate =
        bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
    final isLinkLocal = bytes[0] == 169 && bytes[1] == 254;
    return isPrivate || isLinkLocal;
  }

  bool _isLanIpv6(List<int> bytes) {
    if (bytes.length != 16) {
      return false;
    }
    final isUniqueLocal = (bytes[0] & 0xfe) == 0xfc;
    final isLinkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80;
    return isUniqueLocal || isLinkLocal;
  }
}

abstract interface class EndpointCandidateProvider {
  Future<List<RemoteEndpoint>> getCandidates();
}

/// Production placeholder until an endpoint mechanism has a platform proof.
/// It never invents a candidate and never opens a relay.
class UnavailableEndpointCandidateProvider
    implements EndpointCandidateProvider {
  const UnavailableEndpointCandidateProvider();

  @override
  Future<List<RemoteEndpoint>> getCandidates() async {
    throw const RemoteException(
      RemoteFailureCode.unsupported,
      'endpoint candidate discovery is not enabled in this phase',
    );
  }
}

abstract interface class RemoteEndpointChangeSource {
  Stream<List<RemoteEndpoint>> get changes;
  Future<void> close();
}

class NoopRemoteEndpointChangeSource implements RemoteEndpointChangeSource {
  const NoopRemoteEndpointChangeSource();

  @override
  Stream<List<RemoteEndpoint>> get changes =>
      const Stream<List<RemoteEndpoint>>.empty();

  @override
  Future<void> close() async {}
}

class RemoteEndpointCodec {
  const RemoteEndpointCodec();

  void write(RemoteByteWriter writer, RemoteEndpoint endpoint) {
    writer.writeUint8(endpoint.kind.index);
    writer.writeUint16(endpoint.port);
    writer.writeLengthPrefixedBytes(
      utf8.encode(endpoint.host),
      maxBytes: RemoteLimits.maxEndpointHostBytes,
    );
  }

  RemoteEndpoint read(RemoteByteReader reader) {
    final kindValue = reader.readUint8();
    if (kindValue >= RemoteEndpointKind.values.length) {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'endpoint kind is invalid',
      );
    }
    final port = reader.readUint16();
    final hostBytes = reader.readLengthPrefixedBytes(
      maxBytes: RemoteLimits.maxEndpointHostBytes,
    );
    try {
      return RemoteEndpoint(
        host: utf8.decode(hostBytes),
        port: port,
        kind: RemoteEndpointKind.values[kindValue],
      );
    } on FormatException {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'endpoint host is not valid UTF-8',
      );
    }
  }
}
