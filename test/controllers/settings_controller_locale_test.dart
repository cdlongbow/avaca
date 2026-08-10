import 'package:avaca/controllers/settings_controller.dart';
import 'package:avaca/core/config.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAppDatabase extends AppDatabase {
  @override
  Future<String?> getSetting(String key) async => null;

  @override
  Future<List<Map<String, Object?>>> getAllActresses({
    String searchKeyword = '',
    String filterType = '全部',
    String sortBy = '新增時間 (新到舊)',
  }) async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'app_locale': 'system'});
  });

  test('locale choices use canonical app locale identifiers', () {
    final controller = SettingsController(db: AppDatabase());

    expect(controller.getLocaleOptions(), [
      'system',
      'zh_TW',
      'zh_CN',
      'ja_JP',
      'en',
    ]);
    expect(
      AppLocalizations.supportedLocales,
      contains(const Locale('ja', 'JP')),
    );
  });

  test('Japanese selection persists and resolves to ja_JP', () async {
    final controller = SettingsController(db: AppDatabase());

    await controller.languageChanged('ja_JP');

    expect(controller.localeString, 'ja_JP');
    expect(controller.appLocale, const Locale('ja', 'JP'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_locale'), 'ja_JP');
  });

  test(
    'works page size defaults to Small when the preference is missing',
    () async {
      SharedPreferences.setMockInitialValues({});
      final controller = SettingsController(db: _FakeAppDatabase());

      await controller.loadFromPrefs();

      expect(controller.worksPageSize, WorksPageSize.small);
    },
  );

  test(
    'works page size falls back to Small for an invalid preference',
    () async {
      SharedPreferences.setMockInitialValues({'works_page_size': 'unknown'});
      final controller = SettingsController(db: _FakeAppDatabase());

      await controller.loadFromPrefs();

      expect(controller.worksPageSize, WorksPageSize.small);
    },
  );

  test('works page size persists and restores Small and Large', () async {
    final controller = SettingsController(db: _FakeAppDatabase());

    await controller.worksPageSizeChanged(WorksPageSize.large);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('works_page_size'), 'large');

    final restored = SettingsController(db: _FakeAppDatabase());
    await restored.loadFromPrefs();
    expect(restored.worksPageSize, WorksPageSize.large);

    await restored.worksPageSizeChanged(WorksPageSize.small);
    expect(prefs.getString('works_page_size'), 'small');
  });

  testWidgets('app restores ja_JP as its active locale', (tester) async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'system',
      'pure_black': false,
      'app_locale': 'ja_JP',
    });

    await tester.pumpWidget(AvacaApp(db: _FakeAppDatabase()));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, const Locale('ja', 'JP'));
    expect(app.theme?.textTheme.bodyMedium?.fontFamily, AppTheme.fontFamily);
  });
}
