import 'dart:io';

import 'package:path/path.dart' as path;

import 'library_filesystem.dart';

/// A single, fail-closed resolver for portable Library media paths.
///
/// Work paths are relative to the authorized LibraryRoot. Media paths are
/// relative to the resolved Work directory. Neither relative value is an
/// identity: the media portable ID remains stable when the absolute root is
/// moved.
final class LibraryMediaLocator {
  LibraryMediaLocator({LibraryFilesystem? filesystem})
    : filesystem = filesystem ?? LibraryFilesystem();

  final LibraryFilesystem filesystem;

  String validateWorkRelativePath(String value) =>
      _validateRelative(value, 'Work path');

  String validateMediaRelativePath(String value) =>
      _validateRelative(value, 'Media path');

  ResolvedLibraryWorkPath resolveWorkPath({
    required String libraryRoot,
    required String workRelativePath,
  }) {
    final root = filesystem.absolutePath(libraryRoot);
    filesystem.validateRoot(root);
    final relative = validateWorkRelativePath(workRelativePath);
    final absolute = path.normalize(
      path.join(root, relative.replaceAll('/', path.separator)),
    );
    _requireWithin(root, absolute, 'Work path escapes LibraryRoot');
    return ResolvedLibraryWorkPath(
      libraryRoot: root,
      workRelativePath: relative,
      absolutePath: absolute,
    );
  }

  Future<ResolvedLibraryMedia> resolveMedia({
    required String libraryRoot,
    required String workRelativePath,
    required String mediaRelativePath,
    String? mediaPortableId,
  }) async {
    final work = resolveWorkPath(
      libraryRoot: libraryRoot,
      workRelativePath: workRelativePath,
    );
    final relative = validateMediaRelativePath(mediaRelativePath);
    final absolute = path.normalize(
      path.join(work.absolutePath, relative.replaceAll('/', path.separator)),
    );
    _requireWithin(work.absolutePath, absolute, 'Media path escapes Work');
    await filesystem.validateNoSymbolicLinks(work.libraryRoot, absolute);
    if (await FileSystemEntity.type(absolute, followLinks: false) !=
        FileSystemEntityType.file) {
      throw LibraryLocatorFailure(
        'media file is unavailable',
        libraryRoot: work.libraryRoot,
        workRelativePath: work.workRelativePath,
        mediaRelativePath: relative,
      );
    }
    return ResolvedLibraryMedia(
      libraryRoot: work.libraryRoot,
      workRelativePath: work.workRelativePath,
      mediaRelativePath: relative,
      absolutePath: absolute,
      mediaPortableId: mediaPortableId,
    );
  }

  String _validateRelative(String value, String label) {
    try {
      return filesystem.validateRelativePath(value);
    } on Object catch (error) {
      throw LibraryLocatorFailure('$label is unsafe: $error');
    }
  }

  void _requireWithin(String root, String candidate, String message) {
    if (!filesystem.isWithin(root, candidate)) {
      throw LibraryLocatorFailure(message, libraryRoot: root);
    }
  }
}

class ResolvedLibraryWorkPath {
  const ResolvedLibraryWorkPath({
    required this.libraryRoot,
    required this.workRelativePath,
    required this.absolutePath,
  });

  final String libraryRoot;
  final String workRelativePath;
  final String absolutePath;
}

final class ResolvedLibraryMedia extends ResolvedLibraryWorkPath {
  const ResolvedLibraryMedia({
    required super.libraryRoot,
    required super.workRelativePath,
    required this.mediaRelativePath,
    required super.absolutePath,
    this.mediaPortableId,
  });

  final String mediaRelativePath;
  final String? mediaPortableId;
}

final class LibraryLocatorFailure implements Exception {
  const LibraryLocatorFailure(
    this.message, {
    this.libraryRoot,
    this.workRelativePath,
    this.mediaRelativePath,
  });

  final String message;
  final String? libraryRoot;
  final String? workRelativePath;
  final String? mediaRelativePath;

  @override
  String toString() => 'LibraryLocatorFailure: $message';
}
