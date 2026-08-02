import 'dart:io';
import 'dart:typed_data';

import 'package:avaca/core/database.dart';
import 'package:avaca/models/scraped_actress_details.dart';
import 'package:avaca/models/work.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:avaca/services/javbus/javbus_client.dart';
import 'package:avaca/services/javbus/javbus_models.dart';
import 'package:avaca/services/javbus/prefix_exclusion.dart';
import 'package:avaca/services/javbus/work_image_downloader.dart';
import 'package:avaca/services/javbus/work_image_policy.dart';
import 'package:avaca/services/works_scrape_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'scrapes exact actress, excludes complex prefixes, and saves images',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_scrape_service_test_',
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
      await database.addActress(name: '涼森れむ');
      final sqlite = await database.database;
      final actressId = (await sqlite.query('actresses')).single['id'] as int;
      final oldAvatar = File(
        '${directory.path}${Platform.pathSeparator}actresses'
        '${Platform.pathSeparator}actress_${actressId}_old.jpg',
      );
      await oldAvatar.parent.create(recursive: true);
      await oldAvatar.writeAsBytes([9]);
      await sqlite.update(
        'actresses',
        {'img_path': oldAvatar.path},
        where: 'id = ?',
        whereArgs: [actressId],
      );
      final client = _FakeJavBusClient();
      final workImages = _FakeWorkImageDownloader();
      final actressImages = _FakeActressImageDownloader();
      final service = WorksScrapeService(
        db: database,
        client: client,
        workImageDownloader: workImages,
        actressImageDownloader: actressImages,
        imageDirectory: directory.path,
      );

      final result = await service.scrape(
        actressId: actressId,
        actressName: '涼森れむ',
        options: const WorkScrapeOptions(
          replaceActressImage: true,
          excludedPrefixes: ['fc2-ppv_123'],
        ),
      );

      expect(client.receivedExclusions, isEmpty);
      expect(client.detailRequests, ['ABF-367']);
      expect(await database.getWorkCountForActress(actressId), 1);
      final works = await database.getWorksForActress(actressId);
      expect(works.single['code'], 'ABF-367');
      expect(works.single['studio'], 'プレステージ');
      expect(
        File(works.single['card_image_path']! as String).existsSync(),
        isTrue,
      );
      expect(
        File(works.single['detail_image_path']! as String).existsSync(),
        isTrue,
      );
      expect(
        (await database.getActressById(actressId))?['img_path'],
        isNotEmpty,
      );
      expect(oldAvatar.existsSync(), isFalse);
      expect(result.saved, 1);
      expect(result.excluded, 1);
    },
  );

  test('missing-only mode keeps existing downloaded image files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca_scrape_missing_only_test_',
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
    await database.addActress(name: '涼森れむ');
    final sqlite = await database.database;
    final actressId = (await sqlite.query('actresses')).single['id'] as int;
    final card = File('${directory.path}/existing-card.jpg');
    final detail = File('${directory.path}/existing-detail.jpg');
    await card.writeAsBytes([7]);
    await detail.writeAsBytes([8]);
    await database.upsertActressWork(
      actressId: actressId,
      work: Work(
        code: 'ABF-367',
        title: '已儲存標題',
        cardImagePath: card.path,
        detailImagePath: detail.path,
      ),
    );
    final workImages = _FakeWorkImageDownloader();
    final service = WorksScrapeService(
      db: database,
      client: _FakeJavBusClient(),
      workImageDownloader: workImages,
      actressImageDownloader: _FakeActressImageDownloader(),
      imageDirectory: directory.path,
    );

    await service.scrape(
      actressId: actressId,
      actressName: '涼森れむ',
      options: const WorkScrapeOptions(
        syncDetails: false,
        fillMissingOnly: true,
        excludedPrefixes: ['FC2-PPV_123'],
      ),
    );

    expect(workImages.downloads, isEmpty);
    expect(await card.readAsBytes(), [7]);
    expect(await detail.readAsBytes(), [8]);
    final work = (await database.getWorksForActress(actressId)).single;
    expect(work['title'], '已儲存標題');
    expect(work['duration_minutes'], 135);
  });

  test(
    'does not scrape a different actress when no exact name matches',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_scrape_exact_name_test_',
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

      final service = WorksScrapeService(
        db: database,
        client: _NoExactMatchJavBusClient(),
        imageDirectory: directory.path,
      );

      await expectLater(
        service.scrape(
          actressId: 1,
          actressName: '涼森れむ',
          options: const WorkScrapeOptions(),
        ),
        throwsA(isA<WorksScrapeException>()),
      );
    },
  );
}

class _NeverTransport implements JavBusTransport {
  @override
  Future<String> get(Uri uri) {
    throw StateError('Unexpected live request: $uri');
  }
}

class _FakeJavBusClient extends JavBusClient {
  _FakeJavBusClient() : super(transport: _NeverTransport());

  List<String> receivedExclusions = [];
  List<String> detailRequests = [];

  @override
  Future<List<JavBusActressSearchResult>> searchActresses(String name) async {
    return [
      JavBusActressSearchResult(
        name: '涼森れむ',
        uri: Uri.parse('https://www.javbus.com/star/uly'),
      ),
    ];
  }

  @override
  Future<JavBusActressPage> fetchActressPage(Uri uri) async {
    return JavBusActressPage(
      details: ScrapedActressDetails(
        name: '涼森れむ',
        avatarUrl: Uri.parse('https://example.test/remu.jpg'),
        birthDate: '1997-12-03',
        height: '160',
        cup: 'F',
        bust: '87',
        waist: '58',
        hip: '85',
      ),
      works: const [],
      pageCount: 1,
    );
  }

  @override
  Future<List<JavBusWorkSummary>> fetchAllActressWorks(
    Uri actressUri, {
    PrefixExclusion? exclusions,
    bool Function()? isCancelled,
  }) async {
    receivedExclusions = exclusions?.values ?? [];
    return [
      JavBusWorkSummary(
        code: 'ABF-367',
        title: '新標題',
        releaseDate: '2026-07-17',
        detailUri: Uri.parse('https://www.javbus.com/ABF-367'),
      ),
      JavBusWorkSummary(
        code: 'FC2-PPV_123-999',
        title: '排除作品',
        detailUri: Uri.parse('https://www.javbus.com/FC2-PPV_123-999'),
      ),
    ];
  }

  @override
  Future<JavBusWorkDetails> fetchWorkDetails(Uri uri) async {
    final code = uri.pathSegments.last;
    detailRequests.add(code);
    return JavBusWorkDetails(
      code: code,
      title: '新標題',
      releaseDate: '2026-07-17',
      durationMinutes: 135,
      studio: 'プレステージ',
      publisher: 'ABSOLUTELYFANTASIA',
      series: '系列',
    );
  }
}

class _NoExactMatchJavBusClient extends _FakeJavBusClient {
  @override
  Future<List<JavBusActressSearchResult>> searchActresses(String name) async {
    return [
      JavBusActressSearchResult(
        name: '別の女優',
        uri: Uri.parse('https://www.javbus.com/star/not-remu'),
      ),
    ];
  }

  @override
  Future<JavBusActressPage> fetchActressPage(Uri uri) {
    throw StateError('A non-exact actress must never be scraped.');
  }
}

class _NoBinaryTransport implements BinaryTransport {
  @override
  Future<BinaryResponse> get(Uri uri) {
    throw StateError('Unexpected binary request: $uri');
  }
}

class _FakeWorkImageDownloader extends WorkImageDownloader {
  _FakeWorkImageDownloader() : super(transport: _NoBinaryTransport());

  final downloads = <WorkImageVariant>[];

  @override
  Future<DownloadedWorkImage> downloadToFile({
    required String code,
    String? studio,
    required WorkImageVariant variant,
    required String targetPath,
  }) async {
    downloads.add(variant);
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    return DownloadedWorkImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      sourceUri: Uri.parse('https://example.test/$code.jpg'),
    );
  }
}

class _FakeActressImageDownloader implements ActressImageDownloader {
  @override
  Future<String> download(Uri uri, String targetPath) async {
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([4, 5, 6]);
    return file.path;
  }
}
