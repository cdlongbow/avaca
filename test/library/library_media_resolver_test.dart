import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:avaca/core/database.dart';
import 'package:avaca/library/library_filesystem.dart';
import 'package:avaca/library/library_media_locator.dart';
import 'package:avaca/library/library_media_resolver.dart';
import 'package:avaca/library/library_models.dart';
import 'package:avaca/library/library_repository.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'resolves by mediaPortableId and fails closed on identity violations',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_media_resolver_',
      );
      final databaseRoot = Directory(p.join(root.path, 'db'))..createSync();
      final libraryRoot = Directory(p.join(root.path, 'library'))..createSync();
      final workDirectory = Directory(
        p.join(libraryRoot.path, 'Actress A', 'ABC-123'),
      )..createSync(recursive: true);
      final bytes = utf8.encode('portable resolver fixture');
      final mediaFile = File(p.join(workDirectory.path, 'ABC-123.mp4'))
        ..writeAsBytesSync(bytes);
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: databaseRoot.path,
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final repository = LibraryRepository(db: db);
        await repository.setActiveLibraryRoot(libraryRoot.path);
        final sha256 = await LibraryFilesystem().hashFile(mediaFile.path);
        await repository.commitInfoDocument(
          LibraryInfoDocument(
            schemaVersion: 1,
            workId: 'work-1',
            code: 'ABC-123',
            metadata: const {'title': 'Fixture'},
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
                originalFileName: 'source.mp4',
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
                fileSizeBytes: bytes.length,
                sha256: sha256,
                sourceFileCreatedAt: DateTime.utc(2026, 8, 31),
                importedAt: DateTime.utc(2026, 8, 31),
                probeBackend: 'fixture',
                probeVersion: '1',
                parserVersion: 1,
              ),
            ],
            scrape: const {'source': 'fixture'},
            libraryRelativePath: 'Actress A/ABC-123',
          ),
          libraryRoot: libraryRoot.path,
        );

        final database = await db.database;
        final workId =
            ((await database.query(
                      'works',
                      columns: const ['id'],
                      where: 'portable_id = ?',
                      whereArgs: ['work-1'],
                    )).single['id']
                    as num)
                .toInt();
        final resolver = LibraryMediaResolver(repository: repository);

        final resolved = await resolver.resolveByPortableId('media-1');
        expect(resolved.absolutePath, mediaFile.absolute.path);
        expect(resolved.mediaPortableId, 'media-1');
        expect(await repository.lookupMediaByPortableId('media-1'), isNotNull);

        await expectLater(
          resolver.resolveByPortableId('missing-media'),
          throwsA(isA<LibraryLocatorFailure>()),
        );
        await expectLater(
          resolver.resolveByPortableId('media-1', expectedWorkId: workId + 1),
          throwsA(isA<LibraryLocatorFailure>()),
        );
        await expectLater(
          resolver.resolveByPortableId(
            'media-1',
            expectedWorkPortableId: 'other-work',
          ),
          throwsA(isA<LibraryLocatorFailure>()),
        );

        await database.update(
          'media_files',
          {'file_size_bytes': bytes.length + 1},
          where: 'portable_id = ?',
          whereArgs: ['media-1'],
        );
        await expectLater(
          resolver.resolveByPortableId('media-1'),
          throwsA(isA<LibraryLocatorFailure>()),
        );
        await database.update(
          'media_files',
          {'file_size_bytes': bytes.length},
          where: 'portable_id = ?',
          whereArgs: ['media-1'],
        );

        await database.update(
          'media_files',
          {'sha256': List.filled(64, '0').join()},
          where: 'portable_id = ?',
          whereArgs: ['media-1'],
        );
        await expectLater(
          resolver.resolveByPortableId('media-1'),
          throwsA(isA<LibraryLocatorFailure>()),
        );
        await database.update(
          'media_files',
          {'sha256': sha256},
          where: 'portable_id = ?',
          whereArgs: ['media-1'],
        );

        await database.update(
          'media_files',
          {'relative_path': '../escape.mp4'},
          where: 'portable_id = ?',
          whereArgs: ['media-1'],
        );
        await expectLater(
          resolver.resolveByPortableId('media-1'),
          throwsA(isA<LibraryLocatorFailure>()),
        );
        await database.update(
          'media_files',
          {'relative_path': 'ABC-123.mp4'},
          where: 'portable_id = ?',
          whereArgs: ['media-1'],
        );

        await database.update(
          'works',
          {'library_managed': 0},
          where: 'id = ?',
          whereArgs: [workId],
        );
        await expectLater(
          resolver.resolveByPortableId('media-1'),
          throwsA(isA<LibraryLocatorFailure>()),
        );
      } finally {
        await db?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );
}
