import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:avaca/core/database.dart';
import 'package:avaca/library/library_exact_resolver.dart';
import 'package:avaca/library/library_filesystem.dart';
import 'package:avaca/library/library_import_service.dart';
import 'package:avaca/library/library_info_store.dart';
import 'package:avaca/library/library_media_probe.dart';
import 'package:avaca/library/library_models.dart';
import 'package:avaca/library/library_repository.dart';
import 'package:avaca/models/scrape_source_id.dart';
import 'package:avaca/models/work.dart';
import 'package:avaca/models/work_storage.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/services/scrape/scrape_source.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'confirmed import copies, indexes, links, then removes source',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_import_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final sourceRoot = Directory(p.join(root.path, 'source'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final sourceFile = File(
        p.join(sourceRoot.path, '[FHD] SSIS00123-RUC.mp4'),
      )..writeAsBytesSync(List<int>.filled(32, 7));
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final details = ScrapeWorkDetails(
          source: ScrapeSourceId.javbus,
          code: 'SSIS-123',
          title: 'Fixture title',
          releaseDate: '2026-08-21',
          performers: const [
            WorkPerformer(name: 'Actress A'),
            WorkPerformer(name: 'Actress B'),
          ],
        );
        final source = _FakeSource(details);
        final service = LibraryImportService(
          repository: LibraryRepository(db: db),
          resolver: LibraryExactWorkResolver(
            sources: {ScrapeSourceId.javbus: source},
            priority: const [ScrapeSourceId.javbus],
          ),
          mediaProbe: const _FakeProbe(),
          filesystem: LibraryFilesystem(),
          shortcutManager: const _RecordingShortcutManager(),
        );
        final scan = await LibraryFolderScanner().scan(sourceRoot.path);
        final selected = scan.single.copyWith(selected: true);
        final plan = await service.buildPlan(
          sourceFolder: sourceRoot.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: [selected],
        );
        expect(plan.issues, isEmpty);
        final preflight = await service.preflight(plan);
        expect(preflight.isReady, isTrue);

        final result = await service.execute(plan, preflight);

        expect(result.succeededCount, 1);
        expect(result.failedCount, 0);
        expect(sourceFile.existsSync(), isFalse);
        final info = File(
          p.join(libraryRoot.path, 'Actress A', 'SSIS-123', 'info.json'),
        );
        expect(info.existsSync(), isTrue);
        final database = await db.database;
        expect((await database.query('media_files')), hasLength(1));
        expect(
          (await database.query('works', where: 'library_managed = 1')),
          hasLength(1),
        );
        expect(
          (await database.query(
            'import_operations',
            where: 'state = ?',
            whereArgs: ['succeeded'],
          )),
          hasLength(1),
        );
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test('database v2 adds portable ids and media journal tables', () async {
    final root = await Directory.systemTemp.createTemp('avaca_library_schema_');
    AppDatabase? db;
    try {
      db = AppDatabase.forTesting(
        baseDir: root.path,
        databaseFactory: databaseFactoryFfi,
      );
      await db.init();
      final database = await db.database;
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = tables.map((row) => row['name']).toSet();
      expect(
        names,
        containsAll([
          'media_files',
          'import_operations',
          'import_operation_items',
          'library_link_artifacts',
          'library_roots',
        ]),
      );
      final actress = await database.insert('actresses', {'name': 'Existing'});
      await db.close();
      db = AppDatabase.forTesting(
        baseDir: root.path,
        databaseFactory: databaseFactoryFfi,
      );
      await db.init();
      final row = (await (await db.database).query(
        'actresses',
        where: 'id = ?',
        whereArgs: [actress],
      )).single;
      expect(row['portable_id'], isA<String>());
    } finally {
      await db?.close();
      if (root.existsSync()) await root.delete(recursive: true);
    }
  });

  test('database v1 migrates to the portable library schema in place', () async {
    final root = await Directory.systemTemp.createTemp('avaca_library_v1_');
    AppDatabase? db;
    Database? legacy;
    try {
      legacy = await databaseFactoryFfi.openDatabase(
        p.join(root.path, AppDatabase.databaseFileName),
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (database, _) async {
            await database.execute('''
              CREATE TABLE actresses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                img_path TEXT,
                birth_date TEXT,
                modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
              )
            ''');
            await database.execute('''
              CREATE TABLE works (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT NOT NULL COLLATE NOCASE UNIQUE,
                title TEXT NOT NULL,
                release_date TEXT,
                duration_minutes INTEGER,
                studio TEXT,
                publisher TEXT,
                series TEXT,
                card_image_path TEXT,
                detail_image_path TEXT,
                is_stored INTEGER NOT NULL DEFAULT 0,
                storage_quality TEXT,
                storage_frame_rate INTEGER,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
              )
            ''');
            await database.insert('actresses', {'name': 'Legacy Actress'});
            await database.insert('works', {
              'code': 'LEG-001',
              'title': 'Legacy Work',
            });
          },
        ),
      );
      await legacy.close();
      legacy = null;

      db = AppDatabase.forTesting(
        baseDir: root.path,
        databaseFactory: databaseFactoryFfi,
      );
      await db.init();
      final database = await db.database;
      final actress = (await database.query('actresses')).single;
      final work = (await database.query('works')).single;
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(actress['portable_id']?.toString() ?? ''),
        isTrue,
      );
      expect(work['portable_id'], isA<String>());
      expect(work['code'], 'LEG-001');
      expect(
        await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'media_files'",
        ),
        hasLength(1),
      );
    } finally {
      await legacy?.close();
      await db?.close();
      if (root.existsSync()) await root.delete(recursive: true);
    }
  });

  test(
    'cancellation before portable commit preserves the source file',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_cancel_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final sourceRoot = Directory(p.join(root.path, 'source'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final sourceFile = File(p.join(sourceRoot.path, 'ABC-123.mp4'))
        ..writeAsStringSync('cancel fixture');
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final details = _fixtureDetails(code: 'ABC-123');
        final service = _fixtureService(db, details);
        final entry = (await LibraryFolderScanner().scan(
          sourceRoot.path,
        )).single.copyWith(selected: true);
        final plan = await service.buildPlan(
          sourceFolder: sourceRoot.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: [entry],
        );
        final preflight = await service.preflight(plan);
        final result = await service.execute(
          plan,
          preflight,
          isCancelled: () => true,
        );

        expect(result.items.single.state, LibraryImportResultState.cancelled);
        expect(sourceFile.existsSync(), isTrue);
        expect(
          File(
            p.join(libraryRoot.path, 'Actress A', 'ABC-123', 'info.json'),
          ).existsSync(),
          isFalse,
        );
        expect((await (await db.database).query('media_files')), isEmpty);
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'same content in a later import is reported as duplicate media',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_dedupe_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final sourceOne = Directory(p.join(root.path, 'source-one'))
        ..createSync();
      final sourceTwo = Directory(p.join(root.path, 'source-two'))
        ..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final bytes = <int>[4, 8, 15, 16, 23, 42];
      final firstFile = File(p.join(sourceOne.path, 'ABC-123.mp4'))
        ..writeAsBytesSync(bytes);
      final secondFile = File(p.join(sourceTwo.path, 'ABC-123.mp4'))
        ..writeAsBytesSync(bytes);
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final details = _fixtureDetails(code: 'ABC-123');
        final service = _fixtureService(db, details);

        final firstEntry = (await LibraryFolderScanner().scan(
          sourceOne.path,
        )).single.copyWith(selected: true);
        final firstPlan = await service.buildPlan(
          sourceFolder: sourceOne.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: [firstEntry],
        );
        final firstPreflight = await service.preflight(firstPlan);
        await service.execute(firstPlan, firstPreflight);
        expect(firstFile.existsSync(), isFalse);

        final secondEntry = (await LibraryFolderScanner().scan(
          sourceTwo.path,
        )).single.copyWith(selected: true);
        final secondPlan = await service.buildPlan(
          sourceFolder: sourceTwo.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: [secondEntry],
        );
        final secondPreflight = await service.preflight(secondPlan);
        expect(secondPreflight.items.single.duplicateMedia, isTrue);
        final result = await service.execute(secondPlan, secondPreflight);

        expect(result.duplicateCount, 1);
        expect(secondFile.existsSync(), isTrue);
        expect((await (await db.database).query('media_files')), hasLength(1));
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'reindex rebuilds the local index and rejects a stale folder path',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_reindex_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final libraryRoot = Directory(
        p.join(root.path, 'library', 'Actress A', 'ABC-123'),
      )..createSync(recursive: true);
      final mediaFile = File(p.join(libraryRoot.path, 'ABC-123.mp4'))
        ..writeAsStringSync('portable fixture');
      final media = LibraryMediaRecord(
        mediaId: 'media-portable-id',
        workId: 'work-portable-id',
        relativePath: 'ABC-123.mp4',
        fileName: 'ABC-123.mp4',
        originalFileName: 'downloaded-ABC-123.mp4',
        variant: null,
        variantType: null,
        hasChineseSubtitles: null,
        partNumber: null,
        partLabel: null,
        width: 1920,
        height: 1080,
        resolutionLabel: '1080p',
        frameRateNumerator: 30000,
        frameRateDenominator: 1001,
        frameRateDecimal: 29.970029,
        durationMs: 1000,
        container: 'mp4',
        codec: 'h264',
        fileSizeBytes: mediaFile.lengthSync(),
        sha256: '',
        sourceFileCreatedAt: DateTime.utc(2026, 8, 21),
        importedAt: DateTime.utc(2026, 8, 28),
        probeBackend: 'fixture',
        probeVersion: '1',
        parserVersion: 1,
      );
      final document = LibraryInfoDocument(
        schemaVersion: 1,
        workId: 'work-portable-id',
        code: 'ABC-123',
        metadata: const {
          'title': 'Portable title',
          'primaryActressName': 'Actress A',
        },
        primaryActressId: 'actress-portable-id',
        performers: const [
          {'actressId': 'actress-portable-id', 'name': 'Actress A'},
        ],
        images: const {},
        media: [media],
        scrape: const {'source': 'fixture'},
        libraryRelativePath: 'Actress A/ABC-123',
      );
      AppDatabase? db;
      try {
        await LibraryInfoStore().write(libraryRoot, document);
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final repository = LibraryRepository(db: db);
        final rootPath = p.join(root.path, 'library');
        final report = await LibraryReindexService(
          repository: repository,
        ).reindex(rootPath);
        expect(report.indexedDocuments, 1);
        expect(report.skippedDocuments, 0);
        expect(
          (await (await db.database).query('works')).single['library_managed'],
          1,
        );
        expect((await (await db.database).query('media_files')), hasLength(1));

        await LibraryInfoStore().write(
          libraryRoot,
          document.copyWith(libraryRelativePath: 'Other/ABC-123'),
        );
        final staleReport = await LibraryReindexService(
          repository: repository,
        ).reindex(rootPath);
        expect(staleReport.skippedDocuments, 1);
        expect(
          staleReport.errors.single,
          contains('does not match its folder'),
        );
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'legacy work updates cannot overwrite library-managed metadata',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_guard_',
      );
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: root.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final database = await db.database;
        final workId = await database.insert('works', {
          'code': 'ABC-123',
          'title': 'Portable title',
          'library_managed': 1,
          'portable_id': 'portable-work',
          'primary_actress_id': null,
        });

        await db.upsertWork(
          const Work(code: 'ABC-123', title: 'Scraper overwrite'),
        );

        final row = (await database.query(
          'works',
          where: 'id = ?',
          whereArgs: [workId],
        )).single;
        expect(row['title'], 'Portable title');
        await expectLater(
          db.updateWorkStorage(
            workId: workId,
            record: const WorkStorageRecord(
              isStored: true,
              quality: '1080',
              frameRate: 30,
            ),
          ),
          throwsA(isA<StateError>()),
        );
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );
}

class _FakeProbe implements LibraryMediaProbe {
  const _FakeProbe();

  @override
  Future<MediaProbeResult> probe(String filePath) async =>
      const MediaProbeResult(
        width: 1920,
        height: 1080,
        frameRateNumerator: 30000,
        frameRateDenominator: 1001,
        durationMs: 1000,
        container: 'mp4',
        codec: 'h264',
        backend: 'fixture',
        backendVersion: '1',
        selectedStreamIndex: 0,
      );

  @override
  void close() {}
}

class _RecordingShortcutManager implements LibraryShortcutManager {
  const _RecordingShortcutManager();

  @override
  bool get isSupported => true;

  @override
  Future<void> createDirectoryShortcut({
    required String linkPath,
    required String targetPath,
  }) async {}
}

ScrapeWorkDetails _fixtureDetails({required String code}) => ScrapeWorkDetails(
  source: ScrapeSourceId.javbus,
  code: code,
  title: 'Fixture title',
  releaseDate: '2026-08-21',
  performers: const [
    WorkPerformer(name: 'Actress A'),
    WorkPerformer(name: 'Actress B'),
  ],
);

LibraryImportService _fixtureService(
  AppDatabase db,
  ScrapeWorkDetails details,
) {
  return LibraryImportService(
    repository: LibraryRepository(db: db),
    resolver: LibraryExactWorkResolver(
      sources: {ScrapeSourceId.javbus: _FakeSource(details)},
      priority: const [ScrapeSourceId.javbus],
    ),
    mediaProbe: const _FakeProbe(),
    filesystem: LibraryFilesystem(),
    shortcutManager: const _RecordingShortcutManager(),
  );
}

class _FakeSource implements ScrapeSource {
  _FakeSource(this.details);

  final ScrapeWorkDetails details;

  @override
  ScrapeSourceId get id => ScrapeSourceId.javbus;

  @override
  Future<ScrapeWorkDetails?> fetchWorkDetailsByCode(
    String canonicalCode,
  ) async => canonicalCode == details.code ? details : null;

  @override
  void close() {}
}
