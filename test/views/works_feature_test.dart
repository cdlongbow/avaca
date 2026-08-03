import 'dart:async';

import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:avaca/services/works_scrape_service.dart';
import 'package:avaca/views/detail_view.dart';
import 'package:avaca/views/works_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _WorksFeatureDatabase extends AppDatabase {
  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async {
    return {
      'id': actressId,
      'name': '涼森れむ',
      'img_path': '',
      'main_type': '有碼',
      'memo': '',
      'height': '160',
      'weight': '',
      'bwh': '87-58-85',
      'cup': 'F',
      'birth_date': '1997-12-03',
    };
  }

  @override
  Future<List<Map<String, Object?>>> getWorksForActress(int actressId) async {
    return const [
      {
        'id': 1,
        'code': 'ABF-367',
        'title': '第一部測試作品',
        'release_date': '2026-07-17',
        'duration_minutes': 135,
        'studio': 'プレステージ',
        'publisher': 'ABSOLUTELYFANTASIA',
        'series': '「顔」で、ヌく。',
        'card_image_path': '',
        'detail_image_path': '',
      },
      {
        'id': 2,
        'code': 'SONE-833',
        'title': '第二部測試作品',
        'release_date': '2026-06-20',
        'duration_minutes': 120,
        'studio': '測試製作商',
        'publisher': '測試發行商',
        'series': '',
        'card_image_path': '',
        'detail_image_path': '',
      },
      {
        'id': 3,
        'code': 'START-196',
        'title': '第三部測試作品',
        'release_date': '2026-05-01',
        'duration_minutes': null,
        'studio': '',
        'publisher': '',
        'series': '',
        'card_image_path': '',
        'detail_image_path': '',
      },
    ];
  }

  @override
  Future<Map<String, Object?>?> getWorkById(int workId) async {
    final rows = await getWorksForActress(7);
    for (final row in rows) {
      if (row['id'] == workId) {
        return row;
      }
    }
    return null;
  }

  @override
  Future<int> getWorkCountForActress(int actressId) async => 178;

  @override
  Future<String?> getSetting(String key) async => null;

  @override
  Future<void> setSetting(String key, String value) async {}
}

void main() {
  testWidgets('works page renders a three-column screenshot-style grid', (
    tester,
  ) async {
    await _pumpWorks(tester);

    expect(find.byKey(const Key('work-card-1')), findsOneWidget);
    expect(find.byKey(const Key('work-card-2')), findsOneWidget);
    expect(find.byKey(const Key('work-card-3')), findsOneWidget);
    expect(find.text('第一部測試作品'), findsOneWidget);
    expect(find.text('ABF-367'), findsOneWidget);
    expect(find.text('2026-07-17'), findsOneWidget);

    final first = tester.getRect(find.byKey(const Key('work-card-1')));
    final second = tester.getRect(find.byKey(const Key('work-card-2')));
    final third = tester.getRect(find.byKey(const Key('work-card-3')));
    expect(first.top, closeTo(second.top, 0.01));
    expect(second.top, closeTo(third.top, 0.01));
    expect(first.right, lessThan(second.left));
    expect(second.right, lessThan(third.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrape action opens settings and accepts complex prefixes', (
    tester,
  ) async {
    await _pumpWorks(tester);

    await tester.tap(find.byKey(const Key('works-scrape-action')));
    await tester.pumpAndSettle();

    expect(find.text('同步詳細資料'), findsOneWidget);
    expect(find.text('更換女優頭像'), findsOneWidget);
    expect(find.text('二次刮削只補齊缺少的資訊'), findsOneWidget);
    expect(find.text('多於此數量的女優不刮削'), findsOneWidget);
    expect(
      find.byKey(const Key('scrape-max-actress-count-input')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('scrape-prefix-input')),
      'fc2-ppv_123',
    );
    await tester.tap(find.byKey(const Key('scrape-prefix-add')));
    await tester.pumpAndSettle();

    expect(find.text('FC2-PPV_123'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('starting scrape forwards settings and refreshes the grid', (
    tester,
  ) async {
    WorkScrapeOptions? received;
    await _pumpWorks(
      tester,
      scrapeExecutor: (options, token, onProgress) async {
        received = options;
        onProgress(
          const WorksScrapeProgress(
            current: 1,
            total: 1,
            saved: 1,
            excluded: 0,
            failed: 0,
          ),
        );
        return const WorksScrapeResult(
          saved: 1,
          excluded: 0,
          failed: 0,
          cancelled: false,
        );
      },
    );

    await tester.tap(find.byKey(const Key('works-scrape-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('scrape-prefix-input')),
      '1pon-HD',
    );
    await tester.enterText(
      find.byKey(const Key('scrape-max-actress-count-input')),
      '3',
    );
    await tester.tap(find.byKey(const Key('scrape-prefix-add')));
    await tester.tap(find.text('開始刮削'));
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.excludedPrefixes, ['1PON-HD']);
    expect(received!.syncDetails, isTrue);
    expect(received!.fillMissingOnly, isTrue);
    expect(received!.maxActressCount, 3);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('刮削完成：儲存 1、排除 0、失敗 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actress-count limit rejects zero and keeps settings open', (
    tester,
  ) async {
    await _pumpWorks(tester);

    await tester.tap(find.byKey(const Key('works-scrape-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('scrape-max-actress-count-input')),
      '0',
    );
    await tester.tap(find.text('開始刮削'));
    await tester.pumpAndSettle();

    expect(find.text('請輸入大於等於 1 的整數'), findsOneWidget);
    expect(find.text('刮削設定'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actress-count limit rejects decimal input', (tester) async {
    await _pumpWorks(tester);

    await tester.tap(find.byKey(const Key('works-scrape-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('scrape-max-actress-count-input')),
      '1.5',
    );
    await tester.tap(find.text('開始刮削'));
    await tester.pumpAndSettle();

    expect(find.text('請輸入大於等於 1 的整數'), findsOneWidget);
    expect(find.text('刮削設定'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('avatar failure is visible while the scrape still completes', (
    tester,
  ) async {
    await _pumpWorks(
      tester,
      scrapeExecutor: (options, token, onProgress) async =>
          const WorksScrapeResult(
            saved: 1,
            excluded: 0,
            failed: 0,
            cancelled: false,
            actressImageStatus: ActressImageSyncStatus.downloadFailed,
          ),
    );

    await tester.tap(find.byKey(const Key('works-scrape-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開始刮削'));
    await tester.pumpAndSettle();

    expect(find.textContaining('女優頭像替換失敗，已保留原頭像'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a work opens details with the downloaded large image', (
    tester,
  ) async {
    await _pumpWorks(tester);

    await tester.tap(find.byKey(const Key('work-card-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('work-detail-image')), findsOneWidget);
    expect(find.text('第一部測試作品'), findsOneWidget);
    expect(find.text('135 分鐘'), findsOneWidget);
    expect(find.textContaining('プレステージ'), findsOneWidget);
    expect(find.textContaining('ABSOLUTELYFANTASIA'), findsOneWidget);
    expect(find.textContaining('「顔」で、ヌく。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back cannot dismiss the active scrape dialog', (
    tester,
  ) async {
    final result = Completer<WorksScrapeResult>();
    await _pumpWorks(
      tester,
      scrapeExecutor: (options, token, onProgress) => result.future,
    );

    await tester.tap(find.byKey(const Key('works-scrape-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開始刮削'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(WorksView), findsOneWidget);

    result.complete(
      const WorksScrapeResult(
        saved: 0,
        excluded: 0,
        failed: 0,
        cancelled: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WorksView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'detail page shows the local work count beside a narrower button',
    (tester) async {
      await tester.pumpWidget(
        _localizedApp(
          home: DetailView(db: _WorksFeatureDatabase(), actressId: 7),
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.getRect(
        find.byKey(const Key('detail-works-button')),
      );
      final count = tester.getRect(find.byKey(const Key('detail-works-count')));

      expect(find.text('178'), findsOneWidget);
      expect(button.right, lessThan(count.left));
      expect(button.width, lessThan(120));
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpWorks(
  WidgetTester tester, {
  Future<WorksScrapeResult> Function(
    WorkScrapeOptions options,
    WorksScrapeCancellationToken token,
    void Function(WorksScrapeProgress progress) onProgress,
  )?
  scrapeExecutor,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    _localizedApp(
      home: WorksView(
        db: _WorksFeatureDatabase(),
        actressId: 7,
        scrapeExecutor: scrapeExecutor,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _localizedApp({required Widget home}) {
  return MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}
