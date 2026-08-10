import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/views/detail_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'alias button opens a trim-and-save modal between works and attributes',
    (tester) async {
      final database = _AliasDetailDatabase();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DetailView(db: database, actressId: 7),
        ),
      );
      await tester.pumpAndSettle();

      final works = tester.getRect(
        find.byKey(const Key('detail-works-button')),
      );
      final aliases = tester.getRect(
        find.byKey(const Key('detail-aliases-button')),
      );
      final attributes = tester.getRect(
        find.byKey(const Key('detail-attributes')),
      );
      expect(works.bottom, lessThanOrEqualTo(aliases.top));
      expect(aliases.bottom, lessThanOrEqualTo(attributes.top));

      final expectedTextColor = Theme.of(
        tester.element(find.byType(DetailView)),
      ).colorScheme.onSurface;
      for (final key in const [
        'detail-works-button',
        'detail-aliases-button',
      ]) {
        final button = tester.widget<OutlinedButton>(find.byKey(Key(key)));
        expect(
          button.style?.foregroundColor?.resolve(<WidgetState>{}),
          expectedTextColor,
        );
      }

      await tester.tap(find.byKey(const Key('detail-aliases-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail-aliases-dialog')), findsOneWidget);
      expect(find.byKey(const Key('detail-alias-input')), findsOneWidget);
      expect(find.byKey(const Key('detail-alias-add')), findsOneWidget);
      expect(find.byKey(const Key('detail-alias-save')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('detail-alias-input')),
        '  新別名  ',
      );
      await tester.tap(find.byKey(const Key('detail-alias-add')));
      await tester.pumpAndSettle();
      expect(find.text('新別名'), findsOneWidget);

      await tester.tap(find.byKey(const Key('detail-alias-save')));
      await tester.pumpAndSettle();
      expect(database.savedAliases, ['舊別名', '新別名']);
      expect(find.byKey(const Key('detail-aliases-dialog')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _AliasDetailDatabase extends AppDatabase {
  List<String> aliases = ['舊別名'];
  List<String> savedAliases = const [];

  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async {
    return {
      'id': actressId,
      'name': '測試女優',
      'img_path': '',
      'main_type': '有碼',
      'memo': '',
      'height': '160',
      'weight': '',
      'bwh': '87-58-85',
      'cup': 'F',
      'birth_date': '1997-12-03',
      'aliases': aliases,
    };
  }

  @override
  Future<int> getWorkCountForActress(int actressId) async => 2;

  @override
  Future<List<String>> getActressAliases(int actressId) async => aliases;

  @override
  Future<void> replaceActressAliases({
    required int actressId,
    required Iterable<String> aliases,
  }) async {
    savedAliases = aliases.toList(growable: false);
    this.aliases = savedAliases;
  }
}
