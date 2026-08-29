import 'dart:io';

import 'package:avaca/remote/remote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows DPAPI protects secrets across a new store instance', () async {
    if (!Platform.isWindows) {
      return;
    }
    final root = await Directory.systemTemp.createTemp('avaca-remote-secret-');
    try {
      final first = WindowsDpapiSecretStore(root);
      final secret = List<int>.generate(32, (index) => index + 1);
      await first.write('identity-key-v1', secret);
      final second = WindowsDpapiSecretStore(root);
      expect(await second.read('identity-key-v1'), secret);
      expect(
        File(
          '${root.path}${Platform.pathSeparator}identity-key-v1.bin',
        ).readAsBytesSync(),
        isNot(secret),
      );
      await first.close();
      await second.close();
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('corrupt protected blob fails closed', () async {
    if (!Platform.isWindows) {
      return;
    }
    final root = await Directory.systemTemp.createTemp(
      'avaca-remote-secret-corrupt-',
    );
    try {
      final path = File(
        '${root.path}${Platform.pathSeparator}identity-key-v1.bin',
      );
      await path.writeAsBytes(<int>[1, 2, 3, 4]);
      final store = WindowsDpapiSecretStore(root);
      await expectLater(
        store.read('identity-key-v1'),
        throwsA(isA<RemoteException>()),
      );
      await store.close();
    } finally {
      await root.delete(recursive: true);
    }
  });
}
