import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'library_filesystem.dart';
import 'library_filename_parser.dart';
import 'library_models.dart';
import 'library_source_access.dart';

/// Android SAF-backed source access.
///
/// A tree/document URI is an opaque capability. It is intentionally never
/// converted into a guessed `/storage/...` path; only the native
/// ContentResolver implementation is allowed to enumerate, copy, or delete
/// the source document.
final class LibraryAndroidStorageAccess implements LibrarySourceAccess {
  LibraryAndroidStorageAccess({
    LibraryFilesystem? filesystem,
    this.parser = const LibraryFilenameParser(),
  }) : filesystem = filesystem ?? LibraryFilesystem();

  static const MethodChannel channel = MethodChannel(
    'com.avaca.avaca/library_storage',
  );

  final LibraryFilesystem filesystem;
  final LibraryFilenameParser parser;

  /// Legacy compatibility for injected raw-path pickers. SAF selections do
  /// not call this method and do not require broad media permission.
  Future<bool> ensureMediaReadAccess() async {
    if (!Platform.isAndroid) return true;
    final granted = await channel.invokeMethod<bool>('requestMediaReadAccess');
    return granted ?? false;
  }

  @override
  Future<LibrarySourceLocator?> pickFolder() async {
    if (!Platform.isAndroid) return null;
    final raw = await channel.invokeMethod<Object?>('pickLibraryTree');
    if (raw == null) return null;
    final map = _map(raw, 'pickLibraryTree');
    final treeUri = _requiredString(map, 'treeUri');
    final displayName = _optionalString(map['displayName']) ?? 'Android folder';
    _validateUri(treeUri, 'treeUri');
    return LibraryAndroidTreeSourceLocator(
      treeUri: treeUri,
      displayName: displayName,
    );
  }

  @override
  Future<List<LibraryScanEntry>> scan(LibrarySourceLocator source) async {
    if (!Platform.isAndroid) {
      throw const LibrarySourceAccessException(
        'Android SAF source access is only available on Android',
      );
    }
    if (source is! LibraryAndroidTreeSourceLocator) {
      throw const LibrarySourceAccessException(
        'Android source access received a non-tree folder locator',
      );
    }
    final raw = await channel.invokeMethod<Object?>('listLibraryDocuments', {
      'treeUri': source.treeUri,
    });
    if (raw is! List) {
      throw const LibrarySourceAccessException(
        'Android source listing returned an invalid result',
      );
    }
    final entries = <LibraryScanEntry>[];
    final seen = <String>{};
    for (final value in raw) {
      final map = _map(value, 'listLibraryDocuments');
      final documentUri = _requiredString(map, 'documentUri');
      final treeUri = _optionalString(map['treeUri']) ?? source.treeUri;
      final displayName = _requiredString(map, 'displayName');
      final relativePath = _optionalString(map['relativePath']) ?? displayName;
      final isDirectory = map['isDirectory'] == true;
      if (isDirectory || !seen.add(documentUri)) continue;
      _validateUri(documentUri, 'documentUri');
      final extension = path.extension(displayName).toLowerCase();
      final extensionWithoutDot = extension.startsWith('.')
          ? extension.substring(1)
          : extension;
      if (!LibraryFilenameParser.supportedExtensions.contains(
        extensionWithoutDot,
      )) {
        continue;
      }
      final modifiedAt = _dateFromMillis(map['modifiedAtEpochMs']);
      entries.add(
        LibraryScanEntry(
          sourcePath: documentUri,
          sourceLocator: LibraryAndroidDocumentSourceEntryLocator(
            treeUri: treeUri,
            documentUri: documentUri,
            relativePath: normalizedSourceRelativePath(relativePath),
            displayName: displayName,
          ),
          originalFileName: displayName,
          sizeBytes: _optionalInt(map['sizeBytes']) ?? 0,
          modifiedAt: modifiedAt,
          createdAt: null,
          parseResult: parser.parse(displayName),
        ),
      );
    }
    entries.sort(
      (left, right) => left.sourceLocator.displayName.toLowerCase().compareTo(
        right.sourceLocator.displayName.toLowerCase(),
      ),
    );
    return List.unmodifiable(entries);
  }

  @override
  Future<LibrarySourceSnapshot> snapshot(
    LibrarySourceEntryLocator entry,
  ) async {
    final locator = _androidEntry(entry);
    final raw = await channel.invokeMethod<Object?>('statLibraryDocument', {
      'treeUri': locator.treeUri,
      'documentUri': locator.documentUri,
    });
    final map = _map(raw, 'statLibraryDocument');
    if (map['exists'] != true) {
      throw const LibrarySourceAccessException(
        'source document does not exist',
      );
    }
    return LibrarySourceSnapshot(
      locator: locator,
      sizeBytes: _optionalInt(map['sizeBytes']) ?? 0,
      modifiedAt: _dateFromMillis(map['modifiedAtEpochMs']),
      createdAt: null,
      changedAt: _dateFromMillis(map['modifiedAtEpochMs']),
    );
  }

  @override
  Future<String> copyToFile(
    LibrarySourceEntryLocator entry,
    String destinationPath, {
    LibrarySourceSnapshot? expectedSnapshot,
    void Function(int bytes)? onBytes,
  }) async {
    final locator = _androidEntry(entry);
    final before = await snapshot(locator);
    if (expectedSnapshot != null && !before.matches(expectedSnapshot)) {
      throw const LibrarySourceAccessException('source changed before copying');
    }
    final destination = filesystem.absolutePath(destinationPath);
    final raw = await channel
        .invokeMethod<Object?>('copyLibraryDocumentToPath', {
          'treeUri': locator.treeUri,
          'documentUri': locator.documentUri,
          'destinationPath': destination,
        });
    final result = _map(raw, 'copyLibraryDocumentToPath');
    final copiedBytes = _optionalInt(result['sizeBytes']);
    final localSnapshot = await filesystem.snapshot(destination);
    if (copiedBytes != null && copiedBytes != localSnapshot.sizeBytes) {
      throw const LibrarySourceAccessException(
        'materialized source size verification failed',
      );
    }
    final after = await snapshot(locator);
    if (!before.matches(after)) {
      throw const LibrarySourceAccessException('source changed while copying');
    }
    onBytes?.call(localSnapshot.sizeBytes);
    return filesystem.hashFile(destination);
  }

  @override
  Future<LibrarySourceDeleteResult> delete(
    LibrarySourceEntryLocator entry, {
    required LibrarySourceSnapshot expectedSnapshot,
  }) async {
    final locator = _androidEntry(entry);
    LibrarySourceSnapshot before;
    try {
      before = await snapshot(locator);
    } on LibrarySourceAccessException catch (error) {
      if (error.message == 'source document does not exist') {
        return const LibrarySourceDeleteResult(
          outcome: LibrarySourceDeleteOutcome.alreadyMissing,
        );
      }
      return LibrarySourceDeleteResult(
        outcome: LibrarySourceDeleteOutcome.unknown,
        message: error.message,
      );
    }
    if (!before.matches(expectedSnapshot)) {
      return const LibrarySourceDeleteResult(
        outcome: LibrarySourceDeleteOutcome.unchanged,
        message: 'source changed before deletion',
      );
    }
    try {
      await channel.invokeMethod<Object?>('deleteLibraryDocument', {
        'treeUri': locator.treeUri,
        'documentUri': locator.documentUri,
      });
    } on PlatformException catch (error) {
      return LibrarySourceDeleteResult(
        outcome: _deleteOutcomeForCode(error.code),
        message: 'source deletion failed',
      );
    } on Object {
      return const LibrarySourceDeleteResult(
        outcome: LibrarySourceDeleteOutcome.unknown,
        message: 'source deletion failed',
      );
    }
    try {
      await snapshot(locator);
      return const LibrarySourceDeleteResult(
        outcome: LibrarySourceDeleteOutcome.unchanged,
        message: 'source still exists after deletion',
      );
    } on LibrarySourceAccessException catch (error) {
      if (error.message == 'source document does not exist') {
        return const LibrarySourceDeleteResult(
          outcome: LibrarySourceDeleteOutcome.deleted,
        );
      }
      return LibrarySourceDeleteResult(
        outcome: LibrarySourceDeleteOutcome.unknown,
        message: error.message,
      );
    }
  }

  LibraryAndroidDocumentSourceEntryLocator _androidEntry(
    LibrarySourceEntryLocator entry,
  ) {
    if (entry is LibraryAndroidDocumentSourceEntryLocator) return entry;
    throw const LibrarySourceAccessException(
      'Android source access received a non-document locator',
    );
  }

  static Map<String, Object?> _map(Object? value, String operation) {
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw LibrarySourceAccessException(
      'Android $operation returned an invalid result',
    );
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = _optionalString(map[key]);
    if (value == null || value.isEmpty) {
      throw LibrarySourceAccessException(
        'Android source result is missing $key',
      );
    }
    return value;
  }

  static String? _optionalString(Object? value) =>
      value is String ? value.trim() : value?.toString().trim();

  static int? _optionalInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static DateTime? _dateFromMillis(Object? value) {
    final millis = _optionalInt(value);
    if (millis == null || millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  static void _validateUri(String value, String label) {
    if (!value.startsWith('content://')) {
      throw LibrarySourceAccessException('Android $label is not a content URI');
    }
  }

  static LibrarySourceDeleteOutcome _deleteOutcomeForCode(String code) {
    return switch (code) {
      'PERMISSION_DENIED' => LibrarySourceDeleteOutcome.denied,
      'DOCUMENT_NOT_FOUND' => LibrarySourceDeleteOutcome.alreadyMissing,
      _ => LibrarySourceDeleteOutcome.unknown,
    };
  }
}
