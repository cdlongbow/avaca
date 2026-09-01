import '../core/database.dart';
import 'library_media_locator.dart';
import 'library_media_resolver.dart';
import 'library_repository.dart';

/// Reads the normal product Collection from physically verifiable media.
///
/// Legacy database queries remain available for migration, data transfer and
/// health tooling. This service is the only query surface used by the normal
/// Home → Actress → Work browsing path.
class LibraryCollectionService {
  LibraryCollectionService({
    required this.db,
    LibraryRepository? repository,
    LibraryMediaLocator? locator,
    LibraryMediaResolver? mediaResolver,
  }) : repository = repository ?? LibraryRepository(db: db),
       locator = locator ?? LibraryMediaLocator() {
    this.mediaResolver =
        mediaResolver ??
        LibraryMediaResolver(
          repository: this.repository,
          locator: this.locator,
        );
  }

  final AppDatabase db;
  final LibraryRepository repository;
  final LibraryMediaLocator locator;
  late final LibraryMediaResolver mediaResolver;

  /// Returns an actress only when the normal Collection can resolve at least
  /// one of her indexed Library media files. Direct routes use this guard so
  /// a legacy metadata-only actress cannot be opened around Collection.
  Future<Map<String, Object?>?> getActressById(int actressId) async {
    final root = await repository.activeLibraryRoot();
    if (root == null) return null;
    final database = await db.database;
    final rows = await database.rawQuery(
      '''
      SELECT DISTINCT a.id, a.name, a.img_path,
             mf.portable_id AS media_portable_id
      FROM actresses a
      INNER JOIN actress_works aw ON aw.actress_id = a.id
      INNER JOIN works w ON w.id = aw.work_id
      INNER JOIN media_files mf ON mf.work_id = w.id
      WHERE a.id = ?
        AND w.library_managed = 1
        AND mf.portable_id IS NOT NULL
        AND TRIM(mf.portable_id) <> ''
      ''',
      [actressId],
    );
    for (final row in rows) {
      if (await _mediaExists(
        mediaPortableId: row['media_portable_id']?.toString(),
      )) {
        return _actressValues(row);
      }
    }
    return null;
  }

  Future<List<Map<String, Object?>>> getActresses({
    String searchKeyword = '',
    String filterType = '全部',
    String sortBy = '新增時間 (新到舊)',
  }) async {
    final root = await repository.activeLibraryRoot();
    if (root == null) return const [];
    final database = await db.database;
    final where = <String>[
      'w.library_managed = 1',
      'mf.portable_id IS NOT NULL',
      "TRIM(mf.portable_id) <> ''",
    ];
    final args = <Object?>[];
    if (searchKeyword.trim().isNotEmpty) {
      where.add('a.name LIKE ?');
      args.add('%${searchKeyword.trim()}%');
    }
    if (filterType != '全部') {
      where.add('a.main_type LIKE ?');
      args.add('%$filterType%');
    }
    final orderBy = switch (sortBy) {
      '新增時間 (新到舊)' => 'a.id DESC',
      '新增時間 (舊到新)' => 'a.id ASC',
      '修改時間 (新到舊)' => 'a.modified_at DESC, a.id DESC',
      '修改時間 (舊到新)' => 'a.modified_at ASC, a.id DESC',
      '年齡 (低到高)' => 'a.birth_date IS NULL, a.birth_date DESC, a.id DESC',
      '年齡 (高到低)' => 'a.birth_date IS NULL, a.birth_date ASC, a.id DESC',
      _ => 'a.id DESC',
    };
    final rows = await database.rawQuery('''
      SELECT DISTINCT a.id, a.name, a.img_path,
             mf.portable_id AS media_portable_id
      FROM actresses a
      INNER JOIN actress_works aw ON aw.actress_id = a.id
      INNER JOIN works w ON w.id = aw.work_id
      INNER JOIN media_files mf ON mf.work_id = w.id
      WHERE ${where.join(' AND ')}
      ORDER BY $orderBy
      ''', args);

    final healthyActresses = <Map<String, Object?>>[];
    final seen = <int>{};
    for (final row in rows) {
      final actressId = (row['id'] as num?)?.toInt();
      if (actressId == null || seen.contains(actressId)) continue;
      final healthy = await _mediaExists(
        mediaPortableId: row['media_portable_id']?.toString(),
      );
      if (!healthy) continue;
      seen.add(actressId);
      healthyActresses.add(_actressValues(row));
    }
    return List.unmodifiable(healthyActresses);
  }

  Future<List<Map<String, Object?>>> getWorksForActress(int actressId) async {
    final root = await repository.activeLibraryRoot();
    if (root == null) return const [];
    final database = await db.database;
    final rows = await database.rawQuery(
      '''
      SELECT DISTINCT w.id, w.code, w.title, w.release_date,
             w.duration_minutes, w.studio, w.publisher, w.series,
             w.card_image_path, w.detail_image_path, w.portable_id,
             w.primary_actress_id, w.library_managed, w.library_relative_path
      FROM works w
      INNER JOIN actress_works aw ON aw.work_id = w.id
      INNER JOIN media_files mf ON mf.work_id = w.id
      WHERE aw.actress_id = ?
        AND w.library_managed = 1
        AND mf.portable_id IS NOT NULL
        AND TRIM(mf.portable_id) <> ''
      ORDER BY w.release_date IS NULL, w.release_date DESC, w.id DESC
      ''',
      [actressId],
    );
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final mediaRows = await database.query(
        'media_files',
        columns: const ['relative_path', 'portable_id'],
        where:
            'work_id = ? AND portable_id IS NOT NULL AND TRIM(portable_id) <> ?',
        whereArgs: [row['id'], ''],
        orderBy: 'part_number IS NULL, part_number ASC, relative_path ASC',
      );
      var healthy = false;
      for (final media in mediaRows) {
        if (await _mediaExists(
          mediaPortableId: media['portable_id']?.toString(),
          expectedWorkId: (row['id'] as num?)?.toInt(),
        )) {
          healthy = true;
          break;
        }
      }
      if (healthy) result.add(Map<String, Object?>.from(row));
    }
    return List.unmodifiable(result);
  }

  Future<int> getWorkCountForActress(int actressId) async =>
      (await getWorksForActress(actressId)).length;

  /// Loads a Work through the normal physical Collection admission boundary.
  /// Legacy metadata-only Works are intentionally not returned.
  Future<Map<String, Object?>?> getWorkById(
    int workId, {
    int? currentActressId,
  }) async {
    final root = await repository.activeLibraryRoot();
    if (root == null) return null;
    if (currentActressId != null) {
      final database = await db.database;
      final relation = await database.query(
        'actress_works',
        columns: const ['work_id'],
        where: 'actress_id = ? AND work_id = ?',
        whereArgs: [currentActressId, workId],
        limit: 1,
      );
      if (relation.isEmpty) return null;
    }
    final work = await db.getWorkById(
      workId,
      currentActressId: currentActressId,
    );
    if (work == null || !_isManaged(work['library_managed'])) return null;
    final rawMedia = work['library_media'];
    if (rawMedia is! List || rawMedia.isEmpty) return null;
    final workPortableId = work['portable_id']?.toString();
    final healthyMedia = <Map<String, Object?>>[];
    for (final value in rawMedia.whereType<Map>()) {
      final media = Map<String, Object?>.from(value);
      final portableId = media['portable_id']?.toString().trim() ?? '';
      if (portableId.isEmpty) continue;
      try {
        await mediaResolver.resolveByPortableId(
          portableId,
          expectedWorkId: workId,
          expectedWorkPortableId: workPortableId,
          verifyIntegrity: false,
        );
        healthyMedia.add(media);
      } on Object {
        // Broken media remains available to health tooling but is not an
        // admission ticket for the normal Collection.
      }
    }
    if (healthyMedia.isEmpty) return null;
    work.remove('is_stored');
    work.remove('storage_quality');
    work.remove('storage_frame_rate');
    work['library_media'] = List.unmodifiable(healthyMedia);
    return work;
  }

  Future<bool> _mediaExists({
    required String? mediaPortableId,
    int? expectedWorkId,
  }) async {
    final id = mediaPortableId?.trim();
    if (id == null || id.isEmpty) return false;
    try {
      await mediaResolver.resolveByPortableId(
        id,
        expectedWorkId: expectedWorkId,
        verifyIntegrity: false,
      );
      return true;
    } on Object {
      return false;
    }
  }

  Map<String, Object?> _actressValues(Map<String, Object?> row) => {
    'id': row['id'],
    'name': row['name'],
    'img_path': row['img_path'],
  };

  bool _isManaged(Object? value) =>
      value is num ? value.toInt() == 1 : value == true;
}
