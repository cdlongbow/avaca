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

  test('returns a recoverable busy code when the queue wait times out', () async {
    final root = await Directory.systemTemp.createTemp('avaca_operation_gate_');
    final lockPath = '${root.path}${Platform.pathSeparator}library.lock';
    final release = Completer<void>();
    final gate = LibraryOperationGate(lockPath: lockPath);
    var thirdStarted = false;
    try {
      final first = gate.run(() async {
        await release.future;
        return 1;
      });
      await expectLater(
        gate.run(
          () async => 2,
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(
          isA<LibraryOperationBusyException>().having(
            (error) => error.toString(),
            'code',
            contains(LibraryOperationBusyException.code),
          ),
        ),
      );
      // A timed-out waiter must not release its queue marker early and allow
      // a later operation to overtake the still-running first operation.
      await expectLater(
        gate.run(
          () async {
            thirdStarted = true;
            return 3;
          },
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<LibraryOperationBusyException>()),
      );
      expect(thirdStarted, isFalse);
      release.complete();
      expect(await first, 1);
      expect(await gate.run(() async => 4), 4);
    } finally {
      if (root.existsSync()) await root.delete(recursive: true);
    }
  });
}
