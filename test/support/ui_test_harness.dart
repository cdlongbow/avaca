import 'dart:io';

import 'package:avaca/core/config.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void>? _uiTestFontsFuture;

/// Widget-test golden captures do not always register pubspec fonts eagerly.
/// Keep the production font path explicit so CJK wrapping and glyph shape are
/// part of the visual regression instead of tofu placeholders.
Future<void> loadUiTestFonts() {
  return _uiTestFontsFuture ??= (() async {
    final loader = FontLoader('NotoSansCjkTcVariable')
      ..addFont(rootBundle.load('assets/fonts/NotoSansCJKtc-VF.ttf'));
    await loader.load();
  })();
}

class GoldenFixtureDatabase extends AppDatabase {
  GoldenFixtureDatabase({Map<String, String>? settings})
    : _settings = settings ?? <String, String>{} {
    imgDir = Directory.systemTemp.path;
  }

  final Map<String, String> _settings;

  @override
  Future<List<Map<String, Object?>>> getAllActresses({
    String searchKeyword = '',
    String filterType = '全部',
    String sortBy = '新增時間 (新到舊)',
  }) async {
    return List.generate(
      12,
      (index) => {
        'id': index + 1,
        'name': '測試收藏 ${index + 1}',
        'img_path': null,
      },
    );
  }

  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async {
    return {
      'id': actressId,
      'name': '高一致性測試資料',
      'img_path': '',
      'main_type': '有碼,女優',
      'memo': '跨平台自適應 UI golden fixture',
      'height': '160',
      'weight': '48',
      'bwh': '87-58-85',
      'cup': 'F',
      'birth_date': '1997-12-03',
    };
  }

  @override
  Future<List<String>> getActressAliases(int actressId) async {
    return const ['測試別名'];
  }

  @override
  Future<int> getWorkCountForActress(int actressId) async => 3;

  @override
  Future<List<Map<String, Object?>>> getWorksForActress(int actressId) async {
    return const [
      {
        'id': 1,
        'code': 'TEST-001',
        'title': '第一部測試作品',
        'release_date': '2026-07-17',
        'duration_minutes': 135,
        'studio': '測試製作商',
        'publisher': '測試發行商',
        'series': '',
        'card_image_path': '',
        'detail_image_path': '',
      },
      {
        'id': 2,
        'code': 'TEST-002',
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
        'code': 'TEST-003',
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
  Future<Map<String, Object?>?> getWorkById(
    int workId, {
    int? currentActressId,
  }) async {
    for (final work in await getWorksForActress(1)) {
      if (work['id'] == workId) return work;
    }
    return null;
  }

  @override
  Future<String?> getSetting(String key) async => _settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    _settings[key] = value;
  }
}

Future<void> pumpGoldenApp(
  WidgetTester tester,
  Widget child, {
  required Size size,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('zh', 'TW'),
}) async {
  await loadUiTestFonts();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final palette = brightness == Brightness.dark
      ? AppPalettes.dark
      : AppPalettes.light;

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.fromPalette(palette),
      home: child,
      builder: (context, appChild) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: appChild!,
        );
      },
    ),
  );
  await tester.pumpAndSettle();
}
