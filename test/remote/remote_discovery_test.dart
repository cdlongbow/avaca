import 'package:avaca/remote/remote.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

import 'support/remote_fakes.dart';

void main() {
  test('LAN endpoints require private or link-local address scope', () {
    expect(
      () => RemoteEndpoint(
        host: '8.8.8.8',
        port: 4587,
        kind: RemoteEndpointKind.lanIpv4,
      ),
      throwsA(isA<RemoteException>()),
    );
    expect(
      () => RemoteEndpoint(
        host: '2001:4860:4860::8888',
        port: 4587,
        kind: RemoteEndpointKind.lanIpv6,
      ),
      throwsA(isA<RemoteException>()),
    );
    expect(
      RemoteEndpoint(
        host: '172.16.4.20',
        port: 4587,
        kind: RemoteEndpointKind.lanIpv4,
      ).isLan,
      isTrue,
    );
    expect(
      RemoteEndpoint(
        host: 'fe80::20',
        port: 4587,
        kind: RemoteEndpointKind.lanIpv6,
      ).isLan,
      isTrue,
    );
  });

  test(
    'discovery records use bounded binary fields and encrypted envelopes',
    () async {
      final clock = FixedRemoteClock(DateTime.utc(2026, 1, 1, 12));
      final crypto = RemoteCrypto(random: FixedRemoteRandom(4));
      final codec = RemoteDiscoveryCodec(crypto: crypto, clock: clock);
      final record = RemoteDiscoveryRecord(
        sequence: 7,
        expiresAt: clock.now.add(const Duration(hours: 1)),
        endpoints: <RemoteEndpoint>[
          RemoteEndpoint(
            host: '192.168.1.20',
            port: 4587,
            kind: RemoteEndpointKind.lanIpv4,
          ),
          RemoteEndpoint(
            host: 'fd00::20',
            port: 4587,
            kind: RemoteEndpointKind.lanIpv6,
          ),
        ],
      );
      final pairSecret = List<int>.generate(32, (index) => index + 10);
      final envelope = await codec.seal(pairSecret: pairSecret, record: record);
      final wire = codec.encodeEnvelope(envelope);
      expect(wire.length, lessThanOrEqualTo(1024));
      expect(wire, isNot(contains('192.168.1.20'.codeUnits)));

      final decodedEnvelope = codec.decodeEnvelope(wire);
      final opened = await codec.open(
        pairSecret: pairSecret,
        envelope: decodedEnvelope,
        minimumSequence: 6,
      );
      expect(opened.sequence, 7);
      expect(
        opened.endpoints.map((endpoint) => endpoint.host),
        contains('192.168.1.20'),
      );
      expect(codec.decodeRecord(codec.encodeRecord(record)).sequence, 7);
    },
  );

  test('discovery rejects tampering, stale sequence, and expiry', () async {
    final clock = FixedRemoteClock(DateTime.utc(2026, 1, 1));
    final codec = RemoteDiscoveryCodec(
      crypto: RemoteCrypto(random: FixedRemoteRandom(50)),
      clock: clock,
    );
    final record = RemoteDiscoveryRecord(
      sequence: 2,
      expiresAt: clock.now.add(const Duration(minutes: 10)),
      endpoints: <RemoteEndpoint>[
        RemoteEndpoint(
          host: '10.0.0.4',
          port: 1000,
          kind: RemoteEndpointKind.lanIpv4,
        ),
      ],
    );
    final secret = List<int>.filled(32, 8);
    final envelope = await codec.seal(pairSecret: secret, record: record);
    final tampered = RemoteDiscoveryEnvelope(
      namespace: envelope.namespace,
      ciphertext: RemoteCiphertext(
        nonce: envelope.ciphertext.nonce,
        cipherText: envelope.ciphertext.cipherText,
        mac: Uint8List(16),
      ),
    );
    await expectLater(
      codec.open(pairSecret: secret, envelope: tampered),
      throwsA(isA<RemoteException>()),
    );
    await expectLater(
      codec.open(pairSecret: secret, envelope: envelope, minimumSequence: 2),
      throwsA(isA<RemoteException>()),
    );
    clock.current = clock.now.add(const Duration(minutes: 11));
    await expectLater(
      codec.open(pairSecret: secret, envelope: envelope),
      throwsA(isA<RemoteException>()),
    );
  });
}
