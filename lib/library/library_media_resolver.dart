import 'dart:io';

import 'library_media_locator.dart';
import 'library_repository.dart';

/// Resolves a managed media file from its persisted portable identity.
///
/// Callers may supply an expected Work id for an additional route guard, but
/// they never supply the root or relative paths that determine the file.
final class LibraryMediaResolver {
  LibraryMediaResolver({required this.repository, LibraryMediaLocator? locator})
    : locator = locator ?? LibraryMediaLocator();

  final LibraryRepository repository;
  final LibraryMediaLocator locator;

  Future<ResolvedLibraryMedia> resolveByPortableId(
    String mediaPortableId, {
    int? expectedWorkId,
    String? expectedWorkPortableId,
    bool verifyIntegrity = true,
  }) async {
    final requestedId = mediaPortableId.trim();
    if (requestedId.isEmpty) {
      throw const LibraryLocatorFailure('media portable ID is empty');
    }
    final record = await repository.lookupMediaByPortableId(requestedId);
    if (record == null) {
      throw LibraryLocatorFailure(
        'media portable ID was not found',
        mediaPortableId: requestedId,
      );
    }
    if (record.mediaPortableId != requestedId) {
      throw const LibraryLocatorFailure('media portable ID identity mismatch');
    }
    if (!record.libraryManaged) {
      throw LibraryLocatorFailure(
        'parent Work is not Library-managed',
        mediaPortableId: requestedId,
      );
    }
    if (expectedWorkId != null && record.workId != expectedWorkId) {
      throw LibraryLocatorFailure(
        'media does not belong to the expected Work',
        mediaPortableId: requestedId,
      );
    }
    if (expectedWorkPortableId != null &&
        record.workPortableId != expectedWorkPortableId.trim()) {
      throw LibraryLocatorFailure(
        'media parent Work portable ID does not match',
        mediaPortableId: requestedId,
      );
    }

    final root = _required(record.libraryRoot, 'active LibraryRoot');
    final workPath = _required(record.workRelativePath, 'Work relative path');
    final mediaPath = _required(
      record.mediaRelativePath,
      'media relative path',
    );
    if (record.workPortableId == null || record.workPortableId!.isEmpty) {
      throw LibraryLocatorFailure(
        'parent Work portable ID is missing',
        mediaPortableId: requestedId,
      );
    }
    if (record.workCode == null || record.workCode!.isEmpty) {
      throw LibraryLocatorFailure(
        'parent Work code is missing',
        mediaPortableId: requestedId,
      );
    }

    final resolved = await locator.resolveMedia(
      libraryRoot: root,
      workRelativePath: workPath,
      mediaRelativePath: mediaPath,
      mediaPortableId: requestedId,
    );
    final stat = await File(resolved.absolutePath).stat();
    final expectedSize = record.fileSizeBytes;
    if (expectedSize != null && stat.size != expectedSize) {
      throw LibraryLocatorFailure(
        'media file size does not match the indexed identity',
        libraryRoot: root,
        workRelativePath: workPath,
        mediaRelativePath: mediaPath,
      );
    }
    if (verifyIntegrity) {
      final expectedHash = record.sha256?.trim() ?? '';
      if (expectedHash.isEmpty) {
        throw LibraryLocatorFailure(
          'media file has no indexed SHA-256 integrity value',
          mediaPortableId: requestedId,
        );
      }
      final actualHash = await locator.filesystem.hashFile(
        resolved.absolutePath,
      );
      if (actualHash.toLowerCase() != expectedHash.toLowerCase()) {
        throw LibraryLocatorFailure(
          'media file SHA-256 does not match the indexed identity',
          libraryRoot: root,
          workRelativePath: workPath,
          mediaRelativePath: mediaPath,
        );
      }
    }
    return resolved;
  }

  String _required(String? value, String label) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      throw LibraryLocatorFailure('$label is missing');
    }
    return normalized;
  }
}
