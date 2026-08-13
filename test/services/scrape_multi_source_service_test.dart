import 'dart:io';
import 'dart:typed_data';

import 'package:avaca/core/database.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/models/scraped_actress_details.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:avaca/services/javbus/work_image_downloader.dart';
import 'package:avaca/services/javbus/work_image_policy.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/services/scrape/scrape_source.dart';
import 'package:avaca/services/scrape/work_code_canonicalizer.dart';
import 'package:avaca/services/works_scrape_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'aggregate mode merges by canonical code and keeps source failures partial',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_multi_source_service_test_',
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
      await database.addActress(name: '小湊よつ葉');
      final actressId =
          (await (await database.database).query('actresses')).single['id']
              as int;

      final minnano = _FakeScrapeSource(
        id: ScrapeSourceId.minnanoAv,
        detailBirthDate: '1996-05-29',
        works: [
          ScrapeWorkSummary(
            source: ScrapeSourceId.minnanoAv,
            code: 'start－489',
            title: 'Minnano title',
            detailUri: Uri.parse('https://www.minnano-av.com/av489.html'),
          ),
          ScrapeWorkSummary(
            source: ScrapeSourceId.minnanoAv,
            code: 'M-002',
            title: 'Minnano only',
            detailUri: Uri.parse('https://www.minnano-av.com/av2.html'),
          ),
        ],
        detailsByCode: {
          'START-489': const ScrapeWorkDetails(
            source: ScrapeSourceId.minnanoAv,
            code: 'START-489',
            title: 'Minnano title',
            studio: 'Minnano studio',
            performerCount: 1,
          ),
          'M-002': const ScrapeWorkDetails(
            source: ScrapeSourceId.minnanoAv,
            code: 'M-002',
            title: 'Minnano only',
            performerCount: 1,
          ),
        },
      );
      final javbus = _FakeScrapeSource(
        id: ScrapeSourceId.javbus,
        detailBirthDate: '1900-01-01',
        works: [
          ScrapeWorkSummary(
            source: ScrapeSourceId.javbus,
            code: 'START-489',
            title: 'JavBus title',
            detailUri: Uri.parse('https://www.javbus.com/START-489'),
          ),
          ScrapeWorkSummary(
            source: ScrapeSourceId.javbus,
            code: 'J-003',
            title: 'JavBus only',
            detailUri: Uri.parse('https://www.javbus.com/J-003'),
          ),
          ScrapeWorkSummary(
            source: ScrapeSourceId.javbus,
            code: 'BAD-004',
            title: 'Broken',
            detailUri: Uri.parse('https://www.javbus.com/BAD-004'),
          ),
        ],
        detailsByCode: {
          'START-489': const ScrapeWorkDetails(
            source: ScrapeSourceId.javbus,
            code: 'START-489',
            title: 'JavBus title',
            durationMinutes: 120,
            performerCount: 2,
          ),
          'J-003': const ScrapeWorkDetails(
            source: ScrapeSourceId.javbus,
            code: 'J-003',
            title: 'JavBus only',
            performerCount: 1,
          ),
        },
        failingCodes: {'BAD-004'},
      );
      final service = WorksScrapeService(
        db: database,
        sources: {
          ScrapeSourceId.minnanoAv: minnano,
          ScrapeSourceId.javbus: javbus,
        },
        workImageDownloader: _FakeWorkImageDownloader(),
        imageDirectory: directory.path,
      );

      final result = await service.scrape(
        actressId: actressId,
        actressName: '小湊よつ葉',
        options: const WorkScrapeOptions(),
        sourceSettings: const ScrapeSourceSettings(),
      );

      final works = await database.getWorksForActress(actressId);
      expect(result.saved, 3);
      expect(result.failed, 1);
      expect(result.partialSuccess, isTrue);
      expect(
        result.sourceResults.keys,
        containsAll([ScrapeSourceId.minnanoAv, ScrapeSourceId.javbus]),
      );
      expect(
        works.map((row) => row['code']),
        unorderedEquals(['START-489', 'M-002', 'J-003']),
      );
      final merged = works.firstWhere((row) => row['code'] == 'START-489');
      expect(merged['studio'], 'Minnano studio');
      expect(merged['duration_minutes'], 120);
      expect(
        (await database.getActressById(actressId))?['birth_date'],
        '1996-05-29',
      );

      minnano.detailRequests.clear();
      javbus.detailRequests.clear();
      await service.scrape(
        actressId: actressId,
        actressName: '小湊よつ葉',
        options: const WorkScrapeOptions(),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.minnanoAv,
          worksSource: WorksSourceSelection.javbus,
        ),
      );
      expect(minnano.detailRequests, isEmpty);
      expect(javbus.detailRequests, isNotEmpty);
    },
  );

  test(
    'aggregate mode rejects details whose canonical code differs from summary',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_multi_source_code_guard_test_',
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
      await database.addActress(name: '河北彩花');
      final actressId =
          (await (await database.database).query('actresses')).single['id']
              as int;

      final summary = ScrapeWorkSummary(
        source: ScrapeSourceId.minnanoAv,
        code: 'start－489',
        title: 'Summary title',
        detailUri: Uri.parse('https://www.minnano-av.com/av489.html'),
      );
      final minnano = _FakeScrapeSource(
        id: ScrapeSourceId.minnanoAv,
        detailBirthDate: '1999-01-01',
        works: [summary],
        detailsByCode: {
          'START-489': const ScrapeWorkDetails(
            source: ScrapeSourceId.minnanoAv,
            code: 'OTHER-999',
            title: 'Wrong detail title',
            studio: 'Wrong studio must not be merged',
            performerCount: 1,
          ),
        },
      );
      final javbus = _FakeScrapeSource(
        id: ScrapeSourceId.javbus,
        detailBirthDate: '1999-01-01',
        works: [
          ScrapeWorkSummary(
            source: ScrapeSourceId.javbus,
            code: 'START-489',
            title: summary.title,
            detailUri: Uri.parse('https://www.javbus.com/START-489'),
          ),
        ],
        detailsByCode: {
          'START-489': const ScrapeWorkDetails(
            source: ScrapeSourceId.javbus,
            code: 'START-489',
            title: 'Verified detail title',
            durationMinutes: 90,
            performerCount: 1,
          ),
        },
      );
      final service = WorksScrapeService(
        db: database,
        sources: {
          ScrapeSourceId.minnanoAv: minnano,
          ScrapeSourceId.javbus: javbus,
        },
        workImageDownloader: _FakeWorkImageDownloader(),
        imageDirectory: directory.path,
      );

      final result = await service.scrape(
        actressId: actressId,
        actressName: '河北彩花',
        options: const WorkScrapeOptions(),
        sourceSettings: const ScrapeSourceSettings(),
      );

      final works = await database.getWorksForActress(actressId);
      expect(result.saved, 1);
      expect(result.failed, 0);
      expect(result.partialSuccess, isTrue);
      expect(works, hasLength(1));
      expect(works.single['code'], 'START-489');
      expect(works.single['studio'], isNot('Wrong studio must not be merged'));
      expect(works.single['duration_minutes'], 90);
    },
  );

  test('details-only source cannot mask a failed works source', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca_multi_source_failure_state_test_',
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
    await database.addActress(name: '河北彩花');
    final actressId =
        (await (await database.database).query('actresses')).single['id']
            as int;

    final minnano = _FakeScrapeSource(
      id: ScrapeSourceId.minnanoAv,
      detailBirthDate: '1999-01-01',
      works: const [],
      detailsByCode: const {},
    );
    final javbus = _FakeScrapeSource(
      id: ScrapeSourceId.javbus,
      detailBirthDate: '1999-01-01',
      works: const [],
      detailsByCode: const {},
      failWorks: true,
    );
    final service = WorksScrapeService(
      db: database,
      sources: {
        ScrapeSourceId.minnanoAv: minnano,
        ScrapeSourceId.javbus: javbus,
      },
      workImageDownloader: _FakeWorkImageDownloader(),
      imageDirectory: directory.path,
    );

    expect(
      () => service.scrape(
        actressId: actressId,
        actressName: '河北彩花',
        options: const WorkScrapeOptions(),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.minnanoAv,
          worksSource: WorksSourceSelection.javbus,
        ),
      ),
      throwsA(isA<WorksScrapeException>()),
    );
  });
}

final class _FakeScrapeSource implements ScrapeSource {
  _FakeScrapeSource({
    required this.id,
    required this.detailBirthDate,
    required this.works,
    required this.detailsByCode,
    this.failingCodes = const {},
    this.failWorks = false,
  });

  @override
  final ScrapeSourceId id;
  final String detailBirthDate;
  final List<ScrapeWorkSummary> works;
  final Map<String, ScrapeWorkDetails> detailsByCode;
  final Set<String> failingCodes;
  final bool failWorks;
  final detailRequests = <String>[];

  @override
  Future<List<ScrapeActressSearchResult>> searchActresses(String name) async {
    return [
      ScrapeActressSearchResult(
        source: id,
        name: name,
        uri: Uri.parse(
          id == ScrapeSourceId.minnanoAv
              ? 'https://www.minnano-av.com/actress618082.html'
              : 'https://www.javbus.com/star/618082',
        ),
      ),
    ];
  }

  @override
  Future<ScrapeActressPage> fetchActressPage(
    ScrapeActressSearchResult actress,
  ) async {
    return ScrapeActressPage(
      source: id,
      details: ScrapedActressDetails(name: '小湊よつ葉', birthDate: detailBirthDate),
      works: works,
    );
  }

  @override
  Future<List<ScrapeWorkSummary>> fetchActressWorks(
    ScrapeActressSearchResult actress, {
    required ScrapeActressPage firstPage,
    bool Function()? isCancelled,
  }) async {
    if (failWorks) {
      throw StateError('simulated works traversal failure');
    }
    return firstPage.works;
  }

  @override
  Future<ScrapeWorkDetails> fetchWorkDetails(ScrapeWorkSummary work) async {
    final code = canonicalizeWorkCode(work.code) ?? '';
    detailRequests.add(code);
    if (failingCodes.contains(code)) {
      throw StateError('simulated failure');
    }
    return detailsByCode[code]!;
  }

  @override
  bool acceptsImageUri(Uri uri) =>
      uri.host == 'www.minnano-av.com' || uri.host == 'www.javbus.com';

  @override
  void close() {}
}

final class _FakeWorkImageDownloader extends WorkImageDownloader {
  _FakeWorkImageDownloader() : super(transport: _NoBinaryTransport());

  @override
  Future<DownloadedWorkImage> downloadToFile({
    required String code,
    String? studio,
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
      throw StateError('unexpected binary request: $uri');
}
