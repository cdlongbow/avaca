import 'dart:typed_data';

import 'package:avaca_remote_core/avaca_remote_core.dart';
import 'package:test/test.dart';

void main() {
  test('mDNS TXT candidate round trips without a secret', () {
    final candidate = AvacaRemoteDiscoveryCandidate(
      protocolVersion: 2,
      serverId: 'server-1',
      port: 4433,
      leafCertificateSha256: Uint8List.fromList(List<int>.filled(32, 1)),
      nonce: Uint8List.fromList(List<int>.filled(16, 2)),
    );
    final txt = candidate.toTxt();
    expect(
      txt.keys,
      containsAll(<String>['v', 'serverId', 'port', 'certPin', 'nonce']),
    );
    expect(txt.keys, isNot(contains('secret')));
    final decoded = AvacaRemoteDiscoveryCandidate.fromTxt(txt);
    expect(decoded.serverId, candidate.serverId);
    expect(decoded.endpoint('server.local').port, 4433);
  });

  test('mDNS TXT rejects unknown or malformed trust material', () {
    final candidate = AvacaRemoteDiscoveryCandidate(
      protocolVersion: 2,
      serverId: 'server-1',
      port: 4433,
      leafCertificateSha256: Uint8List(32),
      nonce: Uint8List(16),
    );
    expect(
      () => AvacaRemoteDiscoveryCandidate.fromTxt(<String, String>{
        ...candidate.toTxt(),
        'secret': 'nope',
      }),
      throwsFormatException,
    );
    expect(
      () => AvacaRemoteDiscoveryCandidate.fromTxt(<String, String>{
        ...candidate.toTxt(),
        'certPin': 'bad',
      }),
      throwsFormatException,
    );
  });

  test('platform discovery event validates endpoint against TXT', () {
    final candidate = AvacaRemoteDiscoveryCandidate(
      protocolVersion: 2,
      serverId: 'server-1',
      port: 4433,
      leafCertificateSha256: Uint8List.fromList(List<int>.filled(32, 7)),
      nonce: Uint8List.fromList(List<int>.filled(16, 8)),
    );
    final event = AvacaRemoteDiscoveryEvent.fromPlatformValue(<String, Object>{
      'host': '192.168.1.20',
      'port': 4433,
      'txt': candidate.toTxt(),
    });
    expect(event.endpoint.host, '192.168.1.20');
    expect(event.endpoint.port, 4433);
    expect(event.candidate.serverId, 'server-1');

    expect(
      () => AvacaRemoteDiscoveryEvent.fromPlatformValue(<String, Object>{
        'host': '192.168.1.20',
        'port': 4434,
        'txt': candidate.toTxt(),
      }),
      throwsFormatException,
    );
    expect(
      () => AvacaRemoteDiscoveryEvent.fromPlatformValue(<String, Object>{
        'host': '192.168.1.20',
        'txt': candidate.toTxt(),
      }),
      throwsFormatException,
    );
  });
}
