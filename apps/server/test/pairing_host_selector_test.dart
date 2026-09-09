import 'dart:io';

import 'package:avaca_server/pairing_host_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  InternetAddress address(String value) => InternetAddress(value);

  test('prefers RFC1918 addresses over other non-loopback IPv4 addresses', () {
    expect(
      AvacaPairingHostSelector.selectAllFromAddresses(<InternetAddress>[
        address('8.8.8.8'),
        address('192.168.1.40'),
        address('172.20.1.40'),
        address('10.0.0.40'),
      ]),
      <String>['10.0.0.40', '172.20.1.40', '192.168.1.40', '8.8.8.8'],
    );
  });

  test('excludes loopback, unspecified, and multicast addresses', () {
    expect(
      AvacaPairingHostSelector.selectFromAddresses(<InternetAddress>[
        address('127.0.0.1'),
        address('0.0.0.0'),
        address('224.0.0.1'),
        address('255.255.255.255'),
      ]),
      isNull,
    );
  });

  test('returns the deterministic lowest address within the best scope', () {
    expect(
      AvacaPairingHostSelector.selectFromAddresses(<InternetAddress>[
        address('192.168.1.30'),
        address('192.168.1.20'),
        address('203.0.113.10'),
      ]),
      '192.168.1.20',
    );
  });
}
