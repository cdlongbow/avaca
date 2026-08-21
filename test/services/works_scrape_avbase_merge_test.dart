import 'dart:io';
import 'dart:typed_data';

import 'package:avaca/core/database.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/models/scraped_actress_details.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:avaca/services/javbus/work_image_downloader.dart';
import 'package:avaca/services/javbus/work_image_policy.dart';
import 'package:avaca/services/javbus/work_image_route_resolver.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/services/scrape/scrape_source.dart';
import 'package:avaca/services/works_scrape_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'all work sources merge one canonical code with JavBus priority',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_avbase_merge_test_',
      );
      final database = AppDatabase.forTesting(
        baseDir: directory.path,
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      await database.init();
      await database.addActress(name: '測試女優');
      final actressId =
          (await (await database.database).query('actresses')).single['id']
              as int;

      final service = WorksScrapeService(
        db: database,
        sources: {
          ScrapeSourceId.javbus: _FakeScrapeSource(
            id: ScrapeSourceId.javbus,
            title: 'JavBus 標題',
            studio: null,
            durationMinutes: 10,
            performerCount: 1,
          ),
          ScrapeSourceId.avbase: _FakeScrapeSource(
            id: ScrapeSourceId.avbase,
            title: 'AvBase 標題',
            studio: 'AvBase 補上的片商',
            series: 'AvBase 系列',
            durationMinutes: 20,
            performerCount: 3,
          ),
        },
        workImageDownloader: _FakeWorkImageDownloader(),
        imageDirectory: directory.path,
        javBusDetailDelay: Duration.zero,
      );
      final progress = <WorksScrapeProgress>[];

      final result = await service.scrape(
        actressId: actressId,
        actressName: '測試女優',
        options: const WorkScrapeOptions(syncDetails: false),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.javbus,
          worksSource: WorksSourceSelection.all,
        ),
        onProgress: progress.add,
      );
      expect(result.saved, 1);
      expect(result.failed, 0);
      expect(
        progress.any(
          (item) =>
              item.phase == WorksScrapePhase.fetchingDetails &&
              item.source == ScrapeSourceId.javbus &&
              item.sourceProgress[ScrapeSourceId.javbus]?.current == 1,
        ),
        isTrue,
        reason: 'JavBus detail progress must leave 0 after its request ends.',
      );
      expect(
        progress.any(
          (item) =>
              item.phase == WorksScrapePhase.fetchingDetails &&
              item.source == ScrapeSourceId.avbase &&
              item.sourceProgress[ScrapeSourceId.avbase]?.current == 1,
        ),
        isTrue,
        reason: 'AvBase detail progress must leave 0 after its request ends.',
      );
      expect(result.worksSources, [
        ScrapeSourceId.javbus,
        ScrapeSourceId.avbase,
      ]);
      expect(await database.getWorkCountForActress(actressId), 1);
      final work = (await database.getWorksForActress(actressId)).single;
      expect(work['code'], 'ABC-123');
      expect(work['title'], 'JavBus 標題');
      expect(work['studio'], 'AvBase 補上的片商');
      expect(work['series'], 'AvBase 系列');
      expect(work['duration_minutes'], 10);

      // JavBus reports one performer and AvBase reports three.  A limit of
      // two must therefore exclude the merged canonical work, proving that
      // the cross-source performerCount maximum is applied before saving.
      final maxFilteredResult = await service.scrape(
        actressId: actressId,
        actressName: '測試女優',
        options: const WorkScrapeOptions(
          syncDetails: false,
          maxActressCount: 2,
        ),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.javbus,
          worksSource: WorksSourceSelection.all,
        ),
      );
      expect(maxFilteredResult.saved, 0);
      expect(maxFilteredResult.excluded, 1);

      final atLimitResult = await service.scrape(
        actressId: actressId,
        actressName: '測試女優',
        options: const WorkScrapeOptions(
          syncDetails: false,
          maxActressCount: 3,
        ),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.javbus,
          worksSource: WorksSourceSelection.all,
        ),
      );
      expect(atLimitResult.saved, 1);
      expect(atLimitResult.excluded, 0);
      service.close();
    },
  );
}

final class _FakeScrapeSource implements ScrapeSource {
  _FakeScrapeSource({
    required this.id,
    required this.title,
    required this.studio,
    this.series,
    required this.durationMinutes,
    required this.performerCount,
  });

  @override
  final ScrapeSourceId id;
  final String title;
  final String? studio;
  final String? series;
  final int durationMinutes;
  final int performerCount;

  final _actressUri = Uri.parse('https://example.test/talents/test');
  final _workUri = Uri.parse('https://example.test/works/abc-123');

  @override
  Future<List<ScrapeActressSearchResult>> searchActresses(String name) async {
    return [
      ScrapeActressSearchResult(source: id, name: name, uri: _actressUri),
    ];
  }

  @override
  Future<ScrapeActressPage> fetchActressPage(
    ScrapeActressSearchResult actress,
  ) async {
    return ScrapeActressPage(
      source: id,
      details: const ScrapedActressDetails(name: '測試女優'),
      works: [
        ScrapeWorkSummary(
          source: id,
          code: 'ABC-123',
          title: title,
          detailUri: _workUri,
          releaseDate: '2026-08-20',
        ),
      ],
    );
  }

  @override
  Future<List<ScrapeWorkSummary>> fetchActressWorks(
    ScrapeActressSearchResult actress, {
    required ScrapeActressPage firstPage,
    bool Function()? isCancelled,
  }) async {
    return firstPage.works;
  }

  @override
  Future<ScrapeWorkDetails> fetchWorkDetails(ScrapeWorkSummary work) async {
    return ScrapeWorkDetails(
      source: id,
      code: id == ScrapeSourceId.avbase ? 'abc-123' : 'ABC-123',
      title: title,
      releaseDate: id == ScrapeSourceId.javbus ? '2026-08-20' : null,
      durationMinutes: durationMinutes,
      studio: studio,
      series: series,
      performerCount: performerCount,
    );
  }

  @override
  bool acceptsImageUri(Uri uri) => false;

  @override
  void close() {}
}

final class _FakeWorkImageDownloader extends WorkImageDownloader {
  _FakeWorkImageDownloader() : super(transport: _NoBinaryTransport());

  @override
  Future<DownloadedWorkImage> downloadToFile({
    required String code,
    String? studio,
    String? publisher,
    List<Uri> originalImageEvidenceUris = const [],
    WorkImageRouteResolution? route,
    required WorkImageVariant variant,
    required String targetPath,
  }) async {
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    return DownloadedWorkImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      sourceUri: Uri.parse('https://example.test/$code.jpg'),
    );
  }
}

final class _NoBinaryTransport implements BinaryTransport {
  @override
  Future<BinaryResponse> get(Uri uri) =>
      throw StateError('Unexpected binary request: $uri');
}
