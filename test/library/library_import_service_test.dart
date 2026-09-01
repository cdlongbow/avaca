import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:avaca/core/database.dart';
import 'package:avaca/library/library_collection_service.dart';
import 'package:avaca/library/library_exact_resolver.dart';
import 'package:avaca/library/library_filesystem.dart';
import 'package:avaca/library/library_image_downloader.dart';
import 'package:avaca/library/library_import_service.dart';
import 'package:avaca/library/library_import_session.dart';
import 'package:avaca/library/library_maintenance_service.dart';
import 'package:avaca/library/library_info_store.dart';
import 'package:avaca/library/library_media_probe.dart';
import 'package:avaca/library/library_media_resolver.dart';
import 'package:avaca/library/library_models.dart';
import 'package:avaca/library/library_repository.dart';
import 'package:avaca/models/scrape_source_id.dart';
import 'package:avaca/models/work.dart';
import 'package:avaca/models/work_storage.dart';
import 'package:avaca/player/player.dart';
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
        final progress = <LibraryImportProgress>[];
        final scan = await LibraryFolderScanner().scan(sourceRoot.path);
        final selected = scan.single.copyWith(selected: true);
        final plan = await service.buildPlan(
          sourceFolder: sourceRoot.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: [selected],
          primaryActressSelector: (_) => 'Actress A',
          onProgress: progress.add,
        );
        expect(plan.issues, isEmpty);
        final preflight = await service.preflight(
          plan,
          onProgress: progress.add,
        );
        expect(preflight.isReady, isTrue);

        final result = await service.execute(
          plan,
          preflight,
          onProgress: progress.add,
        );

        expect(result.succeededCount, 1);
        expect(result.failedCount, 0);
        expect(plan.progressItemCount, 1);
        expect(progress, isNotEmpty);
        expect(progress.every((item) => item.itemIndex == 1), isTrue);
        expect(progress.every((item) => item.itemCount == 1), isTrue);
        expect(
          progress.map((item) => item.phase),
          containsAll(<LibraryImportProgressPhase>[
            LibraryImportProgressPhase.resolving,
            LibraryImportProgressPhase.hashing,
            LibraryImportProgressPhase.probing,
            LibraryImportProgressPhase.preflight,
            LibraryImportProgressPhase.staging,
            LibraryImportProgressPhase.copying,
            LibraryImportProgressPhase.verifying,
            LibraryImportProgressPhase.portableCommit,
            LibraryImportProgressPhase.indexing,
            LibraryImportProgressPhase.linking,
            LibraryImportProgressPhase.sourceCleanup,
            LibraryImportProgressPhase.succeeded,
          ]),
        );
        expect(progress.last.isTerminal, isTrue);
        expect(progress.last.resultState, LibraryImportResultState.succeeded);
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
        final work = (await database.query(
          'works',
          where: 'library_managed = 1',
        )).single;
        final primaryActressId = (work['primary_actress_id'] as num).toInt();
        expect(
          (await database.query(
            'actresses',
            columns: const ['name'],
            where: 'id = ?',
            whereArgs: [primaryActressId],
          )).single['name'],
          'Actress A',
        );
        expect(
          (await database.rawQuery(
            '''
            SELECT a.name
            FROM actresses a
            INNER JOIN actress_works aw ON aw.actress_id = a.id
            WHERE aw.work_id = ?
            ORDER BY a.name COLLATE NOCASE ASC
            ''',
            [work['id']],
          )).map((row) => row['name']),
          ['Actress A', 'Actress B'],
        );
        expect(
          (await database.query(
            'work_performers',
            columns: const ['name'],
            where: 'work_id = ?',
            whereArgs: [work['id']],
            orderBy: 'name COLLATE NOCASE ASC',
          )).map((row) => row['name']),
          ['Actress A', 'Actress B'],
        );
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'confirmed import reaches physical Collection and existing Player by portable ID',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_golden_journey_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final sourceRoot = Directory(p.join(root.path, 'source'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final sourceFile = File(p.join(sourceRoot.path, 'ABC-123.mp4'))
        ..writeAsBytesSync(List<int>.generate(64, (index) => index));
      final importSession = LibraryImportSession();
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        importSession.setSourceFolder(sourceRoot.path);
        importSession.setLibraryRoot(libraryRoot.path);
        importSession.setEntries(
          await LibraryFolderScanner().scan(sourceRoot.path),
        );
        importSession.selectAllRecognizable();
        expect(importSession.entries, hasLength(1));
        expect(importSession.selectedCount, 1);

        final service = _fixtureService(db, _fixtureDetails(code: 'ABC-123'));
        final plan = await service.buildPlan(
          sourceFolder: importSession.sourceFolder!,
          libraryRoot: importSession.libraryRoot!,
          selectedEntries: importSession.selectedEntries,
          primaryActressSelector: (_) => 'Actress A',
        );
        expect(plan.issues, isEmpty);
        expect(plan.items, hasLength(1));
        expect(plan.items.single.details.code, 'ABC-123');

        final preflight = await service.preflight(plan);
        expect(preflight.isReady, isTrue);

        final batch = await service.execute(plan, preflight);
        expect(batch.succeededCount, 1);
        expect(batch.failedCount, 0);
        expect(sourceFile.existsSync(), isFalse);
        importSession.reconcileAfterImport(
          batch.items
              .where((item) => item.state == LibraryImportResultState.succeeded)
              .map((item) => item.sourcePath),
        );
        expect(importSession.entries, isEmpty);

        final database = await db.database;
        final workRow = (await database.query(
          'works',
          where: 'library_managed = 1',
        )).single;
        final workId = (workRow['id'] as num).toInt();
        final collectionWork = await LibraryCollectionService(
          db: db,
        ).getWorkById(workId);
        expect(collectionWork, isNotNull);
        expect(collectionWork!.containsKey('is_stored'), isFalse);
        expect(collectionWork.containsKey('storage_quality'), isFalse);
        expect(collectionWork.containsKey('storage_frame_rate'), isFalse);
        final collectionMedia = collectionWork['library_media'];
        expect(collectionMedia, isA<List>());
        final media = Map<String, Object?>.from(
          (collectionMedia! as List).single as Map,
        );
        final mediaPortableId = media['portable_id']?.toString() ?? '';
        expect(mediaPortableId, plan.items.single.mediaPortableId);

        final resolved =
            await LibraryMediaResolver(
              repository: LibraryRepository(db: db),
            ).resolveByPortableId(
              mediaPortableId,
              expectedWorkId: workId,
              expectedWorkPortableId: workRow['portable_id']?.toString(),
              verifyIntegrity: true,
            );
        expect(resolved.mediaPortableId, mediaPortableId);
        expect(File(resolved.absolutePath).existsSync(), isTrue);

        final platform = InMemoryPlayerPlatform(
          duration: const Duration(seconds: 10),
        );
        final controller = AvacaPlayerController(platform: platform);
        try {
          await controller.open(
            PlayerLaunchRequest(
              workCode: workRow['code']?.toString() ?? '',
              source: LocalPlayerMediaSource(resolved.absolutePath),
            ),
          );
          await Future<void>.delayed(Duration.zero);
          expect(platform.sessions, hasLength(1));
          expect(controller.state.phase, PlayerPhase.ready);
          expect(platform.sessions.single.closed, isFalse);
        } finally {
          await controller.close();
        }
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'review blocks multi-performer Work until a primary is explicit',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_primary_review_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final sourceRoot = Directory(p.join(root.path, 'source'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final sourceFile = File(p.join(sourceRoot.path, 'ABC-123.mp4'))
        ..writeAsStringSync('primary review fixture');
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final service = _fixtureService(db, _fixtureDetails(code: 'ABC-123'));
        final entry = (await LibraryFolderScanner().scan(
          sourceRoot.path,
        )).single.copyWith(selected: true);

        final plan = await service.buildPlan(
          sourceFolder: sourceRoot.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: [entry],
        );

        expect(plan.items, isEmpty);
        expect(
          plan.issues.single.message,
          contains('multiple performers require an explicit primary actress'),
        );
        expect(sourceFile.existsSync(), isTrue);
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test('review lookup is read-only until successful commit', () async {
    final root = await Directory.systemTemp.createTemp(
      'avaca_library_review_read_only_',
    );
    final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
    final sourceRoot = Directory(p.join(root.path, 'source'))..createSync();
    final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
    final sourceFile = File(p.join(sourceRoot.path, 'ABC-123.mp4'))
      ..writeAsStringSync('review read-only fixture');
    AppDatabase? db;
    try {
      db = AppDatabase.forTesting(
        baseDir: databaseRoot.path,
        databaseFactory: databaseFactoryFfi,
      );
      await db.init();
      final database = await db.database;
      final actressId = await database.insert('actresses', {
        'name': 'Actress A',
      });
      final service = _fixtureService(db, _fixtureDetails(code: 'ABC-123'));
      final entry = (await LibraryFolderScanner().scan(
        sourceRoot.path,
      )).single.copyWith(selected: true);

      final plan = await service.buildPlan(
        sourceFolder: sourceRoot.path,
        libraryRoot: libraryRoot.path,
        selectedEntries: [entry],
        primaryActressSelector: (_) => 'Actress A',
      );

      expect(plan.issues, isEmpty);
      final row = (await database.query(
        'actresses',
        where: 'id = ?',
        whereArgs: [actressId],
      )).single;
      expect(row['portable_id'], isNull);
      expect(sourceFile.existsSync(), isTrue);

      final preflight = await service.preflight(plan);
      final cancelled = await service.execute(
        plan,
        preflight,
        isCancelled: () => true,
      );
      expect(cancelled.items.single.state, LibraryImportResultState.cancelled);
      expect(
        (await database.query(
          'actresses',
          where: 'id = ?',
          whereArgs: [actressId],
        )).single['portable_id'],
        isNull,
      );
      expect(sourceFile.existsSync(), isTrue);

      final committed = await service.execute(plan, preflight);
      expect(committed.succeededCount, 1);
      expect(
        (await database.query(
          'actresses',
          where: 'id = ?',
          whereArgs: [actressId],
        )).single['portable_id'],
        isA<String>(),
      );
      expect(sourceFile.existsSync(), isFalse);
    } finally {
      await db?.close();
      if (root.existsSync()) await root.delete(recursive: true);
    }
  });

  test(
    'preflight failure does not assign a portable Actress identity',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_review_failure_identity_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final sourceRoot = Directory(p.join(root.path, 'source'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final sourceFile = File(p.join(sourceRoot.path, 'ABC-123.mp4'))
        ..writeAsStringSync('review failure identity fixture');
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final database = await db.database;
        final actressId = await database.insert('actresses', {
          'name': 'Actress A',
        });
        final service = _fixtureService(
          db,
          _fixtureDetails(code: 'ABC-123'),
          diskSpaceChecker: (_, _) async => false,
        );
        final entry = (await LibraryFolderScanner().scan(
          sourceRoot.path,
        )).single.copyWith(selected: true);
        final plan = await service.buildPlan(
          sourceFolder: sourceRoot.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: [entry],
          primaryActressSelector: (_) => 'Actress A',
        );
        final preflight = await service.preflight(plan);
        expect(preflight.isReady, isFalse);
        await expectLater(
          service.execute(plan, preflight),
          throwsA(isA<StateError>()),
        );
        expect(
          (await database.query(
            'actresses',
            where: 'id = ?',
            whereArgs: [actressId],
          )).single['portable_id'],
          isNull,
        );
        expect(sourceFile.existsSync(), isTrue);
        expect(await database.query('import_operations'), isEmpty);
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'commit refuses any review issue before journal or filesystem mutation',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_atomic_review_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final sourceRoot = Directory(p.join(root.path, 'source'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final sourceFile = File(p.join(sourceRoot.path, 'ABC-123.mp4'))
        ..writeAsStringSync('atomic review fixture');
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final repository = _CountingLibraryRepository(db: db);
        final service = _fixtureService(
          db,
          _fixtureDetails(code: 'ABC-123'),
          repository: repository,
        );
        final entry = (await LibraryFolderScanner().scan(
          sourceRoot.path,
        )).single.copyWith(selected: true);
        final plan = await service.buildPlan(
          sourceFolder: sourceRoot.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: [entry],
          primaryActressSelector: (_) => 'Actress A',
        );
        final preflight = await service.preflight(plan);
        final blockedPlan = LibraryImportPlan(
          sourceFolder: plan.sourceFolder,
          libraryRoot: plan.libraryRoot,
          items: plan.items,
          issues: const [
            LibraryPlanIssue(
              sourcePath: 'review',
              code: 'ABC-123',
              message: 'review issue',
            ),
          ],
          fingerprint: plan.fingerprint,
          revision: plan.revision,
        );

        await expectLater(
          service.execute(blockedPlan, preflight),
          throwsA(isA<StateError>()),
        );
        final mismatchedPlan = LibraryImportPlan(
          sourceFolder: plan.sourceFolder,
          libraryRoot: plan.libraryRoot,
          items: plan.items,
          issues: const [],
          fingerprint: 'different-reviewed-plan',
          revision: plan.revision,
        );
        await expectLater(
          service.execute(mismatchedPlan, preflight),
          throwsA(isA<StateError>()),
        );
        final itemErrorReport = LibraryPreflightReport(
          items: [
            LibraryPreflightItem(
              item: plan.items.single,
              duplicateMedia: false,
              error: 'item preflight failed',
            ),
          ],
          errors: const [],
          diskSpaceChecked: true,
          planFingerprint: plan.fingerprint,
          revision: plan.revision,
        );
        await expectLater(
          service.execute(plan, itemErrorReport),
          throwsA(isA<StateError>()),
        );
        final globalErrorReport = LibraryPreflightReport(
          items: preflight.items,
          errors: const [
            LibraryPlanIssue(
              sourcePath: 'review',
              code: 'ABC-123',
              message: 'global preflight error',
            ),
          ],
          diskSpaceChecked: true,
          planFingerprint: plan.fingerprint,
          revision: plan.revision,
        );
        await expectLater(
          service.execute(plan, globalErrorReport),
          throwsA(isA<StateError>()),
        );
        final staleReport = LibraryPreflightReport(
          items: preflight.items,
          errors: const [],
          diskSpaceChecked: true,
          planFingerprint: plan.fingerprint,
          revision: plan.revision + 1,
        );
        await expectLater(
          service.execute(plan, staleReport),
          throwsA(isA<StateError>()),
        );
        final emptyReport = LibraryPreflightReport(
          items: const [],
          errors: const [],
          diskSpaceChecked: true,
          planFingerprint: plan.fingerprint,
          revision: plan.revision,
        );
        await expectLater(
          service.execute(plan, emptyReport),
          throwsA(isA<StateError>()),
        );
        final emptyPlan = LibraryImportPlan(
          sourceFolder: plan.sourceFolder,
          libraryRoot: plan.libraryRoot,
          items: const [],
          issues: const [],
          fingerprint: plan.fingerprint,
          revision: plan.revision,
        );
        await expectLater(
          service.execute(emptyPlan, emptyReport),
          throwsA(isA<StateError>()),
        );
        final invalidPrimaryPlan = await service.buildPlan(
          sourceFolder: sourceRoot.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: [entry],
          primaryActressSelector: (_) => 'Unknown Actress',
        );
        final invalidPrimaryReport = LibraryPreflightReport(
          items: const [],
          errors: const [],
          diskSpaceChecked: true,
          planFingerprint: invalidPrimaryPlan.fingerprint,
          revision: invalidPrimaryPlan.revision,
        );
        await expectLater(
          service.execute(invalidPrimaryPlan, invalidPrimaryReport),
          throwsA(isA<StateError>()),
        );
        final database = await db.database;
        expect(await database.query('import_operations'), isEmpty);
        expect(await database.query('library_roots'), isEmpty);
        expect(await database.query('media_files'), isEmpty);
        expect(await database.query('actresses'), isEmpty);
        expect(sourceFile.existsSync(), isTrue);
        expect(
          Directory(
            p.join(libraryRoot.path, 'Actress A', 'ABC-123'),
          ).existsSync(),
          isFalse,
        );
        expect(repository.setActiveLibraryRootCalls, 0);
        expect(repository.createImportOperationCalls, 0);
        expect(repository.commitInfoDocumentCalls, 0);
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'different hashes for one normalized destination fail before commit',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_destination_collision_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final sourceRoot = Directory(p.join(root.path, 'source'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final firstFile = File(p.join(sourceRoot.path, 'ABC-123 [first].mp4'))
        ..writeAsBytesSync([1, 2, 3]);
      final secondFile = File(p.join(sourceRoot.path, 'ABC-123 [second].mp4'))
        ..writeAsBytesSync([4, 5, 6]);
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final repository = _CountingLibraryRepository(db: db);
        final service = _fixtureService(
          db,
          _fixtureDetails(code: 'ABC-123'),
          repository: repository,
        );
        final entries = await LibraryFolderScanner().scan(sourceRoot.path);
        final plan = await service.buildPlan(
          sourceFolder: sourceRoot.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: entries.map(
            (entry) => entry.copyWith(selected: true),
          ),
          primaryActressSelector: (_) => 'Actress A',
        );
        expect(plan.issues, isEmpty);
        expect(plan.items, hasLength(2));
        final preflight = await service.preflight(plan);
        expect(preflight.isReady, isFalse);
        expect(
          preflight.items.where((item) => item.error != null),
          hasLength(1),
        );
        expect(
          preflight.items.singleWhere((item) => item.error != null).error,
          contains('collision'),
        );

        await expectLater(
          service.execute(plan, preflight),
          throwsA(isA<StateError>()),
        );

        final database = await db.database;
        expect(repository.setActiveLibraryRootCalls, 0);
        expect(repository.createImportOperationCalls, 0);
        expect(await database.query('library_roots'), isEmpty);
        expect(await database.query('import_operations'), isEmpty);
        expect(await database.query('media_files'), isEmpty);
        expect(firstFile.existsSync(), isTrue);
        expect(secondFile.existsSync(), isTrue);
        expect(
          Directory(
            p.join(libraryRoot.path, 'Actress A', 'ABC-123'),
          ).existsSync(),
          isFalse,
        );
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'same-hash multipart entries keep one physical media and preserve duplicate source',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_multipart_dedupe_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final sourceRoot = Directory(p.join(root.path, 'source'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final bytes = <int>[7, 11, 13, 17];
      final firstFile = File(p.join(sourceRoot.path, 'ABC-123-CD1.mp4'))
        ..writeAsBytesSync(bytes);
      final secondFile = File(p.join(sourceRoot.path, 'ABC-123-CD2.mp4'))
        ..writeAsBytesSync(bytes);
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final service = _fixtureService(db, _fixtureDetails(code: 'ABC-123'));
        final entries = await LibraryFolderScanner().scan(sourceRoot.path);
        final plan = await service.buildPlan(
          sourceFolder: sourceRoot.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: entries.map(
            (entry) => entry.copyWith(selected: true),
          ),
          primaryActressSelector: (_) => 'Actress A',
        );
        expect(plan.items, hasLength(2));
        expect(plan.items.map((item) => item.entry.parseResult.partNumber), [
          1,
          2,
        ]);
        final preflight = await service.preflight(plan);
        expect(preflight.isReady, isTrue);
        expect(preflight.items.map((item) => item.duplicateMedia), [
          false,
          true,
        ]);

        final result = await service.execute(plan, preflight);

        expect(result.succeededCount, 1);
        expect(result.duplicateCount, 1);
        expect(firstFile.existsSync(), isFalse);
        expect(secondFile.existsSync(), isTrue);
        final database = await db.database;
        final mediaRows = await database.query('media_files');
        expect(mediaRows, hasLength(1));
        expect(mediaRows.single['relative_path'], 'ABC-123-CD1.mp4');
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test('destination folder appearing after preflight is not adopted', () async {
    final root = await Directory.systemTemp.createTemp(
      'avaca_library_destination_toctou_',
    );
    final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
    final sourceRoot = Directory(p.join(root.path, 'source'))..createSync();
    final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
    final sourceFile = File(p.join(sourceRoot.path, 'ABC-123.mp4'))
      ..writeAsStringSync('toctou fixture');
    AppDatabase? db;
    try {
      db = AppDatabase.forTesting(
        baseDir: databaseRoot.path,
        databaseFactory: databaseFactoryFfi,
      );
      await db.init();
      final service = _fixtureService(db, _fixtureDetails(code: 'ABC-123'));
      final entry = (await LibraryFolderScanner().scan(
        sourceRoot.path,
      )).single.copyWith(selected: true);
      final plan = await service.buildPlan(
        sourceFolder: sourceRoot.path,
        libraryRoot: libraryRoot.path,
        selectedEntries: [entry],
        primaryActressSelector: (_) => 'Actress A',
      );
      final preflight = await service.preflight(plan);
      expect(preflight.isReady, isTrue);
      final destinationWork = Directory(
        p.join(libraryRoot.path, plan.items.single.destinationRelativePath),
      )..createSync(recursive: true);

      final result = await service.execute(plan, preflight);

      expect(result.items.single.state, LibraryImportResultState.failed);
      expect(sourceFile.existsSync(), isTrue);
      expect(destinationWork.existsSync(), isTrue);
      expect(
        File(p.join(destinationWork.path, 'info.json')).existsSync(),
        isFalse,
      );
      final database = await db.database;
      expect(await database.query('media_files'), isEmpty);
      expect(
        (await database.query('import_operations')).single['state'],
        LibraryImportOperationState.failed.value,
      );
    } finally {
      await db?.close();
      if (root.existsSync()) await root.delete(recursive: true);
    }
  });

  test(
    'media appearing in an existing Work after preflight is never overwritten',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_media_toctou_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final sourceRoot = Directory(p.join(root.path, 'source'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final sourceFile = File(p.join(sourceRoot.path, 'ABC-123.mp4'))
        ..writeAsStringSync('toctou media fixture');
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final service = _fixtureService(db, _fixtureDetails(code: 'ABC-123'));
        final entry = (await LibraryFolderScanner().scan(
          sourceRoot.path,
        )).single.copyWith(selected: true);
        final plan = await service.buildPlan(
          sourceFolder: sourceRoot.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: [entry],
          primaryActressSelector: (_) => 'Actress A',
        );
        final preflight = await service.preflight(plan);
        expect(preflight.isReady, isTrue);
        final destinationWork = Directory(
          p.join(libraryRoot.path, plan.items.single.destinationRelativePath),
        );
        await LibraryInfoStore().write(
          destinationWork,
          LibraryInfoDocument(
            schemaVersion: 1,
            workId: plan.items.single.workPortableId,
            code: 'ABC-123',
            metadata: const {'title': 'External Work'},
            primaryActressId: plan.items.single.primaryActressId,
            performers: plan.items.single.performers,
            images: const {},
            media: const [],
            scrape: const {'source': 'external'},
            libraryRelativePath: plan.items.single.destinationRelativePath,
          ),
        );
        final destinationMedia = File(
          p.join(destinationWork.path, 'ABC-123.mp4'),
        )..writeAsStringSync('external media must survive');
        final originalDestinationBytes = await destinationMedia.readAsBytes();

        final result = await service.execute(plan, preflight);

        expect(result.items.single.state, LibraryImportResultState.failed);
        expect(sourceFile.existsSync(), isTrue);
        expect(await destinationMedia.readAsBytes(), originalDestinationBytes);
        final database = await db.database;
        expect(await database.query('media_files'), isEmpty);
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'final portable hash failure keeps the copy on the repair path',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_final_hash_failure_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final sourceRoot = Directory(p.join(root.path, 'source'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final sourceFile = File(p.join(sourceRoot.path, 'ABC-123.mp4'))
        ..writeAsStringSync('final hash fixture');
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final service = _fixtureService(
          db,
          _fixtureDetails(code: 'ABC-123'),
          filesystem: _FailFinalHashFilesystem(),
        );
        final entry = (await LibraryFolderScanner().scan(
          sourceRoot.path,
        )).single.copyWith(selected: true);
        final plan = await service.buildPlan(
          sourceFolder: sourceRoot.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: [entry],
          primaryActressSelector: (_) => 'Actress A',
        );
        final preflight = await service.preflight(plan);
        final result = await service.execute(plan, preflight);

        expect(
          result.items.single.state,
          LibraryImportResultState.repairRequired,
        );
        expect(sourceFile.existsSync(), isTrue);
        expect(
          File(
            p.join(libraryRoot.path, 'Actress A', 'ABC-123', 'ABC-123.mp4'),
          ).existsSync(),
          isTrue,
        );
        final database = await db.database;
        expect(await database.query('media_files'), isEmpty);
        expect(
          (await database.query('import_operations')).single['state'],
          LibraryImportOperationState.repairRequired.value,
        );
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'database indexing failure preserves portable media and source for repair',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_index_failure_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final sourceRoot = Directory(p.join(root.path, 'source'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final sourceFile = File(p.join(sourceRoot.path, 'ABC-123.mp4'))
        ..writeAsStringSync('index failure fixture');
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final service = _fixtureService(
          db,
          _fixtureDetails(code: 'ABC-123'),
          repository: _FailingCommitRepository(db: db),
        );
        final entry = (await LibraryFolderScanner().scan(
          sourceRoot.path,
        )).single.copyWith(selected: true);
        final plan = await service.buildPlan(
          sourceFolder: sourceRoot.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: [entry],
          primaryActressSelector: (_) => 'Actress A',
        );
        final preflight = await service.preflight(plan);
        final result = await service.execute(plan, preflight);

        expect(
          result.items.single.state,
          LibraryImportResultState.repairRequired,
        );
        expect(sourceFile.existsSync(), isTrue);
        expect(
          File(
            p.join(libraryRoot.path, 'Actress A', 'ABC-123', 'ABC-123.mp4'),
          ).existsSync(),
          isTrue,
        );
        final database = await db.database;
        expect(await database.query('media_files'), isEmpty);
        expect(
          (await database.query('import_operations')).single['state'],
          LibraryImportOperationState.repairRequired.value,
        );
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'source changed before cleanup is preserved while portable commit is repairable',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_source_changed_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final sourceRoot = Directory(p.join(root.path, 'source'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final sourceFile = File(p.join(sourceRoot.path, 'ABC-123.mp4'))
        ..writeAsStringSync('source before cleanup');
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final service = _fixtureService(
          db,
          _fixtureDetails(code: 'ABC-123'),
          imageDownloader: _MutatingImageDownloader(sourceFile),
        );
        final entry = (await LibraryFolderScanner().scan(
          sourceRoot.path,
        )).single.copyWith(selected: true);
        final plan = await service.buildPlan(
          sourceFolder: sourceRoot.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: [entry],
          primaryActressSelector: (_) => 'Actress A',
        );
        final preflight = await service.preflight(plan);
        final result = await service.execute(plan, preflight);

        expect(
          result.items.single.state,
          LibraryImportResultState.repairRequired,
        );
        expect(sourceFile.existsSync(), isTrue);
        expect(await sourceFile.readAsString(), 'source changed during import');
        expect(
          File(
            p.join(libraryRoot.path, 'Actress A', 'ABC-123', 'ABC-123.mp4'),
          ).existsSync(),
          isTrue,
        );
        final database = await db.database;
        expect(await database.query('media_files'), hasLength(1));
        expect(
          (await database.query('import_operations')).single['state'],
          LibraryImportOperationState.repairRequired.value,
        );
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'linking failure occurs before source cleanup and is restart-safe',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_link_failure_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final sourceRoot = Directory(p.join(root.path, 'source'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final sourceFile = File(p.join(sourceRoot.path, 'ABC-123.mp4'))
        ..writeAsStringSync('link failure fixture');
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final service = _fixtureService(
          db,
          _fixtureDetails(code: 'ABC-123'),
          shortcutManager: const _FailingShortcutManager(),
        );
        final entry = (await LibraryFolderScanner().scan(
          sourceRoot.path,
        )).single.copyWith(selected: true);
        final plan = await service.buildPlan(
          sourceFolder: sourceRoot.path,
          libraryRoot: libraryRoot.path,
          selectedEntries: [entry],
          primaryActressSelector: (_) => 'Actress A',
        );
        final preflight = await service.preflight(plan);
        final result = await service.execute(plan, preflight);

        expect(
          result.items.single.state,
          LibraryImportResultState.repairRequired,
        );
        expect(sourceFile.existsSync(), isTrue);
        expect(await (await db.database).query('media_files'), hasLength(1));
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );

  test('import recovery cleans pre-commit staging idempotently', () async {
    final root = await Directory.systemTemp.createTemp(
      'avaca_library_recovery_',
    );
    final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
    final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
    AppDatabase? db;
    try {
      db = AppDatabase.forTesting(
        baseDir: databaseRoot.path,
        databaseFactory: databaseFactoryFfi,
      );
      await db.init();
      final repository = LibraryRepository(db: db);
      final operationId = await repository.createImportOperation(
        libraryRoot: libraryRoot.path,
        planFingerprint: 'recovery-fixture',
      );
      final staging = Directory(
        p.join(libraryRoot.path, '.__avaca_importing', operationId),
      )..createSync(recursive: true);
      File(p.join(staging.path, 'stale.tmp')).writeAsStringSync('stale');
      final committedOperationId = await repository.createImportOperation(
        libraryRoot: libraryRoot.path,
        planFingerprint: 'committed-recovery-fixture',
      );
      await repository.updateImportOperation(
        operationId: committedOperationId,
        state: LibraryImportOperationState.portableCommitted,
        committed: true,
      );
      final committedMedia = File(p.join(libraryRoot.path, 'keep.mp4'))
        ..writeAsStringSync('portable copy must survive recovery');
      final recovery = LibraryImportRecoveryService(
        repository: repository,
        filesystem: LibraryFilesystem(),
      );

      final first = await recovery.recover();
      final second = await recovery.recover();

      expect(first.cleaned, 1);
      expect(first.repairRequired, 1);
      expect(second.cleaned, 0);
      expect(second.repairRequired, 0);
      expect(staging.existsSync(), isFalse);
      expect(committedMedia.existsSync(), isTrue);
      expect(
        (await (await db.database).query(
          'import_operations',
          where: 'id = ?',
          whereArgs: [operationId],
        )).single['state'],
        LibraryImportOperationState.cancelledBeforeCommit.value,
      );
      expect(
        (await (await db.database).query(
          'import_operations',
          where: 'id = ?',
          whereArgs: [committedOperationId],
        )).single['state'],
        LibraryImportOperationState.repairRequired.value,
      );
    } finally {
      await db?.close();
      if (root.existsSync()) await root.delete(recursive: true);
    }
  });

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
          primaryActressSelector: (_) => 'Actress A',
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
          primaryActressSelector: (_) => 'Actress A',
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
          primaryActressSelector: (_) => 'Actress A',
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

class _CountingLibraryRepository extends LibraryRepository {
  _CountingLibraryRepository({required super.db});

  var setActiveLibraryRootCalls = 0;
  var createImportOperationCalls = 0;
  var commitInfoDocumentCalls = 0;

  @override
  Future<String> setActiveLibraryRoot(String rootPath) {
    setActiveLibraryRootCalls++;
    return super.setActiveLibraryRoot(rootPath);
  }

  @override
  Future<String> createImportOperation({
    required String libraryRoot,
    required String planFingerprint,
    Iterable<Map<String, Object?>> items = const [],
  }) {
    createImportOperationCalls++;
    return super.createImportOperation(
      libraryRoot: libraryRoot,
      planFingerprint: planFingerprint,
      items: items,
    );
  }

  @override
  Future<LibraryWorkCommitResult> commitInfoDocument(
    LibraryInfoDocument document, {
    required String libraryRoot,
    String? importOperationId,
  }) {
    commitInfoDocumentCalls++;
    return super.commitInfoDocument(
      document,
      libraryRoot: libraryRoot,
      importOperationId: importOperationId,
    );
  }
}

class _FailFinalHashFilesystem extends LibraryFilesystem {
  @override
  Future<String> hashFile(String filePath) {
    final normalized = filePath.toLowerCase().replaceAll('\\', '/');
    if (normalized.endsWith('/actress a/abc-123/abc-123.mp4')) {
      throw StateError('simulated final hash failure');
    }
    return super.hashFile(filePath);
  }
}

class _FailingCommitRepository extends LibraryRepository {
  _FailingCommitRepository({required super.db});

  @override
  Future<LibraryWorkCommitResult> commitInfoDocument(
    LibraryInfoDocument document, {
    required String libraryRoot,
    String? importOperationId,
  }) async {
    throw StateError('simulated database indexing failure');
  }
}

class _MutatingImageDownloader implements LibraryImageDownloader {
  _MutatingImageDownloader(this.sourceFile);

  final File sourceFile;
  var _mutated = false;

  @override
  Future<LibraryImageDownloadResult> download({
    required ScrapeWorkDetails details,
    required String destinationDirectory,
  }) async {
    if (!_mutated) {
      _mutated = true;
      sourceFile.writeAsStringSync('source changed during import');
    }
    return const LibraryImageDownloadResult();
  }

  @override
  void close() {}
}

class _FailingShortcutManager implements LibraryShortcutManager {
  const _FailingShortcutManager();

  @override
  bool get isSupported => true;

  @override
  Future<void> createDirectoryShortcut({
    required String linkPath,
    required String targetPath,
  }) async {
    throw StateError('simulated performer link failure');
  }
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
  ScrapeWorkDetails details, {
  LibraryRepository? repository,
  Future<bool> Function(String root, int requiredBytes)? diskSpaceChecker,
  LibraryFilesystem? filesystem,
  LibraryShortcutManager? shortcutManager,
  LibraryImageDownloader? imageDownloader,
}) {
  return LibraryImportService(
    repository: repository ?? LibraryRepository(db: db),
    resolver: LibraryExactWorkResolver(
      sources: {ScrapeSourceId.javbus: _FakeSource(details)},
      priority: const [ScrapeSourceId.javbus],
    ),
    mediaProbe: const _FakeProbe(),
    filesystem: filesystem ?? LibraryFilesystem(),
    shortcutManager: shortcutManager ?? const _RecordingShortcutManager(),
    imageDownloader: imageDownloader,
    diskSpaceChecker: diskSpaceChecker,
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
