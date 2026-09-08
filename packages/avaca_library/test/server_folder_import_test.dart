import 'dart:io';

import 'package:avaca_domain/avaca_domain.dart';
import 'package:avaca_library/avaca_library.dart';
import 'package:avaca_scraper/avaca_scraper.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Server folder import scans asynchronously and reports stage timings',
    () async {
      final root = await Directory.systemTemp.createTemp('avaca-import-');
      try {
        final nested = Directory('${root.path}${Platform.pathSeparator}nested');
        await nested.create();
        await File(
          '${nested.path}${Platform.pathSeparator}ABP-001.mkv',
        ).writeAsBytes(const <int>[1, 2, 3]);
        await File(
          '${root.path}${Platform.pathSeparator}unrecognised.mkv',
        ).writeAsBytes(const <int>[4, 5]);
        await File(
          '${root.path}${Platform.pathSeparator}notes.txt',
        ).writeAsString('not media');

        final writer = _RecordingCatalogWriter();
        final scraper = _RecordingScraper();
        final stages = <ServerImportStage>[];
        final result =
            await ServerFolderImportService(
              catalogWriter: writer,
              scraper: scraper,
            ).importFolder(
              root.path,
              onProgress: (progress) => stages.add(progress.stage),
            );

        expect(result.cancelled, isFalse);
        expect(result.scanned, 2);
        expect(result.imported, 1);
        expect(result.skipped, 1);
        expect(result.failed, 0);
        expect(result.totalDuration, greaterThanOrEqualTo(Duration.zero));
        expect(scraper.codes, <String>['ABP-1']);
        expect(writer.media, hasLength(1));
        expect(writer.media.single.length, 3);
        expect(
          stages,
          containsAllInOrder(const <ServerImportStage>[
            ServerImportStage.scanning,
            ServerImportStage.resolving,
            ServerImportStage.indexing,
            ServerImportStage.completed,
          ]),
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'Server folder import cancels at an item boundary without writing',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca-import-cancel-',
      );
      try {
        await File(
          '${root.path}${Platform.pathSeparator}ABP-001.mkv',
        ).writeAsBytes(const <int>[1]);
        final writer = _RecordingCatalogWriter();
        var cancel = false;
        final stages = <ServerImportStage>[];
        final result =
            await ServerFolderImportService(
              catalogWriter: writer,
              scraper: _RecordingScraper(),
            ).importFolder(
              root.path,
              isCancelled: () => cancel,
              onProgress: (progress) {
                stages.add(progress.stage);
                if (progress.stage == ServerImportStage.scanning) cancel = true;
              },
            );

        expect(result.cancelled, isTrue);
        expect(result.imported, 0);
        expect(writer.media, isEmpty);
        expect(
          stages,
          containsAllInOrder(const <ServerImportStage>[
            ServerImportStage.scanning,
            ServerImportStage.cancelled,
          ]),
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'Server folder import refuses silent truncation at its file limit',
    () async {
      final root = await Directory.systemTemp.createTemp('avaca-import-limit-');
      try {
        await File(
          '${root.path}${Platform.pathSeparator}ABP-001.mkv',
        ).writeAsBytes(const <int>[1]);
        await File(
          '${root.path}${Platform.pathSeparator}ABP-002.mkv',
        ).writeAsBytes(const <int>[2]);
        final service = ServerFolderImportService(
          catalogWriter: _RecordingCatalogWriter(),
          scraper: _RecordingScraper(),
          maxFiles: 1,
        );

        await expectLater(
          service.importFolder(root.path),
          throwsA(
            isA<ServerProtocolException>().having(
              (error) => error.code,
              'code',
              'import_limit_exceeded',
            ),
          ),
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'Server folder import rejects an empty root before touching the filesystem',
    () async {
      await expectLater(
        ServerFolderImportService(
          catalogWriter: _RecordingCatalogWriter(),
          scraper: _RecordingScraper(),
        ).importFolder('   '),
        throwsA(
          isA<ServerProtocolException>().having(
            (error) => error.code,
            'code',
            'invalid_import_root',
          ),
        ),
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'Server folder import populates the Server catalog and playable media',
    () async {
      final root = await Directory.systemTemp.createTemp('avaca-import-db-');
      final repository = await ServerSqliteCatalogRepository.open(
        databasePath: '${root.path}${Platform.pathSeparator}server.sqlite',
      );
      try {
        final mediaPath = '${root.path}${Platform.pathSeparator}ABP-001.mkv';
        await File(mediaPath).writeAsBytes(const <int>[9, 8, 7, 6]);
        final result = await ServerFolderImportService(
          catalogWriter: repository,
          scraper: _RecordingScraper(),
        ).importFolder(root.path);

        expect(result.imported, 1);
        final page = await repository.listCollection(limit: 10);
        expect(page.items, hasLength(1));
        expect(page.items.single.code, 'ABP-1');
        final detail = await repository.getWorkDetail(page.items.single.workId);
        expect(detail.media, hasLength(1));
        expect(
          detail.media.single.availability,
          AvacaMediaAvailability.available,
        );
        final selection = await repository.findPlayback(
          detail.media.single.mediaId,
        );
        expect(selection?.absolutePath, mediaPath);
        expect(selection?.length, 4);
      } finally {
        await repository.close();
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}

final class _RecordingCatalogWriter implements ServerCatalogWriter {
  final List<AvacaWorkSummary> works = <AvacaWorkSummary>[];
  final List<ServerMediaRecord> media = <ServerMediaRecord>[];

  @override
  Future<void> upsertWork(AvacaWorkSummary work) async => works.add(work);

  @override
  Future<void> upsertMedia(ServerMediaRecord value) async => media.add(value);
}

final class _RecordingScraper implements AvacaScraper {
  final List<String> codes = <String>[];

  @override
  Future<AvacaWorkSummary> resolveWork(String code) async {
    codes.add(code);
    return AvacaWorkSummary(
      workId: AvacaWorkId('work.$code'),
      code: code,
      title: 'Title $code',
    );
  }
}
