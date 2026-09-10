import 'dart:io';

import 'package:avaca_domain/avaca_domain.dart';
import 'package:avaca_library/avaca_library.dart';
import 'package:avaca_scraper/avaca_scraper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  test('filename parser preserves variants and marks ambiguity for review', () {
    const parser = ServerFilenameParser();

    final variant = parser.parse('ABP-001-U-1080P.mkv');
    expect(variant.status, ServerPhysicalParseStatus.recognized);
    expect(variant.code, 'ABP-1');
    expect(variant.variantToken, 'U');
    expect(variant.noiseTokens, contains('1080P'));

    final ambiguous = parser.parse('ABP-001-C-UC.mkv');
    expect(ambiguous.status, ServerPhysicalParseStatus.ambiguous);
    expect(ambiguous.code, isNull);
  });

  test(
    'physical inventory is durable when metadata is absent and re-scan is idempotent',
    () async {
      final root = await Directory.systemTemp.createTemp('avaca-recovery-');
      final repository = await ServerSqliteCatalogRepository.open(
        databasePath: '${root.path}${Platform.pathSeparator}server.sqlite',
      );
      try {
        await File(
          '${root.path}${Platform.pathSeparator}ABP-001-U.mkv',
        ).writeAsBytes(const <int>[1, 2, 3]);
        await File(
          '${root.path}${Platform.pathSeparator}needs-review.mkv',
        ).writeAsBytes(const <int>[4, 5]);

        final service = ServerFolderImportService(catalogWriter: repository);
        final first = await service.importFolder(root.path);
        expect(first.physicalIndexed, 2);
        expect(first.imported, 2);
        expect(first.skipped, 0);
        expect(first.needsReview, 2);

        final review = await repository.listReviewItems();
        expect(review, hasLength(2));
        expect(
          review.map((item) => item.fileName),
          contains('needs-review.mkv'),
        );
        final needsReview = review.firstWhere(
          (item) => item.fileName == 'needs-review.mkv',
        );
        await repository.applyManualCode(
          mediaId: needsReview.mediaId,
          code: 'XYZ-002',
        );
        expect(await repository.findManualCode(needsReview.mediaId), 'XYZ-2');

        final second = await service.importFolder(root.path);
        expect(second.physicalIndexed, 2);
        expect((await repository.listReviewItems()), hasLength(2));
      } finally {
        await repository.close();
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'rich metadata updates work details without changing physical authority',
    () async {
      final root = await Directory.systemTemp.createTemp('avaca-rich-');
      final repository = await ServerSqliteCatalogRepository.open(
        databasePath: '${root.path}${Platform.pathSeparator}server.sqlite',
      );
      try {
        await File(
          '${root.path}${Platform.pathSeparator}ABP-001.mkv',
        ).writeAsBytes(const <int>[1]);
        final result = await ServerFolderImportService(
          catalogWriter: repository,
          scraper: _RichScraper(),
        ).importFolder(root.path);
        expect(result.metadataResolved, 1);
        final page = await repository.listCollection();
        final detail = await repository.getWorkDetail(page.items.single.workId);
        expect(detail.description, 'Server-owned description');
        expect(detail.releaseDate, '2026-09-10');
        expect(detail.performers.single.displayName, 'Performer');
        expect((await repository.listReviewItems()), isEmpty);
      } finally {
        await repository.close();
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'v1 Server catalog rows survive the additive v2 migration',
    () async {
      final root = await Directory.systemTemp.createTemp('avaca-migration-');
      final databasePath = '${root.path}${Platform.pathSeparator}server.sqlite';
      sqfliteFfiInit();
      final oldDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (database, _) async {
            await database.execute(
              'CREATE TABLE server_works (portable_id TEXT PRIMARY KEY, code TEXT NOT NULL, title TEXT NOT NULL, cover_resource_id TEXT, modified_at TEXT NOT NULL)',
            );
            await database.execute(
              'CREATE TABLE server_media (portable_id TEXT PRIMARY KEY, work_portable_id TEXT NOT NULL, absolute_path TEXT NOT NULL, length_bytes INTEGER NOT NULL, mime_type TEXT NOT NULL, duration_ms INTEGER, modified_at TEXT NOT NULL)',
            );
          },
        ),
      );
      await oldDatabase.insert('server_works', {
        'portable_id': 'work-old',
        'code': 'OLD-1',
        'title': 'Old row',
        'modified_at': DateTime.now().toUtc().toIso8601String(),
      });
      await oldDatabase.insert('server_media', {
        'portable_id': 'media-old',
        'work_portable_id': 'work-old',
        'absolute_path': 'C:/old/fixture.mkv',
        'length_bytes': 0,
        'mime_type': 'video/x-matroska',
        'modified_at': DateTime.now().toUtc().toIso8601String(),
      });
      await oldDatabase.close();
      final repository = await ServerSqliteCatalogRepository.open(
        databasePath: databasePath,
      );
      try {
        final detail = await repository.getWorkDetail(
          const AvacaWorkId('work-old'),
        );
        expect(detail.title, 'Old row');
        expect(detail.media.single.mediaId.value, 'media-old');
      } finally {
        await repository.close();
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}

final class _RichScraper implements AvacaScraper, AvacaRichScraper {
  @override
  Future<AvacaWorkSummary> resolveWork(String code) async => AvacaWorkSummary(
    workId: AvacaWorkId('work.$code'),
    code: code,
    title: 'Title $code',
  );

  @override
  Future<AvacaWorkMetadata> resolveWorkDetails(String code) async =>
      AvacaWorkMetadata(
        summary: AvacaWorkSummary(
          workId: AvacaWorkId('work.$code'),
          code: code,
          title: 'Title $code',
        ),
        description: 'Server-owned description',
        releaseDate: '2026-09-10',
        performers: const <AvacaPerformerMetadata>[
          AvacaPerformerMetadata(
            performerId: AvacaActressId('performer-1'),
            displayName: 'Performer',
          ),
        ],
        source: 'fixture',
      );
}
