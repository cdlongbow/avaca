import 'dart:convert';
import 'dart:typed_data';

import 'package:avaca_remote_core/avaca_remote_core.dart';
import 'package:test/test.dart';

void main() {
  var now = DateTime.utc(2026, 9, 8, 12);
  final codec = AvacaPairingInvitationCodec(clock: () => now);

  test(
    'v2 invitation has a stable canonical round trip and redacts secrets',
    () {
      final invitation = codec.issue(
        serverId: 'server-1',
        clientId: 'client-1',
        host: '127.0.0.1',
        port: 4433,
        leafCertificateSha256: Uint8List.fromList(List<int>.filled(32, 0x11)),
        pairingSecret: Uint8List.fromList(List<int>.filled(32, 0x22)),
        lifetime: const Duration(minutes: 10),
        invitationId: 'invite-1',
      );
      final encoded = codec.encode(invitation);
      expect(encoded, startsWith(AvacaPairingInvitationCodec.prefix));
      expect(encoded.length, lessThan(300));
      final decoded = codec.decode(encoded);
      expect(decoded.serverId, invitation.serverId);
      expect(decoded.clientId, invitation.clientId);
      expect(decoded.host, invitation.host);
      expect(decoded.port, invitation.port);
      expect(decoded.expiresAt, invitation.expiresAt);
      expect(
        decoded.leafCertificateSha256,
        orderedEquals(List<int>.filled(32, 0x11)),
      );
      expect(decoded.pairingSecret, orderedEquals(List<int>.filled(32, 0x22)));
      expect(
        decoded.toProfile().toString(),
        isNot(contains('pairingSecret: [34')),
      );
      expect(codec.encode(decoded), encoded);
      invitation.dispose();
      decoded.dispose();
    },
  );

  test('v2 decoder keeps accepting the original JSON invitation payload', () {
    final payload = <String, Object>{
      'serverId': 'server-legacy',
      'clientId': 'client-legacy',
      'host': '192.168.0.2',
      'port': 4545,
      'certPin': base64UrlEncode(
        List<int>.filled(32, 0x31),
      ).replaceAll('=', ''),
      'secret': base64UrlEncode(List<int>.filled(32, 0x41)).replaceAll('=', ''),
      'expiry': now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
      'invitationId': 'legacy-invite',
    };
    final legacy =
        '${AvacaPairingInvitationCodec.prefix}${base64UrlEncode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}';
    final decoded = codec.decode(legacy);
    expect(decoded.serverId, 'server-legacy');
    expect(decoded.invitationId, 'legacy-invite');
    decoded.dispose();
  });

  test('expired and non-canonical invitations fail closed', () {
    final invitation = codec.issue(
      serverId: 'server-1',
      clientId: 'client-1',
      host: 'localhost',
      port: 4433,
      leafCertificateSha256: Uint8List(32),
      pairingSecret: Uint8List(32),
      lifetime: const Duration(minutes: 1),
      invitationId: 'invite-2',
    );
    final encoded = codec.encode(invitation);
    expect(() => codec.decode('$encoded='), throwsFormatException);
    now = now.add(const Duration(minutes: 1));
    expect(() => codec.decode(encoded), throwsFormatException);
    invitation.dispose();
  });
}
