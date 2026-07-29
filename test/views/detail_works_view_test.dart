import 'dart:async';

import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/main.dart';
import 'package:avaca/views/detail_view.dart';
import 'package:avaca/views/works_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAppDatabase extends AppDatabase {
  final String persistedName = '已儲存名稱';

  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async {
    return {
      'id': actressId,
      'name': persistedName,
      'img_path': '',
      'main_type': '有碼,無碼',
      'memo': '',
      'height': '',
      'weight': '',
      'bwh': '',
      'cup': '',
    };
  }

  @override
  Future<List<Map<String, Object?>>> getAllActresses({
    String searchKeyword = '',
    String filterType = '全部',
    String sortBy = '新增時間 (新到舊)',
  }) async {
    return const [];
  }

  @override
  Future<String?> getSetting(String key) async => null;
}

class _PendingAppDatabase extends _FakeAppDatabase {
  final Completer<Map<String, Object?>?> result =
      Completer<Map<String, Object?>?>();

  @override
  Future<Map<String, Object?>?> getActressById(int actressId) => result.future;
}

class _NotFoundAppDatabase extends _FakeAppDatabase {
  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async => null;
}

class _FailingAppDatabase extends _FakeAppDatabase {
  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async {
    throw StateError('database unavailable');
  }
}

void main() {
  group('DetailView responsive profile layout', () {
    testWidgets(
      'places the image left and Works above attributes with symmetric gaps',
      (tester) async {
        await _pumpDetail(tester, size: const Size(390, 844));

        final imageRect = tester.getRect(
          find.byKey(const Key('detail-profile-image')),
        );
        final worksRect = tester.getRect(
          find.byKey(const Key('detail-works-button')),
        );
        final attributesRect = tester.getRect(
          find.byKey(const Key('detail-attributes')),
        );

        expect(imageRect.left, closeTo(16, 0.01));
        expect(worksRect.left, greaterThan(imageRect.right));
        expect(
          worksRect.left - imageRect.right,
          closeTo(390 - worksRect.right, 0.01),
        );
        expect(worksRect.top, closeTo(imageRect.top, 0.01));
        expect(attributesRect.left, greaterThan(imageRect.right));
        expect(attributesRect.top, greaterThan(worksRect.bottom));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'mirrors the profile layout in edit mode with compact title and chips',
      (tester) async {
        await _pumpDetail(tester, size: const Size(390, 844));

        await tester.tap(find.byIcon(Icons.edit));
        await tester.pumpAndSettle();

        final imageRect = tester.getRect(
          find.byKey(const Key('detail-profile-image')),
        );
        final worksRect = tester.getRect(
          find.byKey(const Key('detail-works-button')),
        );
        final attributesRect = tester.getRect(
          find.byKey(const Key('detail-attributes')),
        );
        final nameFieldFinder = find.byKey(const Key('detail-name-field'));
        final nameField = tester.widget<TextField>(nameFieldFinder);
        final nameFieldRect = tester.getRect(nameFieldFinder);
        final firstChip = find.byType(FilterChip).first;
        final firstChipRect = tester.getRect(firstChip);
        final chip = tester.widget<FilterChip>(firstChip);

        expect(worksRect.left, greaterThan(imageRect.right));
        expect(
          worksRect.left - imageRect.right,
          closeTo(390 - worksRect.right, 0.01),
        );
        expect(attributesRect.left, greaterThan(imageRect.right));
        expect(attributesRect.top, greaterThan(worksRect.bottom));
        expect(nameField.style?.fontSize, 18);
        expect(nameFieldRect.height, lessThanOrEqualTo(40));
        expect(firstChipRect.height, lessThanOrEqualTo(32));
        expect((chip.label as Text).style?.fontSize, 14);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('does not overflow at narrow or desktop widths', (
      tester,
    ) async {
      for (final size in const [Size(320, 700), Size(1280, 720)]) {
        await _pumpDetail(tester, size: size);
        expect(find.text('作品'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byIcon(Icons.edit));
        await tester.pumpAndSettle();
        expect(find.text('作品'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
      'uses full desktop content width for symmetric Works button gaps',
      (tester) async {
        await _pumpDetail(tester, size: const Size(1280, 720));

        final imageRect = tester.getRect(
          find.byKey(const Key('detail-profile-image')),
        );
        final worksRect = tester.getRect(
          find.byKey(const Key('detail-works-button')),
        );

        expect(
          worksRect.left - imageRect.right,
          closeTo(1280 - worksRect.right, 1),
        );
      },
    );

    testWidgets(
      'supports 125 percent text scaling in narrow view and edit layouts',
      (tester) async {
        await _pumpDetail(
          tester,
          size: const Size(320, 700),
          textScaler: TextScaler.linear(1.25),
        );

        expect(find.byKey(const Key('detail-profile-image')), findsOneWidget);
        expect(find.byKey(const Key('detail-works-button')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byIcon(Icons.edit));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('detail-name-field')), findsOneWidget);
        expect(find.byType(FilterChip), findsWidgets);
        expect(find.byKey(const Key('detail-works-button')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Works page navigation', () {
    testWidgets('keeps an accessible AppBar and title visible while loading', (
      tester,
    ) async {
      final db = _PendingAppDatabase();

      await _pumpWorks(tester, db: db);

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('作品'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byTooltip('返回'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('distinguishes a load error from a missing actress', (
      tester,
    ) async {
      await _pumpWorks(tester, db: _FailingAppDatabase());
      await tester.pumpAndSettle();

      expect(find.text('載入失敗'), findsOneWidget);
      expect(find.textContaining('database unavailable'), findsNothing);
      expect(find.text('找不到資料'), findsNothing);

      await _pumpWorks(tester, db: _NotFoundAppDatabase());
      await tester.pumpAndSettle();

      expect(find.text('找不到資料'), findsOneWidget);
      expect(find.text('載入失敗'), findsNothing);
    });

    testWidgets(
      'opens Works from view mode and returns to the unchanged detail view',
      (tester) async {
        SharedPreferences.setMockInitialValues({'app_locale': 'zh_TW'});
        final db = _FakeAppDatabase();

        await tester.pumpWidget(AvacaApp(db: db));
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(Navigator));
        Navigator.of(context).pushNamed('/detail/7');
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('detail-name-field')), findsNothing);
        await tester.tap(find.byKey(const Key('detail-works-button')));
        await tester.pumpAndSettle();

        expect(find.text('已儲存名稱演出的作品'), findsOneWidget);

        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();

        expect(find.byType(DetailView), findsOneWidget);
        expect(find.text('已儲存名稱'), findsOneWidget);
        expect(find.byKey(const Key('detail-name-field')), findsNothing);
        expect(find.byKey(const Key('detail-works-button')), findsOneWidget);
      },
    );

    testWidgets(
      'loads the persisted name and preserves an unsaved edit on back',
      (tester) async {
        SharedPreferences.setMockInitialValues({'app_locale': 'zh_TW'});
        final db = _FakeAppDatabase();

        await tester.pumpWidget(AvacaApp(db: db));
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(Navigator));
        Navigator.of(context).pushNamed('/detail/7');
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.edit));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('detail-name-field')),
          '尚未儲存名稱',
        );

        await tester.tap(find.byKey(const Key('detail-works-button')));
        await tester.pumpAndSettle();

        expect(find.byType(WorksView), findsOneWidget);
        expect(find.text('已儲存名稱演出的作品'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
        expect(find.text('尚未儲存名稱演出的作品'), findsNothing);

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        final nameField = tester.widget<TextField>(
          find.byKey(const Key('detail-name-field')),
        );
        expect(nameField.controller?.text, '尚未儲存名稱');
      },
    );
  });
}

Future<void> _pumpWorks(WidgetTester tester, {required AppDatabase db}) async {
  await tester.pumpWidget(const SizedBox.shrink());

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WorksView(db: db, actressId: 7),
    ),
  );
  await tester.pump();
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required Size size,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: textScaler),
        child: DetailView(db: _FakeAppDatabase(), actressId: 7),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
