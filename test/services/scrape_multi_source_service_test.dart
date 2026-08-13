import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:avaca/core/database.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/models/scraped_actress_details.dart';
import 'package:avaca/models/work.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:avaca/services/javbus/work_image_downloader.dart';
import 'package:avaca/services/javbus/work_image_policy.dart';
import 'package:avaca/services/scrape/scrape_image_downloader.dart';
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

  test(
    'deduplicates equivalent START aliases without merging different numbers',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_start_alias_dedup_test_',
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
      await database.upsertActressWork(
        actressId: actressId,
        work: const Work(code: '1START00408', title: 'legacy alias'),
      );
      await database.upsertActressWork(
        actressId: actressId,
        work: const Work(code: 'START-408', title: 'legacy canonical'),
      );

      final source = _FakeScrapeSource(
        id: ScrapeSourceId.minnanoAv,
        detailBirthDate: '1996-05-29',
        works: [
          ScrapeWorkSummary(
            source: ScrapeSourceId.minnanoAv,
            code: '1start00408',
            title: 'START 408 alias',
            detailUri: Uri.parse('https://www.minnano-av.com/av408-a.html'),
          ),
          ScrapeWorkSummary(
            source: ScrapeSourceId.minnanoAv,
            code: 'START-408',
            title: 'START 408 canonical',
            detailUri: Uri.parse('https://www.minnano-av.com/av408-b.html'),
          ),
          ScrapeWorkSummary(
            source: ScrapeSourceId.minnanoAv,
            code: '1start00427',
            title: 'START 427 alias',
            detailUri: Uri.parse('https://www.minnano-av.com/av427-a.html'),
          ),
          ScrapeWorkSummary(
            source: ScrapeSourceId.minnanoAv,
            code: 'START-427',
            title: 'START 427 canonical',
            detailUri: Uri.parse('https://www.minnano-av.com/av427-b.html'),
          ),
        ],
        detailsByCode: {
          'START-408': ScrapeWorkDetails(
            source: ScrapeSourceId.minnanoAv,
            code: '1start00408',
            title: 'START 408',
            performerCount: 1,
            imageUris: [
              Uri.parse('https://www.minnano-av.com/p_package/2605/195939.jpg'),
            ],
          ),
          'START-427': const ScrapeWorkDetails(
            source: ScrapeSourceId.minnanoAv,
            code: 'START-427',
            title: 'START 427',
            performerCount: 1,
          ),
        },
      );
      final uriDownloader = _RecordingScrapeImageUriDownloader();
      final service = WorksScrapeService(
        db: database,
        sources: {ScrapeSourceId.minnanoAv: source},
        workImageDownloader: _FakeWorkImageDownloader(),
        imageUriDownloader: uriDownloader,
        imageDirectory: directory.path,
      );

      final result = await service.scrape(
        actressId: actressId,
        actressName: '小湊よつ葉',
        options: const WorkScrapeOptions(),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.minnanoAv,
          worksSource: WorksSourceSelection.minnanoAv,
        ),
      );

      final works = await database.getWorksForActress(actressId);
      expect(result.saved, 2);
      expect(works, hasLength(2));
      expect(
        works.map((row) => row['code']),
        unorderedEquals(['START-408', 'START-427']),
      );
      expect(works.where((row) => row['code'] == '1START00408'), isEmpty);
      expect(source.detailRequests, ['START-408', 'START-427']);
      expect(uriDownloader.requested, isEmpty);
    },
  );

  test(
    'starts all source pipelines and detail queues concurrently while each source stays sequential',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_multi_source_overlap_test_',
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

      final minnanoCollectionStarted = Completer<void>();
      final releaseMinnanoCollection = Completer<void>();
      final javbusCollectionStarted = Completer<void>();
      final minnanoDetailStarted = Completer<void>();
      final releaseMinnanoDetail = Completer<void>();
      final javbusDetailStarted = Completer<void>();
      final releaseJavbusDetail = Completer<void>();

      final minnano = _FakeScrapeSource(
        id: ScrapeSourceId.minnanoAv,
        detailBirthDate: '1996-05-29',
        beforeSearch: () async {
          if (!minnanoCollectionStarted.isCompleted) {
            minnanoCollectionStarted.complete();
          }
          await releaseMinnanoCollection.future;
        },
        beforeDetail: (code) async {
          if (code == 'M-001') {
            if (!minnanoDetailStarted.isCompleted) {
              minnanoDetailStarted.complete();
            }
            await releaseMinnanoDetail.future;
          }
        },
        works: [
          ScrapeWorkSummary(
            source: ScrapeSourceId.minnanoAv,
            code: 'M-001',
            title: 'Minnano 1',
            detailUri: Uri.parse('https://www.minnano-av.com/m1.html'),
          ),
          ScrapeWorkSummary(
            source: ScrapeSourceId.minnanoAv,
            code: 'M-002',
            title: 'Minnano 2',
            detailUri: Uri.parse('https://www.minnano-av.com/m2.html'),
          ),
        ],
        detailsByCode: {
          'M-001': const ScrapeWorkDetails(
            source: ScrapeSourceId.minnanoAv,
            code: 'M-001',
            title: 'Minnano 1',
            performerCount: 1,
          ),
          'M-002': const ScrapeWorkDetails(
            source: ScrapeSourceId.minnanoAv,
            code: 'M-002',
            title: 'Minnano 2',
            performerCount: 1,
          ),
        },
      );
      final javbus = _FakeScrapeSource(
        id: ScrapeSourceId.javbus,
        detailBirthDate: '1996-05-29',
        beforeSearch: () async {
          if (!javbusCollectionStarted.isCompleted) {
            javbusCollectionStarted.complete();
          }
        },
        beforeDetail: (code) async {
          if (code == 'J-001') {
            if (!javbusDetailStarted.isCompleted) {
              javbusDetailStarted.complete();
            }
            await releaseJavbusDetail.future;
          }
        },
        works: [
          ScrapeWorkSummary(
            source: ScrapeSourceId.javbus,
            code: 'J-001',
            title: 'JavBus 1',
            detailUri: Uri.parse('https://www.javbus.com/J-001'),
          ),
          ScrapeWorkSummary(
            source: ScrapeSourceId.javbus,
            code: 'J-002',
            title: 'JavBus 2',
            detailUri: Uri.parse('https://www.javbus.com/J-002'),
          ),
        ],
        detailsByCode: {
          'J-001': const ScrapeWorkDetails(
            source: ScrapeSourceId.javbus,
            code: 'J-001',
            title: 'JavBus 1',
            performerCount: 1,
          ),
          'J-002': const ScrapeWorkDetails(
            source: ScrapeSourceId.javbus,
            code: 'J-002',
            title: 'JavBus 2',
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

      final scrape = service.scrape(
        actressId: actressId,
        actressName: '小湊よつ葉',
        options: const WorkScrapeOptions(syncDetails: false),
        sourceSettings: const ScrapeSourceSettings(),
      );

      await minnanoCollectionStarted.future;
      await javbusCollectionStarted.future;
      expect(minnanoCollectionStarted.isCompleted, isTrue);
      expect(javbusCollectionStarted.isCompleted, isTrue);
      releaseMinnanoCollection.complete();

      await minnanoDetailStarted.future;
      await javbusDetailStarted.future;
      expect(minnano.detailRequests, ['M-001']);
      expect(javbus.detailRequests, ['J-001']);
      releaseMinnanoDetail.complete();
      releaseJavbusDetail.complete();

      final result = await scrape;
      expect(result.saved, 4);
      expect(minnano.detailRequests, ['M-001', 'M-002']);
      expect(javbus.detailRequests, ['J-001', 'J-002']);
    },
  );

  test('merge priority is independent of source completion order', () async {
    Future<Map<String, Object?>> runScenario({
      required Duration minnanoDelay,
      required Duration javbusDelay,
    }) async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_completion_order_test_',
      );
      final database = AppDatabase.forTesting(
        baseDir: directory.path,
        databaseFactory: databaseFactoryFfi,
      );
      try {
        await database.init();
        await database.addActress(name: '小湊よつ葉');
        final actressId =
            (await (await database.database).query('actresses')).single['id']
                as int;
        final minnano = _FakeScrapeSource(
          id: ScrapeSourceId.minnanoAv,
          detailBirthDate: '1996-05-29',
          beforeDetail: (_) => Future<void>.delayed(minnanoDelay),
          works: [
            ScrapeWorkSummary(
              source: ScrapeSourceId.minnanoAv,
              code: 'START-408',
              title: 'Minnano summary',
              detailUri: Uri.parse('https://www.minnano-av.com/start408.html'),
            ),
          ],
          detailsByCode: {
            'START-408': const ScrapeWorkDetails(
              source: ScrapeSourceId.minnanoAv,
              code: '1start00408',
              title: 'Minnano title',
              studio: 'Minnano studio',
              performerCount: 1,
            ),
          },
        );
        final javbus = _FakeScrapeSource(
          id: ScrapeSourceId.javbus,
          detailBirthDate: '1996-05-29',
          beforeDetail: (_) => Future<void>.delayed(javbusDelay),
          works: [
            ScrapeWorkSummary(
              source: ScrapeSourceId.javbus,
              code: 'start-408',
              title: 'JavBus summary',
              detailUri: Uri.parse('https://www.javbus.com/START-408'),
            ),
          ],
          detailsByCode: {
            'START-408': const ScrapeWorkDetails(
              source: ScrapeSourceId.javbus,
              code: 'START-408',
              title: 'JavBus title',
              durationMinutes: 120,
              performerCount: 2,
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
          actressName: '小湊よつ葉',
          options: const WorkScrapeOptions(syncDetails: false),
          sourceSettings: const ScrapeSourceSettings(),
        );
        expect(result.saved, 1);
        return (await database.getWorksForActress(actressId)).single;
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    }

    final minnanoSlow = await runScenario(
      minnanoDelay: const Duration(milliseconds: 30),
      javbusDelay: Duration.zero,
    );
    final javbusSlow = await runScenario(
      minnanoDelay: Duration.zero,
      javbusDelay: const Duration(milliseconds: 30),
    );

    expect(minnanoSlow['code'], 'START-408');
    expect(javbusSlow['code'], 'START-408');
    expect(minnanoSlow['title'], 'Minnano title');
    expect(javbusSlow['title'], 'Minnano title');
    expect(minnanoSlow['studio'], 'Minnano studio');
    expect(javbusSlow['studio'], 'Minnano studio');
    expect(minnanoSlow['duration_minutes'], 120);
    expect(javbusSlow['duration_minutes'], 120);
  });

  test(
    'cancellation before commit does not persist collected details',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_cancel_before_commit_test_',
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
      final token = WorksScrapeCancellationToken();
      final source = _FakeScrapeSource(
        id: ScrapeSourceId.minnanoAv,
        detailBirthDate: '1996-05-29',
        beforeDetail: (_) async => token.cancel(),
        works: [
          ScrapeWorkSummary(
            source: ScrapeSourceId.minnanoAv,
            code: 'START-408',
            title: 'Cancelled work',
            detailUri: Uri.parse('https://www.minnano-av.com/start408.html'),
          ),
        ],
        detailsByCode: {
          'START-408': const ScrapeWorkDetails(
            source: ScrapeSourceId.minnanoAv,
            code: 'START-408',
            title: 'Cancelled work',
            performerCount: 1,
          ),
        },
      );
      final service = WorksScrapeService(
        db: database,
        sources: {ScrapeSourceId.minnanoAv: source},
        workImageDownloader: _FakeWorkImageDownloader(),
        imageDirectory: directory.path,
      );

      final result = await service.scrape(
        actressId: actressId,
        actressName: '小湊よつ葉',
        options: const WorkScrapeOptions(syncDetails: false),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.minnanoAv,
          worksSource: WorksSourceSelection.minnanoAv,
        ),
        cancellationToken: token,
      );

      expect(result.cancelled, isTrue);
      expect(await database.getWorksForActress(actressId), isEmpty);
    },
  );

  test(
    'cancellation during actress image sync does not persist the image',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_cancel_actress_sync_test_',
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
      final token = WorksScrapeCancellationToken();
      final source = _FakeScrapeSource(
        id: ScrapeSourceId.minnanoAv,
        detailBirthDate: '1996-05-29',
        detailAvatarUrl: Uri.parse(
          'https://www.minnano-av.com/p_actress_125_125/avatar.jpg',
        ),
        works: [
          ScrapeWorkSummary(
            source: ScrapeSourceId.minnanoAv,
            code: 'START-408',
            title: 'Cancelled actress sync',
            detailUri: Uri.parse('https://www.minnano-av.com/start408.html'),
          ),
        ],
        detailsByCode: {
          'START-408': const ScrapeWorkDetails(
            source: ScrapeSourceId.minnanoAv,
            code: 'START-408',
            title: 'Cancelled actress sync',
            performerCount: 1,
          ),
        },
      );
      final service = WorksScrapeService(
        db: database,
        sources: {ScrapeSourceId.minnanoAv: source},
        actressImageDownloader: _CancellingActressImageDownloader(token),
        workImageDownloader: _FakeWorkImageDownloader(),
        imageDirectory: directory.path,
      );

      final result = await service.scrape(
        actressId: actressId,
        actressName: '小湊よつ葉',
        options: const WorkScrapeOptions(replaceActressImage: true),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.minnanoAv,
          worksSource: WorksSourceSelection.minnanoAv,
        ),
        cancellationToken: token,
      );

      expect(result.cancelled, isTrue);
      expect(result.saved, 0);
      expect(await database.getWorksForActress(actressId), isEmpty);
      final actressDirectory = Directory('${directory.path}/actresses');
      final files = actressDirectory.existsSync()
          ? actressDirectory.listSync().whereType<File>()
          : const <File>[];
      expect(files, isEmpty);
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
    this.beforeSearch,
    this.beforeDetail,
    this.detailAvatarUrl,
  });

  @override
  final ScrapeSourceId id;
  final String detailBirthDate;
  final List<ScrapeWorkSummary> works;
  final Map<String, ScrapeWorkDetails> detailsByCode;
  final Set<String> failingCodes;
  final bool failWorks;
  final Future<void> Function()? beforeSearch;
  final Future<void> Function(String code)? beforeDetail;
  final Uri? detailAvatarUrl;
  final detailRequests = <String>[];

  @override
  Future<List<ScrapeActressSearchResult>> searchActresses(String name) async {
    await beforeSearch?.call();
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
      details: ScrapedActressDetails(
        name: '小湊よつ葉',
        birthDate: detailBirthDate,
        avatarUrl: detailAvatarUrl,
      ),
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
    await beforeDetail?.call(code);
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

final class _RecordingScrapeImageUriDownloader
    implements ScrapeImageUriDownloader {
  final requested = <Uri>[];

  @override
  Future<String> download({
    required Uri uri,
    required String targetPath,
  }) async {
    requested.add(uri);
    return targetPath;
  }

  @override
  void close() {}
}

final class _CancellingActressImageDownloader
    implements ActressImageDownloader {
  _CancellingActressImageDownloader(this.token);

  final WorksScrapeCancellationToken token;

  @override
  Future<String> download(Uri uri, String targetPath) async {
    token.cancel();
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    return file.path;
  }
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
