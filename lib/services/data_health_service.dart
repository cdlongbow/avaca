import 'package:sqflite/sqflite.dart';

import '../core/database.dart';
import '../library/library_media_locator.dart';
import '../models/data_health.dart';

class DataHealthService {
  DataHealthService({required this.db, LibraryMediaLocator? locator})
    : locator = locator ?? LibraryMediaLocator();

  final AppDatabase db;
  final LibraryMediaLocator locator;

  Future<DataHealthSnapshot> load() async {
    final database = await db.database;
    final warnings = <String>[];

    void warn(String key) {
      if (!warnings.contains(key)) warnings.add(key);
    }

    Future<T> safe<T>(
      String warningKey,
      T fallback,
      Future<T> Function() operation,
    ) async {
      try {
        return await operation();
      } on Object {
        warn(warningKey);
        return fallback;
      }
    }

    final actressCount = await safe(
      'actresses',
      0,
      () => _count(database, 'actresses'),
    );
    final workCount = await safe('works', 0, () => _count(database, 'works'));
    final storedWorkCount = await safe(
      'storedWorks',
      0,
      () => _count(database, 'works', where: 'is_stored = 1'),
    );
    final pendingDeletionCount = await safe(
      'pendingDeletions',
      0,
      () => _count(database, 'pending_file_deletions'),
    );
    final missingReleaseDateCount = await safe(
      'metadata',
      0,
      () => _missing(database, 'release_date'),
    );
    final missingStudioCount = await safe(
      'metadata',
      0,
      () => _missing(database, 'studio'),
    );
    final missingPublisherCount = await safe(
      'metadata',
      0,
      () => _missing(database, 'publisher'),
    );
    final missingSeriesCount = await safe(
      'metadata',
      0,
      () => _missing(database, 'series'),
    );
    final missingCardImageCount = await safe(
      'images',
      0,
      () => _missingImageReferences(database, 'card_image_path'),
    );
    final missingDetailImageCount = await safe(
      'images',
      0,
      () => _missingImageReferences(database, 'detail_image_path'),
    );
    final missingProvenanceCount = await safe('provenance', 0, () async {
      final rows = await database.rawQuery('''
          SELECT COUNT(*) AS count
          FROM works w
          WHERE NOT EXISTS (
            SELECT 1 FROM work_field_provenance p WHERE p.work_id = w.id
          )
        ''');
      return _number(rows.firstOrNull?['count']);
    });
    final libraryWorkCount = await safe(
      'library',
      0,
      () => _count(database, 'works', where: 'library_managed = 1'),
    );
    final importRepairCount = await safe('library', 0, () async {
      final rows = await database.rawQuery('''
        SELECT COUNT(*) AS count
        FROM import_operations
        WHERE state IN ('repair_required', 'source_cleanup_pending')
      ''');
      return _number(rows.firstOrNull?['count']);
    });
    final libraryMediaIssueCount = await safe('library', 0, () async {
      final rootRows = await database.query(
        'library_roots',
        columns: const ['path'],
        where: 'is_active = 1',
        orderBy: 'modified_at DESC',
        limit: 1,
      );
      final root = rootRows.firstOrNull?['path']?.toString().trim();
      if (root == null || root.isEmpty) return 0;
      final rows = await database.rawQuery('''
        SELECT w.library_relative_path, m.relative_path, m.portable_id
        FROM media_files m INNER JOIN works w ON w.id = m.work_id
        WHERE w.library_managed = 1
      ''');
      var missing = 0;
      for (final row in rows) {
        if (row['portable_id']?.toString().trim().isEmpty ?? true) {
          missing++;
          continue;
        }
        try {
          await locator.resolveMedia(
            libraryRoot: root,
            workRelativePath: row['library_relative_path']?.toString() ?? '',
            mediaRelativePath: row['relative_path']?.toString() ?? '',
            mediaPortableId: row['portable_id']?.toString(),
          );
        } on Object {
          missing++;
        }
      }
      return missing;
    });
    final libraryLinkIssueCount = await safe('library', 0, () async {
      final rows = await database.rawQuery('''
        SELECT COUNT(*) AS count FROM library_link_artifacts
        WHERE state <> 'ready'
      ''');
      return _number(rows.firstOrNull?['count']);
    });
    return DataHealthSnapshot(
      generatedAt: DateTime.now().toUtc(),
      actressCount: actressCount,
      workCount: workCount,
      storedWorkCount: storedWorkCount,
      notStoredWorkCount: (workCount - storedWorkCount).clamp(0, workCount),
      missingReleaseDateCount: missingReleaseDateCount,
      missingStudioCount: missingStudioCount,
      missingPublisherCount: missingPublisherCount,
      missingSeriesCount: missingSeriesCount,
      missingCardImageCount: missingCardImageCount,
      missingDetailImageCount: missingDetailImageCount,
      missingProvenanceCount: missingProvenanceCount,
      pendingDeletionCount: pendingDeletionCount,
      libraryWorkCount: libraryWorkCount,
      libraryMediaIssueCount: libraryMediaIssueCount,
      importRepairCount: importRepairCount,
      libraryLinkIssueCount: libraryLinkIssueCount,
      warnings: List.unmodifiable(warnings),
    );
  }

  Future<int> _count(
    DatabaseExecutor database,
    String table, {
    String? where,
  }) async {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM $table${where == null ? '' : ' WHERE $where'}',
    );
    return _number(rows.firstOrNull?['count']);
  }

  Future<int> _missing(DatabaseExecutor database, String column) => _count(
    database,
    'works',
    where: '$column IS NULL OR TRIM(CAST($column AS TEXT)) = \'\'',
  );

  Future<int> _missingImageReferences(
    DatabaseExecutor database,
    String column,
  ) async {
    final rows = await database.query('works', columns: [column]);
    var missing = 0;
    for (final row in rows) {
      final storedPath = row[column]?.toString().trim() ?? '';
      try {
        if (storedPath.isEmpty ||
            await db.resolveManagedImageForTransfer(storedPath) == null) {
          missing++;
        }
      } on Object {
        missing++;
      }
    }
    return missing;
  }
}

int _number(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
