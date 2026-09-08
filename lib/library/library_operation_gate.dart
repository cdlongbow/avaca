import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../core/database.dart';

/// Serializes mutations to the portable Library.
///
/// The in-process queue protects multiple Flutter routes or isolates in this
/// process. The lock file protects other app processes. The lock is anchored
/// beside the database rather than inside LibraryRoot because LibraryRoot is
/// user-configurable and can move.
final class LibraryOperationGate {
  LibraryOperationGate({required String lockPath})
    : lockPath = path.normalize(File(lockPath).absolute.path),
      _queue = _queues.putIfAbsent(
        path.normalize(File(lockPath).absolute.path).toLowerCase(),
        _LibraryOperationQueue.new,
      );

  factory LibraryOperationGate.forDatabase(AppDatabase db) =>
      LibraryOperationGate(
        lockPath: path.join(db.baseDir, '.avaca_library_operation.lock'),
      );

  static final Map<String, _LibraryOperationQueue> _queues =
      <String, _LibraryOperationQueue>{};

  final String lockPath;
  final _LibraryOperationQueue _queue;

  /// Runs one Library mutation while bounding both the in-process queue wait
  /// and the cross-process file-lock wait.  A second import must never leave
  /// the Flutter UI waiting forever behind a crashed or abandoned process.
  Future<T> run<T>(
    Future<T> Function() action, {
    Duration timeout = defaultTimeout,
  }) => _queue.run(lockPath: lockPath, action: action, timeout: timeout);

  static const defaultTimeout = Duration(seconds: 10);
}

final class _LibraryOperationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>({
    required String lockPath,
    required Future<T> Function() action,
    required Duration timeout,
  }) {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    return (() async {
      var releaseImmediately = true;
      try {
        try {
          await previous.timeout(timeout);
        } on TimeoutException {
          // Do not let a later operation overtake the operation we timed out
          // behind.  The timed-out entry is removed from execution, but its
          // queue marker is released only after the predecessor completes.
          // Otherwise a third import could enter while the first still owns
          // the cross-process lock.
          releaseImmediately = false;
          previous.then<void>(
            (_) {
              if (!released.isCompleted) released.complete();
            },
            onError: (_, _) {
              if (!released.isCompleted) released.complete();
            },
          );
          throw const LibraryOperationBusyException();
        }
        return await _withFileLock(lockPath, action, timeout: timeout);
      } on TimeoutException {
        throw const LibraryOperationBusyException();
      } finally {
        if (releaseImmediately && !released.isCompleted) {
          released.complete();
        }
      }
    })();
  }
}

/// Stable error code used by UI and automation to offer retry/recovery.
final class LibraryOperationBusyException implements Exception {
  const LibraryOperationBusyException();

  static const code = 'LIBRARY_OPERATION_BUSY';

  @override
  String toString() => '$code: another Library operation is still running';
}

Future<T> _withFileLock<T>(
  String lockPath,
  Future<T> Function() action, {
  required Duration timeout,
}) async {
  await Directory(path.dirname(lockPath)).create(recursive: true);
  final handle = await File(lockPath).open(mode: FileMode.append);
  var locked = false;
  try {
    await handle.lock(FileLock.exclusive).timeout(timeout);
    locked = true;
    return await action();
  } finally {
    if (locked) {
      try {
        await handle.unlock();
      } finally {
        await handle.close();
      }
    } else {
      await handle.close();
    }
  }
}
