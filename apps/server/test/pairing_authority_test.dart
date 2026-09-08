import 'dart:typed_data';

import 'package:avaca_library/avaca_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'invitation becomes active only after authentication and is one-time',
    () async {
      final now = DateTime.utc(2026, 9, 8, 12);
      final authority = ServerPairingInvitationAuthority(clock: () => now);
      final invitation = authority.issue(
        serverId: 'server-1',
        clientId: 'client-1',
        host: '127.0.0.1',
        port: 4433,
        leafCertificateSha256: Uint8List(32),
      );

      final pending = await authority.resolveSecret('client-1');
      expect(pending, isNotNull);
      expect(await authority.resolveSecret('client-2'), isNull);
      authority.markAuthenticated('client-1');
      final active = await authority.resolveSecret('client-1');
      expect(active, isNotNull);
      expect(active, orderedEquals(pending!));
      expect(authority.encode(invitation), startsWith('AVACA-PAIR-V2.'));

      authority.revoke('client-1');
      expect(await authority.resolveSecret('client-1'), isNull);
      authority.dispose();
    },
  );

  test('expired pending invitations are not resolved', () async {
    var now = DateTime.utc(2026, 9, 8, 12);
    final authority = ServerPairingInvitationAuthority(clock: () => now);
    authority.issue(
      serverId: 'server-1',
      clientId: 'client-expired',
      host: 'localhost',
      port: 4433,
      leafCertificateSha256: Uint8List(32),
      lifetime: const Duration(minutes: 1),
    );
    now = now.add(const Duration(minutes: 2));
    expect(await authority.resolveSecret('client-expired'), isNull);
    authority.dispose();
  });
}
