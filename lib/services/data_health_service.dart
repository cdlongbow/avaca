import '../core/database.dart';
import '../models/data_health.dart';

class DataHealthService {
  DataHealthService({required this.db});

  final AppDatabase db;

  Future<DataHealthSnapshot> load() async {
    final database = await db.database;
    final actressCount = await _count(database, 'actresses');
    final workCount = await _count(database, 'works');
    final storedWorkCount = await _count(
      database,
      'works',
      where: 'is_stored = 1',
    );
    final pendingDeletionCount = await _count(
      database,
      'pending_file_deletions',
    );
    final missingReleaseDateCount = await _missing(database, 'release_date');
    final missingStudioCount = await _missing(database, 'studio');
    final missingPublisherCount = await _missing(database, 'publisher');
    final missingSeriesCount = await _missing(database, 'series');
    final missingCardImageCount = await _missingImageReferences(
      database,
      'card_image_path',
    );
    final missingDetailImageCount = await _missingImageReferences(
      database,
      'detail_image_path',
    );
    final missingProvenance = await database.rawQuery('''
      SELECT COUNT(*) AS count
      FROM works w
      WHERE NOT EXISTS (
        SELECT 1 FROM work_field_provenance p WHERE p.work_id = w.id
      )
    ''');
    final jobRows = await database.rawQuery(
      'SELECT state, COUNT(*) AS count FROM scrape_jobs GROUP BY state ORDER BY state',
    );
    final jobCounts = <String, int>{};
    for (final row in jobRows) {
      jobCounts[row['state']?.toString() ?? 'unknown'] = _number(row['count']);
    }
    final sourceRows = await database.rawQuery('''
      SELECT COALESCE(source, 'unknown') AS source, COUNT(*) AS count
      FROM scrape_job_events
      WHERE severity IN ('warning', 'error')
        AND created_at >= datetime('now', '-7 day')
      GROUP BY source
      ORDER BY count DESC, source ASC
    ''');
    final sourceErrorCounts = <String, int>{};
    for (final row in sourceRows) {
      sourceErrorCounts[row['source']?.toString() ?? 'unknown'] = _number(
        row['count'],
      );
    }
    return DataHealthSnapshot(
      generatedAt: DateTime.now().toUtc(),
      actressCount: actressCount,
      workCount: workCount,
      storedWorkCount: storedWorkCount,
      notStoredWorkCount: workCount - storedWorkCount,
      missingReleaseDateCount: missingReleaseDateCount,
      missingStudioCount: missingStudioCount,
      missingPublisherCount: missingPublisherCount,
      missingSeriesCount: missingSeriesCount,
      missingCardImageCount: missingCardImageCount,
      missingDetailImageCount: missingDetailImageCount,
      missingProvenanceCount: _number(missingProvenance.firstOrNull?['count']),
      pendingDeletionCount: pendingDeletionCount,
      jobCounts: Map.unmodifiable(jobCounts),
      sourceErrorCounts: Map.unmodifiable(sourceErrorCounts),
    );
  }

  Future<int> _count(dynamic database, String table, {String? where}) async {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM $table${where == null ? '' : ' WHERE $where'}',
    );
    return _number(rows.firstOrNull?['count']);
  }

  Future<int> _missing(dynamic database, String column) => _count(
    database,
    'works',
    where: '$column IS NULL OR TRIM(CAST($column AS TEXT)) = \'\'',
  );

  Future<int> _missingImageReferences(dynamic database, String column) async {
    final rows = await database.query('works', columns: [column]);
    var missing = 0;
    for (final row in rows) {
      final storedPath = row[column]?.toString().trim() ?? '';
      if (storedPath.isEmpty ||
          await db.resolveManagedImageForTransfer(storedPath) == null) {
        missing++;
      }
    }
    return missing;
  }
}

int _number(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
