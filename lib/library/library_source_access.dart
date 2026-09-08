import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'library_filesystem.dart';
import 'library_filename_parser.dart';
import 'library_models.dart';

class LibrarySourceAccessException implements Exception {
  const LibrarySourceAccessException(this.message);

  final String message;

  @override
  String toString() => 'LibrarySourceAccessException: $message';
}

enum LibrarySourceDeleteOutcome {
  deleted,
  alreadyMissing,
  denied,
  unchanged,
  unknown,
}

class LibrarySourceDeleteResult {
  const LibrarySourceDeleteResult({required this.outcome, this.message});

  final LibrarySourceDeleteOutcome outcome;
  final String? message;

  bool get isConfirmedDeleted => outcome == LibrarySourceDeleteOutcome.deleted;
}

/// Storage capability for an import source.
///
/// The final AVACA Library remains a normal app-private filesystem.  This
/// interface only abstracts the external source side so Android SAF document
/// URIs are never mistaken for dart:io paths.
abstract interface class LibrarySourceAccess {
  Future<LibrarySourceLocator?> pickFolder();

  Future<List<LibraryScanEntry>> scan(LibrarySourceLocator source);

  Future<LibrarySourceSnapshot> snapshot(LibrarySourceEntryLocator entry);

  /// Copies one source document to an app-private seekable file and returns
  /// its SHA-256 digest.
  Future<String> copyToFile(
    LibrarySourceEntryLocator entry,
    String destinationPath, {
    LibrarySourceSnapshot? expectedSnapshot,
    void Function(int bytes)? onBytes,
  });

  Future<LibrarySourceDeleteResult> delete(
    LibrarySourceEntryLocator entry, {
    required LibrarySourceSnapshot expectedSnapshot,
  });
}

/// Path backend used by Windows, macOS, Linux, and existing unit tests.
final class LibraryPathSourceAccess implements LibrarySourceAccess {
  LibraryPathSourceAccess({
    LibraryFilesystem? filesystem,
    this.parser = const LibraryFilenameParser(),
  }) : filesystem = filesystem ?? LibraryFilesystem();

  final LibraryFilesystem filesystem;
  final LibraryFilenameParser parser;

  @override
  Future<LibrarySourceLocator?> pickFolder() async => null;

  @override
  Future<List<LibraryScanEntry>> scan(LibrarySourceLocator source) {
    if (source is! LibraryPathSourceLocator) {
      throw const LibrarySourceAccessException(
        'path source access received a non-path folder locator',
      );
    }
    return LibraryFolderScanner(
      parser: parser,
      filesystem: filesystem,
    ).scan(source.absolutePath);
  }

  @override
  Future<LibrarySourceSnapshot> snapshot(
    LibrarySourceEntryLocator entry,
  ) async {
    if (entry is! LibraryPathSourceEntryLocator) {
      throw const LibrarySourceAccessException(
        'path source access received a non-path entry locator',
      );
    }
    return filesystem.snapshot(entry.absolutePath);
  }

  @override
  Future<String> copyToFile(
    LibrarySourceEntryLocator entry,
    String destinationPath, {
    LibrarySourceSnapshot? expectedSnapshot,
    void Function(int bytes)? onBytes,
  }) async {
    if (entry is! LibraryPathSourceEntryLocator) {
      throw const LibrarySourceAccessException(
        'path source access received a non-path entry locator',
      );
    }
    final before = await snapshot(entry);
    if (expectedSnapshot != null && !before.matches(expectedSnapshot)) {
      throw const LibrarySourceAccessException('source changed before copying');
    }
    final digest = await filesystem.copyAndHash(
      entry.absolutePath,
      destinationPath,
      expectedSnapshot: before,
      onBytes: onBytes,
    );
    final after = await snapshot(entry);
    if (!before.matches(after)) {
      throw const LibrarySourceAccessException('source changed while copying');
    }
    return digest;
  }

  @override
  Future<LibrarySourceDeleteResult> delete(
    LibrarySourceEntryLocator entry, {
    required LibrarySourceSnapshot expectedSnapshot,
  }) async {
    if (entry is! LibraryPathSourceEntryLocator) {
      return const LibrarySourceDeleteResult(
        outcome: LibrarySourceDeleteOutcome.unknown,
        message: 'path source access received a non-path entry locator',
      );
    }
    LibrarySourceSnapshot before;
    try {
      before = await snapshot(entry);
    } on Object catch (error) {
      // Keep the failure path asynchronous as well; this method is called by
      // the import workflow and must not perform a synchronous filesystem
      // probe on Flutter's frame isolate.
      if (!await File(entry.absolutePath).exists()) {
        return const LibrarySourceDeleteResult(
          outcome: LibrarySourceDeleteOutcome.alreadyMissing,
        );
      }
      return LibrarySourceDeleteResult(
        outcome: LibrarySourceDeleteOutcome.unknown,
        message: _safeError(error),
      );
    }
    if (!before.matches(expectedSnapshot)) {
      return const LibrarySourceDeleteResult(
        outcome: LibrarySourceDeleteOutcome.unchanged,
        message: 'source changed before deletion',
      );
    }
    try {
      await File(entry.absolutePath).delete();
    } on FileSystemException catch (error) {
      return LibrarySourceDeleteResult(
        outcome: error.osError?.errorCode == 13
            ? LibrarySourceDeleteOutcome.denied
            : LibrarySourceDeleteOutcome.unknown,
        message: 'source deletion failed',
      );
    } on Object {
      return const LibrarySourceDeleteResult(
        outcome: LibrarySourceDeleteOutcome.unknown,
        message: 'source deletion failed',
      );
    }
    if (!await File(entry.absolutePath).exists()) {
      return const LibrarySourceDeleteResult(
        outcome: LibrarySourceDeleteOutcome.deleted,
      );
    }
    return const LibrarySourceDeleteResult(
      outcome: LibrarySourceDeleteOutcome.unchanged,
      message: 'source still exists after deletion',
    );
  }

  String _safeError(Object error) => error is LibrarySourceAccessException
      ? error.message
      : 'source access failed';
}

String normalizedSourceRelativePath(String value) =>
    path.normalize(value.replaceAll('\\', '/')).replaceAll('\\', '/');
