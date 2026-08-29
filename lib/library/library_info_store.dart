import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'library_filesystem.dart';
import 'library_models.dart';
import 'library_repository.dart';

class LibraryInfoStore {
  LibraryInfoStore({LibraryFilesystem? filesystem})
    : filesystem = filesystem ?? LibraryFilesystem();

  final LibraryFilesystem filesystem;

  Future<void> write(
    Directory workDirectory,
    LibraryInfoDocument document,
  ) async {
    if (document.schemaVersion != 1) {
      throw const FormatException('unsupported info.json schema');
    }
    _validatePortableDocument(document);
    await filesystem.writeJsonAtomically(
      path.join(workDirectory.absolute.path, 'info.json'),
      document.toJson(),
    );
  }

  Future<LibraryInfoDocument> read(File infoFile) async {
    final decoded = jsonDecode(await infoFile.readAsString());
    final document = LibraryInfoDocument.fromJson(decoded);
    _validatePortableDocument(document);
    return document;
  }

  void _validatePortableDocument(LibraryInfoDocument document) {
    if (document.workId.trim().isEmpty || document.code.trim().isEmpty) {
      throw const FormatException('info.json requires work identity');
    }
    if (document.libraryRelativePath.trim().isNotEmpty) {
      filesystem.validateRelativePath(document.libraryRelativePath);
    }
    for (final media in document.media) {
      filesystem.validateRelativePath(media.relativePath);
      if (media.relativePath.contains(':') ||
          media.relativePath.startsWith('/')) {
        throw const FormatException(
          'info.json cannot contain an absolute media path',
        );
      }
    }
    for (final imagePath in document.images.values.whereType<String>()) {
      filesystem.validateRelativePath(imagePath);
    }
  }
}

class LibraryReindexReport {
  const LibraryReindexReport({
    required this.scannedInfoFiles,
    required this.indexedDocuments,
    required this.skippedDocuments,
    required this.errors,
  });

  final int scannedInfoFiles;
  final int indexedDocuments;
  final int skippedDocuments;
  final List<String> errors;
}

/// Rebuilds the SQLite index from portable work folders.  Generated actress
/// links and staging directories are never followed as data sources.
class LibraryReindexService {
  LibraryReindexService({
    required this.repository,
    LibraryInfoStore? infoStore,
    LibraryFilesystem? filesystem,
  }) : filesystem = filesystem ?? LibraryFilesystem(),
       infoStore = infoStore ?? LibraryInfoStore(filesystem: filesystem);

  final LibraryRepository repository;
  final LibraryFilesystem filesystem;
  final LibraryInfoStore infoStore;

  Future<LibraryReindexReport> reindex(String rootPath) async {
    final root = filesystem.absolutePath(rootPath);
    filesystem.validateRoot(root);
    final directory = Directory(root);
    if (!await directory.exists()) {
      throw LibraryFilesystemException(
        'library root does not exist',
        pathValue: root,
      );
    }
    var scanned = 0;
    var indexed = 0;
    var skipped = 0;
    final errors = <String>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File ||
          path.basename(entity.path).toLowerCase() != 'info.json') {
        continue;
      }
      final workDirectory = Directory(path.dirname(entity.path));
      final relativeWorkPath = path.relative(workDirectory.path, from: root);
      if (relativeWorkPath.isEmpty || _isStaging(relativeWorkPath)) continue;
      scanned++;
      try {
        final document = await infoStore.read(entity);
        final declaredRelativePath = document.libraryRelativePath.trim();
        if (declaredRelativePath.isNotEmpty) {
          final declaredWorkPath = path.normalize(
            path.join(
              root,
              declaredRelativePath.replaceAll('/', path.separator),
            ),
          );
          if (!filesystem.isWithin(root, declaredWorkPath) ||
              !filesystem.samePath(declaredWorkPath, workDirectory.path)) {
            throw FormatException(
              'info.json libraryRelativePath does not match its folder',
            );
          }
        }
        for (final media in document.media) {
          final candidate = path.normalize(
            path.join(
              workDirectory.path,
              media.relativePath.replaceAll('/', path.separator),
            ),
          );
          if (!filesystem.isWithin(workDirectory.path, candidate) ||
              await FileSystemEntity.type(candidate, followLinks: false) !=
                  FileSystemEntityType.file) {
            throw FormatException(
              'media file is missing: ${media.relativePath}',
            );
          }
          if (media.sha256.isNotEmpty &&
              await filesystem.hashFile(candidate) != media.sha256) {
            throw FormatException(
              'media hash does not match info.json: ${media.relativePath}',
            );
          }
        }
        final effective = document.copyWith(
          libraryRelativePath: document.libraryRelativePath.isEmpty
              ? relativeWorkPath.replaceAll('\\', '/')
              : document.libraryRelativePath,
        );
        await repository.commitInfoDocument(effective, libraryRoot: root);
        indexed++;
      } on Object catch (error) {
        skipped++;
        errors.add('${entity.path}: $error');
      }
    }
    return LibraryReindexReport(
      scannedInfoFiles: scanned,
      indexedDocuments: indexed,
      skippedDocuments: skipped,
      errors: List.unmodifiable(errors),
    );
  }

  bool _isStaging(String relativePath) => relativePath
      .replaceAll('\\', '/')
      .split('/')
      .any(
        (segment) =>
            segment == '.__avaca_importing' || segment.startsWith('.__avaca_'),
      );
}
