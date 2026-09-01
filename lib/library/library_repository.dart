import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/database.dart';
import 'library_models.dart';

class LibraryActressCandidate {
  const LibraryActressCandidate({
    required this.id,
    required this.name,
    required this.portableId,
    required this.matchedByAlias,
  });

  final int id;
  final String name;
  final String portableId;
  final bool matchedByAlias;
}

class LibraryWorkCommitResult {
  const LibraryWorkCommitResult({required this.workId, required this.mediaIds});

  final int workId;
  final List<String> mediaIds;
}

/// The DB-authoritative identity needed to resolve one managed media file.
///
/// Nullable fields are intentional: a corrupt or legacy row must reach the
/// resolver so it can fail closed with a useful reason instead of falling
/// back to caller-provided paths.
class LibraryManagedMediaLookup {
  const LibraryManagedMediaLookup({
    required this.mediaRowId,
    required this.mediaPortableId,
    required this.workId,
    required this.libraryManaged,
    required this.workPortableId,
    required this.workCode,
    required this.libraryRoot,
    required this.workRelativePath,
    required this.mediaRelativePath,
    required this.fileSizeBytes,
    required this.sha256,
  });

  final int mediaRowId;
  final String mediaPortableId;
  final int workId;
  final bool libraryManaged;
  final String? workPortableId;
  final String? workCode;
  final String? libraryRoot;
  final String? workRelativePath;
  final String? mediaRelativePath;
  final int? fileSizeBytes;
  final String? sha256;
}

class LibraryRepository {
  LibraryRepository({required this.db, PortableIdGenerator? idGenerator})
    : _idGenerator = idGenerator ?? PortableIdGenerator();

  final AppDatabase db;
  final PortableIdGenerator _idGenerator;

  Future<List<LibraryActressCandidate>> findActressCandidates(
    Iterable<String> names, {
    bool ensurePortableIds = true,
  }) async {
    final database = await db.database;
    final result = <int, LibraryActressCandidate>{};
    for (final rawName in names) {
      final name = rawName.trim();
      if (name.isEmpty) continue;
      final canonicalRows = await database.rawQuery(
        'SELECT id, name, portable_id FROM actresses '
        'WHERE name = ? COLLATE NOCASE',
        [name],
      );
      for (final row in canonicalRows) {
        final candidate = await _candidateFromRow(
          database,
          row,
          false,
          ensurePortableId: ensurePortableIds,
        );
        result[candidate.id] = candidate;
      }
      final aliasRows = await database.rawQuery(
        'SELECT DISTINCT a.id, a.name, a.portable_id '
        'FROM actress_aliases aa INNER JOIN actresses a ON a.id = aa.actress_id '
        'WHERE aa.alias = ? COLLATE NOCASE',
        [name],
      );
      for (final row in aliasRows) {
        final candidate = await _candidateFromRow(
          database,
          row,
          true,
          ensurePortableId: ensurePortableIds,
        );
        result[candidate.id] = result[candidate.id] ?? candidate;
      }
    }
    final values = result.values.toList();
    values.sort((left, right) {
      final nameCompare = left.name.toLowerCase().compareTo(
        right.name.toLowerCase(),
      );
      return nameCompare != 0 ? nameCompare : left.id.compareTo(right.id);
    });
    return List.unmodifiable(values);
  }

  Future<LibraryActressCandidate> _candidateFromRow(
    DatabaseExecutor executor,
    Map<String, Object?> row,
    bool matchedByAlias, {
    required bool ensurePortableId,
  }) async {
    final id = (row['id'] as num?)?.toInt();
    final name = row['name']?.toString().trim() ?? '';
    if (id == null || name.isEmpty) throw StateError('invalid actress row');
    var portableId = row['portable_id']?.toString().trim() ?? '';
    if (portableId.isEmpty && ensurePortableId) {
      portableId = _idGenerator.next();
      await executor.update(
        'actresses',
        {'portable_id': portableId},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    return LibraryActressCandidate(
      id: id,
      name: name,
      portableId: portableId,
      matchedByAlias: matchedByAlias,
    );
  }

  Future<String?> activeLibraryRoot() async {
    final database = await db.database;
    final rows = await database.query(
      'library_roots',
      columns: const ['path'],
      where: 'is_active = 1',
      orderBy: 'modified_at DESC',
      limit: 1,
    );
    return rows.firstOrNull?['path']?.toString();
  }

  Future<String> setActiveLibraryRoot(String rootPath) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final database = await db.database;
    final existing = await database.query(
      'library_roots',
      columns: const ['id'],
      where: 'path = ?',
      whereArgs: [rootPath],
      limit: 1,
    );
    final id = existing.firstOrNull?['id']?.toString() ?? _idGenerator.next();
    await database.transaction((transaction) async {
      await transaction.update('library_roots', {'is_active': 0});
      await transaction.insert('library_roots', {
        'id': id,
        'path': rootPath,
        'is_active': 1,
        'created_at': now,
        'modified_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    return id;
  }

  Future<String?> findActressPortableId(int actressId) async {
    final database = await db.database;
    final rows = await database.query(
      'actresses',
      columns: const ['portable_id'],
      where: 'id = ?',
      whereArgs: [actressId],
      limit: 1,
    );
    final value = rows.firstOrNull?['portable_id']?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<int?> findWorkIdByCode(String code) async {
    final database = await db.database;
    final rows = await database.query(
      'works',
      columns: const ['id'],
      where: 'code = ? COLLATE NOCASE',
      whereArgs: [code.trim().toUpperCase()],
      limit: 1,
    );
    return (rows.firstOrNull?['id'] as num?)?.toInt();
  }

  Future<String?> findWorkPortableIdByCode(String code) async {
    final database = await db.database;
    final rows = await database.query(
      'works',
      columns: const ['portable_id'],
      where: 'code = ? COLLATE NOCASE',
      whereArgs: [code.trim().toUpperCase()],
      limit: 1,
    );
    final value = rows.firstOrNull?['portable_id']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<int?> findWorkIdByPortableId(String portableId) async {
    final database = await db.database;
    final rows = await database.query(
      'works',
      columns: const ['id'],
      where: 'portable_id = ?',
      whereArgs: [portableId],
      limit: 1,
    );
    return (rows.firstOrNull?['id'] as num?)?.toInt();
  }

  /// Looks up a media identity without accepting any filesystem path from the
  /// caller. The active root is read from the same DB snapshot as the media
  /// and parent Work fields.
  Future<LibraryManagedMediaLookup?> lookupMediaByPortableId(
    String portableId,
  ) async {
    final value = portableId.trim();
    if (value.isEmpty) return null;
    final database = await db.database;
    final rows = await database.rawQuery(
      '''
      SELECT mf.id AS media_row_id,
             mf.portable_id AS media_portable_id,
             mf.work_id AS work_id,
             mf.file_size_bytes AS file_size_bytes,
             mf.sha256 AS sha256,
             mf.relative_path AS media_relative_path,
             w.library_managed AS library_managed,
             w.portable_id AS work_portable_id,
             w.code AS work_code,
             w.library_relative_path AS work_relative_path,
             (
               SELECT path
               FROM library_roots
               WHERE is_active = 1
               ORDER BY modified_at DESC
               LIMIT 1
             ) AS library_root
      FROM media_files mf
      INNER JOIN works w ON w.id = mf.work_id
      WHERE mf.portable_id = ? COLLATE BINARY
      ''',
      [value],
    );
    if (rows.length != 1) return null;
    final row = rows.single;
    final mediaRowId = (row['media_row_id'] as num?)?.toInt();
    final workId = (row['work_id'] as num?)?.toInt();
    final mediaId = row['media_portable_id']?.toString().trim() ?? '';
    if (mediaRowId == null || workId == null || mediaId.isEmpty) {
      return null;
    }
    return LibraryManagedMediaLookup(
      mediaRowId: mediaRowId,
      mediaPortableId: mediaId,
      workId: workId,
      libraryManaged: (row['library_managed'] as num?)?.toInt() == 1,
      workPortableId: row['work_portable_id']?.toString().trim(),
      workCode: row['work_code']?.toString().trim(),
      libraryRoot: row['library_root']?.toString().trim(),
      workRelativePath: row['work_relative_path']?.toString().trim(),
      mediaRelativePath: row['media_relative_path']?.toString().trim(),
      fileSizeBytes: (row['file_size_bytes'] as num?)?.toInt(),
      sha256: row['sha256']?.toString().trim(),
    );
  }

  Future<LibraryWorkCommitResult> commitInfoDocument(
    LibraryInfoDocument document, {
    required String libraryRoot,
    String? importOperationId,
  }) async {
    final database = await db.database;
    return database.transaction(
      (transaction) => _commitInfoDocument(
        transaction,
        document,
        libraryRoot: libraryRoot,
        importOperationId: importOperationId,
      ),
    );
  }

  Future<LibraryWorkCommitResult> _commitInfoDocument(
    DatabaseExecutor executor,
    LibraryInfoDocument document, {
    required String libraryRoot,
    String? importOperationId,
  }) async {
    final primaryId = await _resolveOrCreateActress(
      executor,
      portableId: document.primaryActressId,
      name: _primaryName(document),
    );
    final primaryPortableId = await _ensureActressPortableId(
      executor,
      primaryId,
    );
    final existing = await executor.query(
      'works',
      columns: const [
        'id',
        'portable_id',
        'primary_actress_id',
        'library_managed',
      ],
      where: '(portable_id = ? OR code = ? COLLATE NOCASE)',
      whereArgs: [document.workId, document.code.trim().toUpperCase()],
      limit: 1,
    );
    final existingRow = existing.firstOrNull;
    final existingPrimary = (existingRow?['primary_actress_id'] as num?)
        ?.toInt();
    if (existingRow != null &&
        existingPrimary != null &&
        existingPrimary != primaryId) {
      throw StateError('committed library work cannot change primary actress');
    }
    final workId =
        (existingRow?['id'] as num?)?.toInt() ??
        await executor.insert('works', {
          'code': document.code.trim().toUpperCase(),
          'title': _metadataString(document, 'title') ?? document.code,
          'release_date': _metadataString(document, 'releaseDate'),
          'duration_minutes': _metadataInt(document, 'durationMinutes'),
          'studio': _metadataString(document, 'studio'),
          'publisher': _metadataString(document, 'publisher'),
          'series': _metadataString(document, 'series'),
          'portable_id': document.workId,
          'primary_actress_id': primaryId,
          'library_managed': 1,
          'library_relative_path': _relativeWorkPath(document),
        });
    if (existingRow != null) {
      await executor.update(
        'works',
        {
          'code': document.code.trim().toUpperCase(),
          'title': _metadataString(document, 'title') ?? document.code,
          'release_date': _metadataString(document, 'releaseDate'),
          'duration_minutes': _metadataInt(document, 'durationMinutes'),
          'studio': _metadataString(document, 'studio'),
          'publisher': _metadataString(document, 'publisher'),
          'series': _metadataString(document, 'series'),
          'portable_id': existingRow['portable_id'] ?? document.workId,
          'primary_actress_id': existingPrimary ?? primaryId,
          'library_managed': 1,
          'library_relative_path': _relativeWorkPath(document),
          'modified_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [workId],
      );
    }

    final performerIds = <int>{primaryId};
    for (final performer in document.performers) {
      final performerId = await _resolveOrCreateActress(
        executor,
        portableId: _stringValue(performer['actressId']),
        name: _stringValue(performer['name']),
      );
      performerIds.add(performerId);
    }
    for (final actressId in performerIds) {
      await executor.insert('actress_works', {
        'actress_id': actressId,
        'work_id': workId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await executor.delete(
      'work_performers',
      where: 'work_id = ? AND source = ?',
      whereArgs: [workId, 'library'],
    );
    for (final performer in document.performers) {
      final name = _stringValue(performer['name']);
      if (name == null || name.isEmpty) continue;
      await executor.insert('work_performers', {
        'work_id': workId,
        'source': 'library',
        'name': name,
        'source_uri': _stringValue(performer['sourceUri']),
      });
    }

    final mediaIds = <String>[];
    for (final media in document.media) {
      final mediaId = await _upsertMedia(
        executor,
        workId: workId,
        media: media,
        importOperationId: importOperationId ?? media.importOperationId,
      );
      mediaIds.add(mediaId);
    }
    // Keep the local row linked to the portable primary identity even if the
    // document was generated by an older importer revision.
    await executor.update(
      'actresses',
      {'portable_id': primaryPortableId},
      where: 'id = ?',
      whereArgs: [primaryId],
    );
    return LibraryWorkCommitResult(workId: workId, mediaIds: mediaIds);
  }

  Future<String> _upsertMedia(
    DatabaseExecutor executor, {
    required int workId,
    required LibraryMediaRecord media,
    String? importOperationId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await executor.query(
      'media_files',
      columns: const ['id', 'portable_id'],
      where: 'work_id = ? AND relative_path = ?',
      whereArgs: [workId, media.relativePath],
      limit: 1,
    );
    final values = _mediaValues(
      workId: workId,
      media: media,
      importedAt: media.importedAt.toUtc().toIso8601String(),
      importOperationId: importOperationId,
      now: now,
    );
    if (existing.isEmpty) {
      await executor.insert('media_files', values);
      return media.mediaId;
    }
    await executor.update(
      'media_files',
      {
        ...values,
        'portable_id': existing.single['portable_id'] ?? media.mediaId,
        'modified_at': now,
      },
      where: 'id = ?',
      whereArgs: [existing.single['id']],
    );
    return existing.single['portable_id']?.toString() ?? media.mediaId;
  }

  Map<String, Object?> _mediaValues({
    required int workId,
    required LibraryMediaRecord media,
    required String importedAt,
    required String? importOperationId,
    required String now,
  }) => {
    'portable_id': media.mediaId,
    'work_id': workId,
    'relative_path': media.relativePath,
    'file_name': media.fileName,
    'original_file_name': media.originalFileName,
    'variant': media.variant,
    'variant_type': media.variantType,
    'has_chinese_subtitles': media.hasChineseSubtitles == null
        ? null
        : (media.hasChineseSubtitles! ? 1 : 0),
    'part_number': media.partNumber,
    'part_label': media.partLabel,
    'width': media.width,
    'height': media.height,
    'resolution_label': media.resolutionLabel,
    'frame_rate_numerator': media.frameRateNumerator,
    'frame_rate_denominator': media.frameRateDenominator,
    'frame_rate_decimal': media.frameRateDecimal,
    'duration_ms': media.durationMs,
    'container': media.container,
    'codec': media.codec,
    'file_size_bytes': media.fileSizeBytes,
    'sha256': media.sha256,
    'source_file_created_at': media.sourceFileCreatedAt
        ?.toUtc()
        .toIso8601String(),
    'imported_at': importedAt,
    'probe_backend': media.probeBackend,
    'probe_version': media.probeVersion,
    'parser_version': media.parserVersion,
    'import_operation_id': importOperationId,
    'created_at': now,
    'modified_at': now,
  };

  Future<List<Map<String, Object?>>> mediaForWork(int workId) async {
    final database = await db.database;
    return database.query(
      'media_files',
      where: 'work_id = ?',
      whereArgs: [workId],
      orderBy: 'part_number IS NULL, part_number ASC, relative_path ASC',
    );
  }

  Future<List<Map<String, Object?>>> importItems(String operationId) async {
    final database = await db.database;
    return database.query(
      'import_operation_items',
      where: 'operation_id = ?',
      whereArgs: [operationId],
      orderBy: 'id ASC',
    );
  }

  Future<void> recordLibraryLink({
    required int workId,
    required String actressPortableId,
    required String relativePath,
    required String targetRelativePath,
    required String state,
    String? error,
  }) async {
    final database = await db.database;
    final rows = await database.query(
      'actresses',
      columns: const ['id'],
      where: 'portable_id = ?',
      whereArgs: [actressPortableId],
      limit: 1,
    );
    final actressId = (rows.firstOrNull?['id'] as num?)?.toInt();
    if (actressId == null) {
      throw StateError('actress for library link was not found');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await database.insert('library_link_artifacts', {
      'work_id': workId,
      'actress_id': actressId,
      'relative_path': relativePath,
      'target_relative_path': targetRelativePath,
      'kind': 'windows_lnk',
      'state': state,
      'last_error': error,
      'created_at': now,
      'modified_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> libraryWorks() async {
    final database = await db.database;
    return database.query(
      'works',
      where: 'library_managed = 1',
      orderBy: 'release_date IS NULL, release_date DESC, id DESC',
    );
  }

  Future<bool> hasMediaHash(String sha256, {int? excludingWorkId}) async {
    final database = await db.database;
    final where = excludingWorkId == null
        ? 'sha256 = ?'
        : 'sha256 = ? AND work_id != ?';
    final args = excludingWorkId == null ? [sha256] : [sha256, excludingWorkId];
    final rows = await database.query(
      'media_files',
      columns: const ['id'],
      where: where,
      whereArgs: args,
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<String> createImportOperation({
    required String libraryRoot,
    required String planFingerprint,
    Iterable<Map<String, Object?>> items = const [],
  }) async {
    final id = _idGenerator.next();
    final now = DateTime.now().toUtc().toIso8601String();
    final database = await db.database;
    await database.transaction((transaction) async {
      await transaction.insert('import_operations', {
        'id': id,
        'state': LibraryImportOperationState.planned.value,
        'library_root': libraryRoot,
        'plan_fingerprint': planFingerprint,
        'created_at': now,
        'updated_at': now,
      });
      for (final item in items) {
        await transaction.insert('import_operation_items', {
          ...item,
          'operation_id': id,
          'state': item['state'] ?? LibraryImportItemState.planned.value,
          'step': item['step'] ?? 'planned',
          'plan_json': item['plan_json'] ?? jsonEncode(item['plan'] ?? {}),
          'created_at': now,
          'updated_at': now,
        });
      }
    });
    return id;
  }

  Future<void> updateImportOperation({
    required String operationId,
    required LibraryImportOperationState state,
    String? error,
    bool committed = false,
  }) async {
    final database = await db.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await database.update(
      'import_operations',
      {
        'state': state.value,
        'updated_at': now,
        'committed_at': committed ? now : null,
        'last_error': error,
      },
      where: 'id = ?',
      whereArgs: [operationId],
    );
  }

  Future<void> updateImportItem({
    required int itemId,
    required LibraryImportItemState state,
    required String step,
    String? error,
    String? workPortableId,
    String? mediaPortableId,
  }) async {
    final database = await db.database;
    final values = <String, Object?>{
      'state': state.value,
      'step': step,
      'last_error': error,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (workPortableId != null) {
      values['work_portable_id'] = workPortableId;
    }
    if (mediaPortableId != null) {
      values['media_portable_id'] = mediaPortableId;
    }
    await database.update(
      'import_operation_items',
      values,
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<List<Map<String, Object?>>> recoverableImportOperations() async {
    final database = await db.database;
    return database.query(
      'import_operations',
      where: 'state NOT IN (?, ?, ?, ?)',
      whereArgs: [
        LibraryImportOperationState.succeeded.value,
        LibraryImportOperationState.failed.value,
        LibraryImportOperationState.cancelledBeforeCommit.value,
        LibraryImportOperationState.repairRequired.value,
      ],
      orderBy: 'updated_at ASC',
    );
  }

  Future<int> _resolveOrCreateActress(
    DatabaseExecutor executor, {
    required String? portableId,
    required String? name,
  }) async {
    if (portableId != null && portableId.isNotEmpty) {
      final rows = await executor.query(
        'actresses',
        columns: const ['id'],
        where: 'portable_id = ?',
        whereArgs: [portableId],
        limit: 1,
      );
      final id = (rows.firstOrNull?['id'] as num?)?.toInt();
      if (id != null) return id;
    }
    final cleanName = name?.trim() ?? '';
    if (cleanName.isEmpty) {
      throw StateError('library work has no primary actress');
    }
    final rows = await executor.query(
      'actresses',
      columns: const ['id', 'portable_id'],
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [cleanName],
    );
    if (rows.length > 1) {
      throw StateError('actress name is ambiguous: $cleanName');
    }
    if (rows.isNotEmpty) {
      final id = (rows.single['id'] as num).toInt();
      final current = rows.single['portable_id']?.toString().trim() ?? '';
      if (current.isEmpty && portableId != null && portableId.isNotEmpty) {
        await executor.update(
          'actresses',
          {'portable_id': portableId},
          where: 'id = ?',
          whereArgs: [id],
        );
      } else {
        await _ensureActressPortableId(executor, id);
      }
      return id;
    }
    return executor.insert('actresses', {
      'name': cleanName,
      'portable_id': portableId ?? _idGenerator.next(),
      'main_type': '',
      'tags': '',
      'memo': '',
      'modified_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<String> _ensureActressPortableId(
    DatabaseExecutor executor,
    int actressId,
  ) async {
    final rows = await executor.query(
      'actresses',
      columns: const ['portable_id'],
      where: 'id = ?',
      whereArgs: [actressId],
      limit: 1,
    );
    final current = rows.firstOrNull?['portable_id']?.toString().trim();
    if (current != null && current.isNotEmpty) return current;
    final generated = _idGenerator.next();
    await executor.update(
      'actresses',
      {'portable_id': generated},
      where: 'id = ?',
      whereArgs: [actressId],
    );
    return generated;
  }

  String? _primaryName(LibraryInfoDocument document) {
    for (final performer in document.performers) {
      final id = _stringValue(performer['actressId']);
      if (id == document.primaryActressId) {
        return _stringValue(performer['name']);
      }
    }
    return document.performers.firstOrNull == null
        ? null
        : _stringValue(document.performers.first['name']);
  }

  String _relativeWorkPath(LibraryInfoDocument document) {
    if (document.libraryRelativePath.trim().isNotEmpty) {
      return document.libraryRelativePath.trim();
    }
    final primary =
        _metadataString(document, 'primaryActressName') ??
        document.primaryActressId ??
        'unknown-actress';
    return '$primary/${document.code.trim().toUpperCase()}';
  }

  String? _metadataString(LibraryInfoDocument document, String key) =>
      _stringValue(document.metadata[key]);

  int? _metadataInt(LibraryInfoDocument document, String key) =>
      (document.metadata[key] as num?)?.toInt();

  String? _stringValue(Object? value) {
    final result = value?.toString().trim();
    return result == null || result.isEmpty ? null : result;
  }
}
