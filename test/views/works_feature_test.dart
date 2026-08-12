import 'dart:async';

import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:avaca/services/works_scrape_service.dart';
import 'package:avaca/views/detail_view.dart';
import 'package:avaca/views/works_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      {
        'id': 4,
        'code': 'SONE409',
        'title': '第四部測試作品',
        'release_date': '2026-04-12',
        'duration_minutes': 110,
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

class _WideWorksFeatureDatabase extends _WorksFeatureDatabase {
  @override
  Future<List<Map<String, Object?>>> getWorksForActress(int actressId) async {
    final works = [...await super.getWorksForActress(actressId)];
    for (var id = 5; id <= 12; id++) {
      works.add({
        'id': id,
        'code': 'WIDE-$id',
        'title': '寬螢幕測試作品 $id',
        'release_date': '2026-01-${id.toString().padLeft(2, '0')}',
        'duration_minutes': 120,
        'studio': '測試製作商',
        'publisher': '測試發行商',
        'series': '',
        'card_image_path': '',
        'detail_image_path': '',
      });
    }
    return works;
  }
}

class _DeletingWorksFeatureDatabase extends _WorksFeatureDatabase {
  final deletedWorkIds = <int>[];

  @override
  Future<List<Map<String, Object?>>> getWorksForActress(int actressId) async {
    final works = await super.getWorksForActress(actressId);
    return works
        .where((work) => !deletedWorkIds.contains(work['id']))
        .toList(growable: false);
  }

  @override
  Future<WorkDeletionReport> deleteWorksWithReport(
    Iterable<int> workIds,
  ) async {
    final requested = workIds.toList(growable: false);
    deletedWorkIds.addAll(requested);
    return WorkDeletionReport(
      databaseCommitted: true,
      requestedWorkIds: requested,
      deletedWorkIds: requested,
      deletedWorkRows: requested.length,
      deletedActressWorkRows: requested.length,
      fileCleanup: const ManagedFileCleanupReport(),
      cacheEvictionPaths: const [],
      pendingFileDeletionsBefore: const [],
      pendingFileDeletionsAfter: const [],
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  testWidgets('works overflow menu contains search and scrape actions', (
    tester,
  ) async {
    await _pumpWorks(tester);

    expect(find.byKey(const Key('works-overflow-menu')), findsOneWidget);
    expect(find.byKey(const Key('works-scrape-action')), findsNothing);

    await tester.tap(find.byKey(const Key('works-overflow-menu')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('works-search-menu-item')), findsOneWidget);
    expect(find.byKey(const Key('works-scrape-menu-item')), findsOneWidget);

    await tester.tap(find.byKey(const Key('works-search-menu-item')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('works-search-field')), findsOneWidget);
    expect(find.byKey(const Key('works-search-close')), findsOneWidget);
    expect(find.byKey(const Key('works-search-clear')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('work code search ignores case and separators', (tester) async {
    await _pumpWorks(tester);

    await tester.tap(find.byKey(const Key('works-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('works-search-menu-item')));
    await tester.pumpAndSettle();

    final searchField = find.byKey(const Key('works-search-field'));

    for (final query in ['SONE-409', 'sone-409', 'SONE409', 'sone409']) {
      await tester.enterText(searchField, query);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('work-card-4')), findsOneWidget);
      expect(find.byKey(const Key('work-card-1')), findsNothing);
      expect(find.byKey(const Key('work-card-2')), findsNothing);
      expect(find.byKey(const Key('work-card-3')), findsNothing);
    }

    expect(find.byKey(const Key('works-search-close')), findsOneWidget);
    expect(find.byKey(const Key('works-search-clear')), findsNothing);

    await tester.enterText(searchField, 'not-a-real-code');
    await tester.pumpAndSettle();

    expect(find.text('找不到符合的作品'), findsOneWidget);
    expect(find.byKey(const Key('work-card-4')), findsNothing);

    await tester.enterText(searchField, '中文');
    await tester.pumpAndSettle();

    expect(find.text('找不到符合的作品'), findsOneWidget);
    expect(find.byKey(const Key('work-card-4')), findsNothing);

    await tester.tap(find.byKey(const Key('works-search-close')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('works-search-field')).hitTestable(),
      findsNothing,
    );
    expect(find.byKey(const Key('work-card-1')), findsOneWidget);
    expect(find.byKey(const Key('work-card-4')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back closes work search before leaving the page', (
    tester,
  ) async {
    await _pumpWorks(tester);

    await tester.tap(find.byKey(const Key('works-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('works-search-menu-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('works-search-field')),
      'SONE409',
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(WorksView), findsOneWidget);
    expect(
      find.byKey(const Key('works-search-field')).hitTestable(),
      findsNothing,
    );
    expect(find.byKey(const Key('work-card-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large works page size keeps two cards in the first row', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'works_page_size': 'large'});
    await _pumpWorks(tester);

    final first = tester.getRect(find.byKey(const Key('work-card-1')));
    final second = tester.getRect(find.byKey(const Key('work-card-2')));
    final third = tester.getRect(find.byKey(const Key('work-card-3')));
    expect(first.top, closeTo(second.top, 0.01));
    expect(third.top, greaterThan(second.top));
  });

  testWidgets('small works cards stay safe under narrow text scaling', (
    tester,
  ) async {
    await _pumpWorks(
      tester,
      size: const Size(320, 480),
      textScaler: const TextScaler.linear(1.25),
    );

    expect(find.byKey(const Key('work-card-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small works cards shrink in the expanded landscape layout', (
    tester,
  ) async {
    await _pumpWorks(tester, size: const Size(1440, 900));
    final smallWidth = tester
        .getRect(find.byKey(const Key('work-card-1')))
        .width;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    SharedPreferences.setMockInitialValues({'works_page_size': 'large'});
    await _pumpWorks(tester, size: const Size(1440, 900));
    final largeWidth = tester
        .getRect(find.byKey(const Key('work-card-1')))
        .width;

    expect(smallWidth, lessThan(largeWidth));
    expect(smallWidth, lessThanOrEqualTo(192));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide Works grid uses remaining width beyond the old cap', (
    tester,
  ) async {
    final database = _WideWorksFeatureDatabase();

    await _pumpWorks(tester, database: database, size: const Size(1440, 900));

    final smallFirst = tester.getRect(find.byKey(const Key('work-card-1')));
    final smallSeventh = tester.getRect(find.byKey(const Key('work-card-7')));
    final smallGrid = tester.getRect(find.byType(GridView).first);

    expect(smallSeventh.top, closeTo(smallFirst.top, 0.01));
    expect(smallGrid.width, greaterThan(1300));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    SharedPreferences.setMockInitialValues({'works_page_size': 'large'});
    await _pumpWorks(tester, database: database, size: const Size(1440, 900));

    final largeFirst = tester.getRect(find.byKey(const Key('work-card-1')));
    final largeFifth = tester.getRect(find.byKey(const Key('work-card-5')));
    final largeGrid = tester.getRect(find.byType(GridView).first);

    expect(largeFifth.top, closeTo(largeFirst.top, 0.01));
    expect(largeGrid.width, closeTo(smallGrid.width, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long press enters multi-select and tap toggles work cards', (
    tester,
  ) async {
    await _pumpWorks(tester);

    await tester.longPress(find.byKey(const Key('work-card-1')));

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('work-card-selected-1')), findsOneWidget);

    expect(find.byKey(const Key('works-delete-action')), findsOneWidget);

    await tester.tap(find.byKey(const Key('work-card-2')));

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('work-card-selected-1')), findsOneWidget);

    expect(find.byKey(const Key('work-card-selected-2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('work-card-1')));

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('work-card-selected-1')), findsNothing);

    expect(find.byKey(const Key('work-card-selected-2')), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'system back clears work selection and delete confirms global removal',

    (tester) async {
      await _pumpWorks(tester);

      await tester.longPress(find.byKey(const Key('work-card-1')));

      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();

      await tester.pumpAndSettle();

      expect(find.byType(WorksView), findsOneWidget);

      expect(find.byKey(const Key('work-card-selected-1')), findsNothing);

      expect(find.byKey(const Key('works-delete-action')), findsNothing);

      await tester.longPress(find.byKey(const Key('work-card-1')));

      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('works-delete-action')));

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('works-delete-confirm')), findsOneWidget);

      expect(find.textContaining('其他女優'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('confirming selected work deletion reloads and exits selection', (
    tester,
  ) async {
    final database = _DeletingWorksFeatureDatabase();

    await _pumpWorks(tester, database: database);

    await tester.longPress(find.byKey(const Key('work-card-1')));

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('works-delete-action')));

    await tester.pumpAndSettle();

    await tester.tap(find.text('確定刪除'));

    await tester.pumpAndSettle();

    expect(database.deletedWorkIds, [1]);

    expect(find.byKey(const Key('work-card-1')), findsNothing);

    expect(find.byKey(const Key('work-card-2')), findsOneWidget);

    expect(find.byKey(const Key('works-delete-action')), findsNothing);

    expect(find.byKey(const Key('works-overflow-menu')), findsOneWidget);

    expect(find.text('已刪除 1 部作品'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scrape settings use compact switch rows and collapsible prefixes',

    (tester) async {
      await _pumpWorks(tester);

      await _openWorksScrapeSettings(tester);

      final switchTiles = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList(growable: false);

      expect(switchTiles, hasLength(3));

      for (final tile in switchTiles) {
        expect(tile.controlAffinity, ListTileControlAffinity.trailing);
      }

      expect(find.text('同步詳細資料'), findsOneWidget);

      expect(find.text('更換女優頭像'), findsOneWidget);

      expect(find.text('二次刮削只補齊缺少的資訊'), findsOneWidget);

      expect(find.text('多於此數量的女優不刮削'), findsOneWidget);

      expect(
        find.byKey(const Key('scrape-max-actress-count-row')),

        findsOneWidget,
      );

      expect(
        find.byKey(const Key('scrape-max-actress-count-input')),

        findsOneWidget,
      );

      final maxCountFinder = find.byKey(
        const Key('scrape-max-actress-count-input'),
      );

      final maxCountEditable = tester.widget<EditableText>(
        find.descendant(
          of: maxCountFinder,

          matching: find.byType(EditableText),
        ),
      );

      expect(maxCountEditable.textAlign, TextAlign.center);
      expect(maxCountEditable.controller.text, '0');

      final inputDecorator = tester.widget<InputDecorator>(
        find.descendant(
          of: maxCountFinder,
          matching: find.byType(InputDecorator),
        ),
      );
      expect(inputDecorator.decoration.border, isA<UnderlineInputBorder>());
      expect(tester.getRect(maxCountFinder).width, closeTo(48, 0.01));

      final rowTextStyle = Theme.of(
        tester.element(find.text('多於此數量的女優不刮削')),
      ).textTheme.bodyMedium;
      expect(maxCountEditable.style.fontSize, rowTextStyle?.fontSize);

      final maxLabelRenderObject = tester.renderObject<RenderParagraph>(
        find.text('多於此數量的女優不刮削'),
      );
      final syncLabelRenderObject = tester.renderObject<RenderParagraph>(
        find.text('同步詳細資料'),
      );
      expect(
        maxLabelRenderObject.text.style?.fontSize,
        syncLabelRenderObject.text.style?.fontSize,
      );

      final spacingKeys = <String>[
        'scrape-settings-gap-title',

        'scrape-settings-gap-sync',

        'scrape-settings-gap-replace',

        'scrape-settings-gap-fill',

        'scrape-settings-gap-max',
      ];

      for (final key in spacingKeys) {
        final gap = tester.widget<SizedBox>(find.byKey(Key(key)));

        expect(gap.height, inInclusiveRange(6, 8));
      }

      final titleBottom = tester
          .getRect(find.byKey(const Key('scrape-settings-title')))
          .bottom;

      final settingsRowKeys = <String>[
        'scrape-sync-details-switch',

        'scrape-replace-actress-image-switch',

        'scrape-fill-missing-only-switch',

        'scrape-max-actress-count-row',

        'scrape-prefix-section',
      ];

      final settingsRows = settingsRowKeys
          .map((key) => tester.getRect(find.byKey(Key(key))))
          .toList(growable: false);

      expect(settingsRows.first.top - titleBottom, closeTo(8, 0.5));

      for (var index = 1; index < settingsRows.length; index++) {
        expect(
          settingsRows[index].top - settingsRows[index - 1].bottom,

          closeTo(8, 0.5),
        );
      }

      expect(find.byKey(const Key('scrape-prefix-section')), findsOneWidget);

      expect(find.byKey(const Key('scrape-prefix-count')), findsOneWidget);

      expect(find.byKey(const Key('scrape-prefix-input')), findsNothing);

      expect(find.byKey(const Key('scrape-prefix-add')), findsNothing);

      await tester.tap(find.byKey(const Key('scrape-prefix-section')));

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scrape-prefix-input')), findsOneWidget);

      expect(find.byKey(const Key('scrape-prefix-add')), findsOneWidget);

      final addButton = tester.widget<IconButton>(
        find.byKey(const Key('scrape-prefix-add')),
      );
      expect(addButton.style?.backgroundColor, isNull);

      await tester.enterText(
        find.byKey(const Key('scrape-prefix-input')),

        'fc2-ppv_123',
      );

      await tester.tap(find.byKey(const Key('scrape-prefix-add')));

      await tester.pumpAndSettle();

      expect(find.text('FC2-PPV_123'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scrape settings remain scrollable in a constrained viewport', (
    tester,
  ) async {
    await _pumpWorks(tester);

    await _openWorksScrapeSettings(tester);

    await tester.tap(find.byKey(const Key('scrape-prefix-section')));

    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(300, 300);

    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpAndSettle();

    final scrollable = find.byKey(const Key('scrape-settings-scroll'));

    expect(scrollable, findsOneWidget);

    final scrollableStateFinder = find.descendant(
      of: scrollable,

      matching: find.byType(Scrollable),
    );

    final states = scrollableStateFinder
        .evaluate()
        .whereType<StatefulElement>()
        .map((element) => element.state)
        .whereType<ScrollableState>()
        .toList(growable: false);

    expect(states.any((state) => state.position.maxScrollExtent > 0), isTrue);

    await tester.drag(scrollable, const Offset(0, -100));

    await tester.pumpAndSettle();

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

    await _openWorksScrapeSettings(tester);

    await tester.tap(find.byKey(const Key('scrape-prefix-section')));

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

  testWidgets('actress-count limit accepts zero as unlimited', (tester) async {
    WorkScrapeOptions? received;

    await _pumpWorks(
      tester,
      scrapeExecutor: (options, token, onProgress) async {
        received = options;
        return const WorksScrapeResult(
          saved: 0,
          excluded: 0,
          failed: 0,
          cancelled: false,
        );
      },
    );

    await _openWorksScrapeSettings(tester);

    await tester.enterText(
      find.byKey(const Key('scrape-max-actress-count-input')),

      '0',
    );

    await tester.tap(find.text('開始刮削'));

    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.maxActressCount, isNull);
    expect(find.text('刮削設定'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('actress-count limit rejects decimal input', (tester) async {
    await _pumpWorks(tester);

    await _openWorksScrapeSettings(tester);

    await tester.enterText(
      find.byKey(const Key('scrape-max-actress-count-input')),

      '1.5',
    );

    await tester.tap(find.text('開始刮削'));

    await tester.pumpAndSettle();

    expect(find.text('請輸入大於等於 0 的整數'), findsOneWidget);

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

    await _openWorksScrapeSettings(tester);

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

    await _openWorksScrapeSettings(tester);

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
  AppDatabase? database,
  Size size = const Size(390, 844),
  TextScaler textScaler = TextScaler.noScaling,
  Future<WorksScrapeResult> Function(
    WorkScrapeOptions options,
    WorksScrapeCancellationToken token,
    void Function(WorksScrapeProgress progress) onProgress,
  )?
  scrapeExecutor,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    _localizedApp(
      textScaler: textScaler,
      home: WorksView(
        db: database ?? _WorksFeatureDatabase(),
        actressId: 7,
        scrapeExecutor: scrapeExecutor,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openWorksScrapeSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('works-overflow-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('works-scrape-menu-item')));
  await tester.pumpAndSettle();
}

Widget _localizedApp({
  required Widget home,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: home,
  );
}
