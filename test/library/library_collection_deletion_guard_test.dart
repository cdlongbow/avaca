import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:avaca/controllers/detail_controller.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/library/library_collection_service.dart';
import 'package:avaca/library/library_filesystem.dart';
import 'package:avaca/library/library_info_store.dart';
import 'package:avaca/library/library_models.dart';
import 'package:avaca/library/library_repository.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'normal Collection deletion preserves Library DB rows and physical media',
    () async {
      final root = Directory(
        p.join(
          Directory.systemTemp.path,
          'avaca_collection_delete_guard_test_${DateTime.now().microsecondsSinceEpoch}',
        ),
      )..createSync(recursive: true);
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))
        ..createSync(recursive: true);
      final workDirectory = Directory(
        p.join(libraryRoot.path, 'Actress A', 'ABC-123'),
      )..createSync(recursive: true);
      final mediaFile = File(p.join(workDirectory.path, 'ABC-123.mp4'))
        ..writeAsStringSync('physical media must remain');
      AppDatabase? db;
      DetailController? controller;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final repository = LibraryRepository(db: db);
        await repository.setActiveLibraryRoot(libraryRoot.path);
        final document = LibraryInfoDocument(
          schemaVersion: 1,
          workId: 'work-1',
          code: 'ABC-123',
          metadata: const {
            'title': 'Physical work',
            'primaryActressName': 'Actress A',
          },
          primaryActressId: 'actress-1',
          performers: const [
            {'actressId': 'actress-1', 'name': 'Actress A'},
          ],
          images: const {},
          media: [
            LibraryMediaRecord(
              mediaId: 'media-1',
              workId: 'work-1',
              relativePath: 'ABC-123.mp4',
              fileName: 'ABC-123.mp4',
              originalFileName: 'ABC-123.mp4',
              variant: null,
              variantType: null,
              hasChineseSubtitles: null,
              partNumber: null,
              partLabel: null,
              width: 1920,
              height: 1080,
              resolutionLabel: '1080p',
              frameRateNumerator: 30,
              frameRateDenominator: 1,
              frameRateDecimal: 30,
              durationMs: 1000,
              container: 'mp4',
              codec: 'h264',
              fileSizeBytes: mediaFile.lengthSync(),
              sha256: '',
              sourceFileCreatedAt: DateTime.utc(2026, 8, 31),
              importedAt: DateTime.utc(2026, 8, 31),
              probeBackend: 'fixture',
              probeVersion: '1',
              parserVersion: 1,
            ),
          ],
          scrape: const {'source': 'fixture'},
          libraryRelativePath: 'Actress A/ABC-123',
        );
        await repository.commitInfoDocument(
          document,
          libraryRoot: libraryRoot.path,
        );
        await LibraryInfoStore(filesystem: LibraryFilesystem()).write(
          workDirectory,
          document,
        );

        final database = await db.database;
        final actressId = ((await database.query(
          'actresses',
          columns: const ['id'],
          where: 'portable_id = ?',
          whereArgs: ['actress-1'],
        )).single['id'] as num).toInt();
        final service = LibraryCollectionService(db: db);
        controller = DetailController(
          db: db,
          actressId: actressId,
          collectionService: service,
        );
        await controller.executeDelete(_UnmountedBuildContext());

        expect(mediaFile.existsSync(), isTrue);
        expect(
          File(p.join(workDirectory.path, 'info.json')).existsSync(),
          isTrue,
        );
        expect(await database.query('actresses'), hasLength(1));
        expect(
          await database.query('works', where: 'library_managed = 1'),
          hasLength(1),
        );
        expect(await database.query('media_files'), hasLength(1));
        expect(await database.query('actress_works'), hasLength(1));
      } finally {
        controller?.dispose();
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );
}

final class _UnmountedBuildContext implements BuildContext {
  @override
  bool get mounted => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
