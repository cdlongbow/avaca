import 'dart:typed_data';

import 'package:avaca_remote_core/avaca_remote_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 9, 12);
  final resolver = AvacaPairingEndpointResolver(clock: () => now);

  AvacaPairingInvitation invitation({
    String serverId = 'server-1',
    String host = 'server.local',
    int port = 4433,
    List<int>? pin,
    DateTime? expiresAt,
  }) => AvacaPairingInvitation(
    serverId: serverId,
    clientId: 'client-1',
    host: host,
    port: port,
    leafCertificateSha256: pin ?? List<int>.filled(32, 0x11),
    pairingSecret: List<int>.filled(32, 0x22),
    expiresAt: expiresAt ?? now.add(const Duration(minutes: 5)),
    invitationId: 'invite-1',
  );

  AvacaRemoteDiscoveryEvent event({
    String serverId = 'server-1',
    String host = '192.168.1.20',
    int candidatePort = 4433,
    int endpointPort = 4433,
    List<int>? pin,
  }) {
    final candidate = AvacaRemoteDiscoveryCandidate(
      protocolVersion: 2,
      serverId: serverId,
      port: candidatePort,
      leafCertificateSha256: pin ?? List<int>.filled(32, 0x11),
      nonce: List<int>.filled(16, 0x33),
    );
    return AvacaRemoteDiscoveryEvent(
      candidate: candidate,
      endpoint: AvacaRemoteDiscoveryEndpoint(host: host, port: endpointPort),
    );
  }

  test('exact identity match replaces only the invitation host', () {
    final source = invitation();
    final candidate = event();
    final profile = resolver.createProfile(
      source,
      selectedMatchingCandidate: candidate,
    );

    expect(profile.serverId, 'server-1');
    expect(profile.clientId, 'client-1');
    expect(profile.host, '192.168.1.20');
    expect(profile.port, 4433);
    expect(
      profile.leafCertificateSha256,
      orderedEquals(List<int>.filled(32, 0x11)),
    );
    expect(profile.pairingSecret, orderedEquals(List<int>.filled(32, 0x22)));
    source.dispose();
    profile.dispose();
  });

  test('zero matches keeps the direct invitation endpoint', () {
    final source = invitation();
    final matches = resolver
        .matchingCandidates(source, <AvacaRemoteDiscoveryEvent>[
          event(serverId: 'other-server'),
          event(pin: Uint8List.fromList(List<int>.filled(32, 0x44))),
          event(candidatePort: 4434, endpointPort: 4434),
        ]);
    expect(matches, isEmpty);

    final profile = resolver.createProfile(source);
    expect(profile.host, 'server.local');
    expect(profile.port, 4433);
    source.dispose();
    profile.dispose();
  });

  test('multiple exact matches are returned for explicit UI selection', () {
    final source = invitation();
    final matches = resolver.matchingCandidates(
      source,
      <AvacaRemoteDiscoveryEvent>[
        event(host: '192.168.1.20'),
        event(host: '192.168.1.21'),
      ],
    );
    expect(matches, hasLength(2));
    expect(
      matches.map((value) => value.endpoint.host),
      containsAll(<String>['192.168.1.20', '192.168.1.21']),
    );
    source.dispose();
  });

  test(
    'server, pin, candidate port, and endpoint port mismatches never match',
    () {
      final source = invitation();
      expect(
        resolver.matchingCandidates(source, <AvacaRemoteDiscoveryEvent>[
          event(serverId: 'other-server'),
          event(pin: List<int>.filled(32, 0x44)),
          event(candidatePort: 4434),
          event(endpointPort: 4434),
        ]),
        isEmpty,
      );
      expect(
        () => resolver.createProfile(
          source,
          selectedMatchingCandidate: event(serverId: 'other-server'),
        ),
        throwsStateError,
      );
      source.dispose();
    },
  );

  test('expired invitations are rejected before endpoint selection', () {
    final source = invitation(expiresAt: now);
    expect(
      () => resolver.matchingCandidates(source, const []),
      throwsFormatException,
    );
    expect(() => resolver.createProfile(source), throwsFormatException);
    source.dispose();
  });
}
