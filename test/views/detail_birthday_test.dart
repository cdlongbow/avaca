import 'package:avaca/core/config.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/views/detail_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _BirthdayDatabase extends AppDatabase {
  _BirthdayDatabase({this.birthDate = '2000-01-01'});

  String? birthDate;

  @override
  Future<int> getWorkCountForActress(int actressId) async => 0;

  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async {
    return {
      'id': actressId,
      'name': '生日測試',
      'img_path': '',
      'main_type': '',
      'memo': '',
      'height': '',
      'weight': '',
      'bwh': '',
      'cup': '',
      'birth_date': birthDate,
    };
  }

  @override
  Future<bool> updateActress({
    required int actressId,
    required String name,
    String imgPath = '',
    String mainType = '',
    String memo = '',
    String height = '',
    String weight = '',
    String bwh = '',
    String cup = '',
    String? birthDate,
  }) async {
    this.birthDate = birthDate;
    return true;
  }
}

void main() {
  testWidgets('body info shows current age and yyyy/MM/dd birth date', (
    tester,
  ) async {
    await tester.pumpWidget(_detailApp(_BirthdayDatabase()));
    await tester.pumpAndSettle();

    final expectedAge = DateTime.now().year - 2000;
    expect(find.text('$expectedAge歲  2000/01/01'), findsOneWidget);
  });

  testWidgets('unknown birth date shows no fabricated age or date', (
    tester,
  ) async {
    await tester.pumpWidget(_detailApp(_BirthdayDatabase(birthDate: null)));
    await tester.pumpAndSettle();

    expect(find.textContaining(RegExp(r'\d+歲')), findsNothing);
    expect(find.textContaining(RegExp(r'\d{4}/\d{2}/\d{2}')), findsNothing);
  });

  testWidgets('birthday editor is a clearable three-column wheel sheet', (
    tester,
  ) async {
    await tester.pumpWidget(_detailApp(_BirthdayDatabase()));
    await tester.pumpAndSettle();
    await _enterDetailEditMode(tester);

    final birthDateButton = find.byKey(const Key('detail-birth-date-button'));
    expect(birthDateButton, findsOneWidget);
    final button = tester.widget<OutlinedButton>(birthDateButton);
    final align = button.child! as Align;
    final label = align.child! as Text;
    final colorScheme = Theme.of(tester.element(birthDateButton)).colorScheme;
    expect(align.alignment, Alignment.centerLeft);
    expect(label.style?.fontSize, 16);
    expect(label.style?.color, colorScheme.onSurfaceVariant);
    await tester.tap(birthDateButton);
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPicker), findsNWidgets(3));
    expect(find.byKey(const Key('birth-date-year-picker')), findsOneWidget);
    expect(find.byKey(const Key('birth-date-month-picker')), findsOneWidget);
    expect(find.byKey(const Key('birth-date-day-picker')), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('清除'), findsOneWidget);
    expect(find.textContaining('農曆'), findsNothing);

    final expectedOverlayColor = Theme.of(
      tester.element(find.byType(DetailView)),
    ).colorScheme.primary.withValues(alpha: 0.28);
    for (final picker in tester.widgetList<CupertinoPicker>(
      find.byType(CupertinoPicker),
    )) {
      final overlay = picker.selectionOverlay! as Container;
      final decoration = overlay.decoration! as BoxDecoration;
      expect(decoration.color, expectedOverlayColor);
      expect(decoration.border, isNull);
      expect(decoration.borderRadius, BorderRadius.circular(6));
    }
  });

  testWidgets('changing January 31 to February clamps to leap-day', (
    tester,
  ) async {
    await tester.pumpWidget(
      _detailApp(_BirthdayDatabase(birthDate: '2024-01-31')),
    );
    await tester.pumpAndSettle();
    await _enterDetailEditMode(tester);
    await tester.tap(find.byKey(const Key('detail-birth-date-button')));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('birth-date-month-picker')),
      const Offset(0, -48),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2024/02/29'), findsOneWidget);
  });

  testWidgets('changed birthday persists after Save and reopen', (
    tester,
  ) async {
    final database = _BirthdayDatabase(birthDate: '2024-01-31');
    await tester.pumpWidget(_detailApp(database));
    await tester.pumpAndSettle();

    await _openBirthdayEditor(tester);
    await tester.drag(
      find.byKey(const Key('birth-date-month-picker')),
      const Offset(0, -48),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();

    expect(database.birthDate, '2024-02-29');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(_detailApp(database));
    await tester.pumpAndSettle();
    expect(find.textContaining('2024/02/29'), findsOneWidget);
  });

  testWidgets('Clear persists null after Save', (tester) async {
    final database = _BirthdayDatabase();
    await tester.pumpWidget(_detailApp(database));
    await tester.pumpAndSettle();

    await _openBirthdayEditor(tester);
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();

    expect(database.birthDate, isNull);
    expect(find.textContaining(RegExp(r'\d+歲')), findsNothing);
    expect(find.textContaining(RegExp(r'\d{4}/\d{2}/\d{2}')), findsNothing);
  });

  testWidgets('Cancel keeps the original birthday', (tester) async {
    final database = _BirthdayDatabase(birthDate: '2024-01-31');
    await tester.pumpWidget(_detailApp(database));
    await tester.pumpAndSettle();

    await _openBirthdayEditor(tester);
    await tester.drag(
      find.byKey(const Key('birth-date-month-picker')),
      const Offset(0, -48),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();

    expect(database.birthDate, '2024-01-31');
  });

  testWidgets('current year, month, and day expose no future choices', (
    tester,
  ) async {
    final today = DateTime.now();
    final isoToday =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    await tester.pumpWidget(_detailApp(_BirthdayDatabase(birthDate: isoToday)));
    await tester.pumpAndSettle();

    await _openBirthdayEditor(tester);
    final yearPicker = tester.widget<CupertinoPicker>(
      find.byKey(const Key('birth-date-year-picker')),
    );
    final monthPicker = tester.widget<CupertinoPicker>(
      find.byKey(const Key('birth-date-month-picker')),
    );
    final dayPicker = tester.widget<CupertinoPicker>(
      find.byKey(const Key('birth-date-day-picker')),
    );

    expect(yearPicker.scrollController!.selectedItem, 0);
    expect(monthPicker.childDelegate.estimatedChildCount, today.month);
    expect(dayPicker.childDelegate.estimatedChildCount, today.day);
  });
}

Future<void> _openBirthdayEditor(WidgetTester tester) async {
  await _enterDetailEditMode(tester);
  await tester.tap(find.byKey(const Key('detail-birth-date-button')));
  await tester.pumpAndSettle();
}

Future<void> _enterDetailEditMode(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('detail-overflow-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('detail-edit-menu-item')));
  await tester.pumpAndSettle();
}

Widget _detailApp(AppDatabase database) {
  return MaterialApp(
    theme: AppTheme.fromPalette(AppPalettes.light),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'TW'),
    home: DetailView(db: database, actressId: 1),
  );
}
