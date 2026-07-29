import 'package:avaca/components/actress_card.dart';
import 'package:avaca/core/config.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/views/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAppDatabase extends AppDatabase {
  @override
  Future<List<Map<String, Object?>>> getAllActresses({
    String searchKeyword = '',
    String filterType = '全部',
    String sortBy = '新增時間 (新到舊)',
  }) async {
    return List.generate(
      18,
      (index) => {'id': index + 1, 'name': '演員 ${index + 1}', 'img_path': null},
    );
  }
}

void main() {
  group('HomeView gallery layout', () {
    testWidgets('uses 3 proportional columns in mobile portrait', (
      tester,
    ) async {
      await _expectGalleryLayout(
        tester,
        size: const Size(390, 844),
        expectedColumns: 3,
      );
    });

    testWidgets('keeps compact spacing with 125% text scaling', (tester) async {
      await _expectGalleryLayout(
        tester,
        size: const Size(390, 844),
        expectedColumns: 3,
        textScaler: TextScaler.linear(1.25),
      );
    });

    testWidgets('uses 6 proportional columns in mobile landscape', (
      tester,
    ) async {
      await _expectGalleryLayout(
        tester,
        size: const Size(844, 390),
        expectedColumns: 6,
      );
    });

    testWidgets('uses 9 proportional columns on desktop', (tester) async {
      await _expectGalleryLayout(
        tester,
        size: const Size(1280, 720),
        expectedColumns: 9,
      );
    });
  });
}

Future<void> _expectGalleryLayout(
  WidgetTester tester, {
  required Size size,
  required int expectedColumns,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.fromPalette(AppPalettes.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: HomeView(db: FakeAppDatabase()),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final gridView = tester.widget<GridView>(find.byType(GridView));
  final delegate =
      gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
  final usableWidth = size.width - 20;
  final itemWidth =
      (usableWidth - 10 * (expectedColumns - 1)) / expectedColumns;
  final expectedNameHeight = textScaler.scale(16);
  final expectedAspectRatio = itemWidth / (itemWidth + 5 + expectedNameHeight);

  expect(delegate.crossAxisCount, expectedColumns);
  expect(delegate.crossAxisSpacing, 10);
  expect(delegate.mainAxisSpacing, 10);
  expect(delegate.childAspectRatio, closeTo(expectedAspectRatio, 0.0001));

  final firstActressCard = find.byType(ActressCard).first;
  final firstCard = find.descendant(
    of: firstActressCard,
    matching: find.byType(Card),
  );
  final secondCard = find.descendant(
    of: find.byType(ActressCard).at(1),
    matching: find.byType(Card),
  );
  final nextRowCard = find.descendant(
    of: find.byType(ActressCard).at(expectedColumns),
    matching: find.byType(Card),
  );
  final image = find.descendant(
    of: firstActressCard,
    matching: find.byType(AspectRatio),
  );
  final name = find.descendant(
    of: firstActressCard,
    matching: find.text('演員 1'),
  );

  final cardRect = tester.getRect(firstCard);
  final secondCardRect = tester.getRect(secondCard);
  final nextRowCardRect = tester.getRect(nextRowCard);
  final imageRect = tester.getRect(image);
  final nameText = tester.widget<Text>(name);
  final nameRect = tester.getRect(name);

  expect(secondCardRect.left - cardRect.right, closeTo(10, 0.001));
  expect(nextRowCardRect.top - cardRect.bottom, closeTo(10, 0.001));
  expect(imageRect.left - cardRect.left, closeTo(5, 0.001));
  expect(cardRect.right - imageRect.right, closeTo(5, 0.001));
  expect(imageRect.top - cardRect.top, closeTo(5, 0.001));
  expect(nameRect.top - imageRect.bottom, closeTo(5, 0.001));
  expect(nameText.style?.height, 1.0);
  expect(nameRect.height, closeTo(expectedNameHeight, 0.001));
  expect(cardRect.bottom - nameRect.bottom, closeTo(5, 0.001));
  expect(tester.takeException(), isNull);
}
