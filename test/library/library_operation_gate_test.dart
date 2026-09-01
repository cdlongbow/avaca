import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:avaca/library/library_operation_gate.dart';

void main() {
  test('serializes concurrent operations sharing one lock path', () async {
    final root = await Directory.systemTemp.createTemp('avaca_operation_gate_');
    final lockPath = '${root.path}${Platform.pathSeparator}library.lock';
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var secondStarted = false;
    try {
      final first = LibraryOperationGate(lockPath: lockPath).run(() async {
        firstStarted.complete();
        await releaseFirst.future;
        return 1;
      });
      await firstStarted.future;
      final second = LibraryOperationGate(lockPath: lockPath).run(() async {
        secondStarted = true;
        return 2;
      });

      await Future<void>.delayed(Duration.zero);
      expect(secondStarted, isFalse);
      releaseFirst.complete();
      expect(await Future.wait([first, second]), [1, 2]);
      expect(secondStarted, isTrue);
    } finally {
      if (root.existsSync()) await root.delete(recursive: true);
    }
  });

  test('releases the queue after an operation throws', () async {
    final root = await Directory.systemTemp.createTemp('avaca_operation_gate_');
    final lockPath = '${root.path}${Platform.pathSeparator}library.lock';
    final gate = LibraryOperationGate(lockPath: lockPath);
    try {
      await expectLater(
        gate.run<void>(() async => throw StateError('expected failure')),
        throwsStateError,
      );
      expect(await gate.run(() async => 'after failure'), 'after failure');
    } finally {
      if (root.existsSync()) await root.delete(recursive: true);
    }
  });
}
