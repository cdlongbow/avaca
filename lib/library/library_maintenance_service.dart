import 'dart:io';

import 'package:path/path.dart' as path;

import 'library_filesystem.dart';
import 'library_models.dart';
import 'library_repository.dart';

class LibraryLinkRebuildReport {
  const LibraryLinkRebuildReport({
    required this.created,
    required this.existing,
    required this.failed,
  });

  final int created;
  final int existing;
  final List<String> failed;
}

/// Recreates disposable actress shortcuts from indexed Work relations.  The
/// real work folder and info.json remain the only library authorities.
class LibraryLinkRebuildService {
  LibraryLinkRebuildService({
    required this.repository,
    required this.filesystem,
    required this.shortcutManager,
  });

  final LibraryRepository repository;
  final LibraryFilesystem filesystem;
  final LibraryShortcutManager shortcutManager;

  Future<LibraryLinkRebuildReport> rebuild(String rootPath) async {
    final root = filesystem.absolutePath(rootPath);
    filesystem.validateRoot(root);
    if (!shortcutManager.isSupported) {
      return const LibraryLinkRebuildReport(
        created: 0,
        existing: 0,
        failed: [],
      );
    }
    final database = await repository.db.database;
    var created = 0;
    var existing = 0;
    final failed = <String>[];
    for (final work in await repository.libraryWorks()) {
      final workId = (work['id'] as num?)?.toInt();
      final primaryActressId = (work['primary_actress_id'] as num?)?.toInt();
      final relativeWorkPath = work['library_relative_path']?.toString().trim();
      final code = work['code']?.toString().trim() ?? '';
      if (workId == null ||
          primaryActressId == null ||
          relativeWorkPath == null ||
          relativeWorkPath.isEmpty ||
          code.isEmpty) {
        failed.add('$code: incomplete library index');
        continue;
      }
      try {
        final target = path.normalize(
          path.join(root, relativeWorkPath.replaceAll('/', path.separator)),
        );
        await filesystem.validateNoSymbolicLinks(root, target);
        if (!filesystem.isWithin(root, target) ||
            !await File(path.join(target, 'info.json')).exists()) {
          throw StateError('portable Work folder or info.json is missing');
        }
        final performerRows = await database.query(
          'work_performers',
          columns: const ['name'],
          where: 'work_id = ?',
          whereArgs: [workId],
          orderBy: 'name COLLATE NOCASE ASC',
        );
        for (final performer in performerRows) {
          final name = performer['name']?.toString().trim() ?? '';
          if (name.isEmpty) continue;
          final candidates = await repository.findActressCandidates([name]);
          final candidate = candidates.length == 1 ? candidates.single : null;
          if (candidate == null || candidate.id == primaryActressId) continue;
          final link = path.join(
            root,
            filesystem.safeSegment(name),
            '$code.lnk',
          );
          if (await File(link).exists() || await Directory(link).exists()) {
            existing++;
            continue;
          }
          await shortcutManager.createDirectoryShortcut(
            linkPath: link,
            targetPath: target,
          );
          await repository.recordLibraryLink(
            workId: workId,
            actressPortableId: candidate.portableId,
            relativePath: path.relative(link, from: root).replaceAll('\\', '/'),
            targetRelativePath: path
                .relative(target, from: root)
                .replaceAll('\\', '/'),
            state: 'ready',
          );
          created++;
        }
      } on Object catch (error) {
        failed.add('$code: $error');
      }
    }
    return LibraryLinkRebuildReport(
      created: created,
      existing: existing,
      failed: List.unmodifiable(failed),
    );
  }
}

class LibraryRecoveryReport {
  const LibraryRecoveryReport({
    required this.cleaned,
    required this.repairRequired,
    required this.errors,
  });

  final int cleaned;
  final int repairRequired;
  final List<String> errors;
}

/// Performs conservative crash recovery.  A portable commit is never
/// guessed away: operations that crossed that boundary are left in
/// repairRequired for an explicit reindex/cleanup pass.
class LibraryImportRecoveryService {
  LibraryImportRecoveryService({
    required this.repository,
    required this.filesystem,
  });

  final LibraryRepository repository;
  final LibraryFilesystem filesystem;

  Future<LibraryRecoveryReport> recover() async {
    var cleaned = 0;
    var repairRequired = 0;
    final errors = <String>[];
    for (final operation in await repository.recoverableImportOperations()) {
      final operationId = operation['id']?.toString();
      final root = operation['library_root']?.toString();
      final state = LibraryImportOperationState.fromValue(
        operation['state']?.toString(),
      );
      if (operationId == null || root == null || root.isEmpty) continue;
      try {
        final stagingRoot = path.join(root, '.__avaca_importing');
        final stagingOperation = path.join(stagingRoot, operationId);
        if (state == LibraryImportOperationState.planned ||
            state == LibraryImportOperationState.preflighting ||
            state == LibraryImportOperationState.staging ||
            state == LibraryImportOperationState.copying ||
            state == LibraryImportOperationState.verifying) {
          await filesystem.deleteStagingTree(
            stagingOperation,
            stagingRoot: stagingRoot,
          );
          await repository.updateImportOperation(
            operationId: operationId,
            state: LibraryImportOperationState.cancelledBeforeCommit,
          );
          cleaned++;
        } else {
          await repository.updateImportOperation(
            operationId: operationId,
            state: LibraryImportOperationState.repairRequired,
            error: 'portable import requires filesystem/index reconciliation',
          );
          repairRequired++;
        }
      } on Object catch (error) {
        errors.add('$operationId: $error');
      }
    }
    return LibraryRecoveryReport(
      cleaned: cleaned,
      repairRequired: repairRequired,
      errors: List.unmodifiable(errors),
    );
  }
}
