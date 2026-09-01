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

  Future<T> run<T>(Future<T> Function() action) =>
      _queue.run(lockPath: lockPath, action: action);
}

final class _LibraryOperationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>({
    required String lockPath,
    required Future<T> Function() action,
  }) {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    return previous.then((_) async {
      try {
        return await _withFileLock(lockPath, action);
      } finally {
        if (!released.isCompleted) released.complete();
      }
    });
  }
}

Future<T> _withFileLock<T>(String lockPath, Future<T> Function() action) async {
  await Directory(path.dirname(lockPath)).create(recursive: true);
  final handle = await File(lockPath).open(mode: FileMode.append);
  var locked = false;
  try {
    await handle.lock(FileLock.exclusive);
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
