import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:avaca/core/database.dart';
import 'package:avaca/library/library_collection_service.dart';
import 'package:avaca/library/library_models.dart';
import 'package:avaca/library/library_repository.dart';
import 'package:avaca/models/work.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'normal Collection only exposes physically resolvable Library media',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_library_collection_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final workDirectory = Directory(
        p.join(libraryRoot.path, 'Actress A', 'ABC-123'),
      )..createSync(recursive: true);
      final mediaFile = File(p.join(workDirectory.path, 'ABC-123.mp4'))
        ..writeAsStringSync('physical media');
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final repository = LibraryRepository(db: db);
        await repository.setActiveLibraryRoot(libraryRoot.path);
        await repository.commitInfoDocument(
          LibraryInfoDocument(
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
            media: [_mediaRecord()],
            scrape: const {'source': 'fixture'},
            libraryRelativePath: 'Actress A/ABC-123',
          ),
          libraryRoot: libraryRoot.path,
        );

        final database = await db.database;
        final metadataOnlyActress = await db.addActress(name: 'Metadata only');
        expect(metadataOnlyActress, isTrue);
        final metadataOnlyId =
            (await database.query(
                  'actresses',
                  columns: const ['id'],
                  where: 'name = ?',
                  whereArgs: ['Metadata only'],
                )).single['id']
                as int;
        await db.upsertActressWork(
          actressId: metadataOnlyId,
          work: const Work(code: 'META-001', title: 'Metadata-only work'),
        );

        final collection = LibraryCollectionService(db: db);
        expect((await collection.getActresses()).map((row) => row['name']), [
          'Actress A',
        ]);
        expect(await collection.getActressById(metadataOnlyId), isNull);
        expect(await collection.getWorksForActress(metadataOnlyId), isEmpty);
        final physicalActressId =
            (await database.query(
                  'actresses',
                  columns: const ['id'],
                  where: 'name = ?',
                  whereArgs: ['Actress A'],
                )).single['id']
                as int;
        expect(
          (await collection.getWorksForActress(
            physicalActressId,
          )).single['code'],
          'ABC-123',
        );
        expect(
          await collection.getActressById(physicalActressId),
          containsPair('name', 'Actress A'),
        );

        await database.update(
          'media_files',
          {'portable_id': ''},
          where: 'work_id = ?',
          whereArgs: [
            (await database.query(
              'works',
              columns: const ['id'],
              where: 'code = ?',
              whereArgs: ['ABC-123'],
            )).single['id'],
          ],
        );
        expect(await collection.getActresses(), isEmpty);
        expect(await collection.getActressById(physicalActressId), isNull);
        expect(await collection.getWorksForActress(physicalActressId), isEmpty);

        await mediaFile.delete();
        expect(await collection.getActresses(), isEmpty);
        expect(await collection.getActressById(physicalActressId), isNull);
        expect(await collection.getWorksForActress(physicalActressId), isEmpty);
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );
}

LibraryMediaRecord _mediaRecord() => LibraryMediaRecord(
  mediaId: 'media-1',
  workId: 'work-1',
  relativePath: 'ABC-123.mp4',
  fileName: 'ABC-123.mp4',
  originalFileName: 'source.mp4',
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
  frameRateDecimal: 29.97,
  durationMs: 1000,
  container: 'mp4',
  codec: 'h264',
  fileSizeBytes: 14,
  sha256: '',
  sourceFileCreatedAt: DateTime.utc(2026, 8, 30),
  importedAt: DateTime.utc(2026, 8, 30),
  probeBackend: 'fixture',
  probeVersion: '1',
  parserVersion: 1,
);
