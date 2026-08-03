import 'package:avaca/core/config.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const expectedFontFamily = 'NotoSansCjkTcVariable';
  const minimumFontWeight = FontWeight.w400;

  test('custom palette ignores OLED and keeps every custom color exact', () {
    const customPalette = AppPalette(
      brightness: Brightness.dark,
      surface: Color(0xFF123456),
      surfaceContainer: Color(0xFF234567),
      onSurface: Color(0xFF345678),
      onSurfaceVariant: Color(0xFF456789),
      primary: Color(0xFF56789A),
      onPrimary: Color(0xFF6789AB),
      outline: Color(0xFF789ABC),
    );

    final resolved = AppThemeResolver.resolve(
      options: const AppThemeOptions(
        mode: AppThemeMode.custom,
        oledBlack: true,
        customPalette: customPalette,
      ),
      systemBrightness: Brightness.dark,
    );

    expect(resolved.surface, customPalette.surface);
    expect(resolved.surfaceContainer, customPalette.surfaceContainer);
    expect(resolved.onSurface, customPalette.onSurface);
    expect(resolved.onSurfaceVariant, customPalette.onSurfaceVariant);
    expect(resolved.primary, customPalette.primary);
    expect(resolved.onPrimary, customPalette.onPrimary);
    expect(resolved.outline, customPalette.outline);
    expect(identical(resolved, customPalette), isTrue);
  });

  group('AppTheme bundled variable font', () {
    for (final palette in [AppPalettes.light, AppPalettes.dark]) {
      test('uses the single bundled family for ${palette.brightness.name}', () {
        final theme = AppTheme.fromPalette(palette);

        expect(theme.textTheme.bodyMedium?.fontFamily, expectedFontFamily);
      });
    }

    test(
      'applies the family and minimum weight to every Material text style',
      () {
        final textTheme = AppTheme.fromPalette(AppPalettes.light).textTheme;
        final styles = <TextStyle?>[
          textTheme.displayLarge,
          textTheme.displayMedium,
          textTheme.displaySmall,
          textTheme.headlineLarge,
          textTheme.headlineMedium,
          textTheme.headlineSmall,
          textTheme.titleLarge,
          textTheme.titleMedium,
          textTheme.titleSmall,
          textTheme.bodyLarge,
          textTheme.bodyMedium,
          textTheme.bodySmall,
          textTheme.labelLarge,
          textTheme.labelMedium,
          textTheme.labelSmall,
        ];

        for (final style in styles) {
          expect(style?.fontFamily, expectedFontFamily);
          expect(
            style?.fontWeight?.value,
            greaterThanOrEqualTo(minimumFontWeight.value),
          );
        }
      },
    );

    test('applies the family and minimum weight to component text styles', () {
      final theme = AppTheme.fromPalette(AppPalettes.light);
      final styles = <TextStyle?>[
        theme.inputDecorationTheme.labelStyle,
        theme.inputDecorationTheme.hintStyle,
        theme.inputDecorationTheme.helperStyle,
        theme.listTileTheme.titleTextStyle,
        theme.listTileTheme.subtitleTextStyle,
        theme.dialogTheme.titleTextStyle,
        theme.dialogTheme.contentTextStyle,
        theme.navigationBarTheme.labelTextStyle?.resolve({}),
        theme.navigationBarTheme.labelTextStyle?.resolve({
          WidgetState.selected,
        }),
      ];

      for (final style in styles) {
        expect(style?.fontFamily, expectedFontFamily);
        expect(
          style?.fontWeight?.value,
          greaterThanOrEqualTo(minimumFontWeight.value),
        );
      }
    });

    testWidgets(
      'renders mixed-language names with the same family and locale',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ja', 'JP'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.fromPalette(AppPalettes.light),
            home: const Scaffold(body: Text('三上悠亜・八木奈々 / AVACA 简体中文')),
          ),
        );

        final text = tester.widget<Text>(find.byType(Text));
        final element = tester.element(find.byType(Text));
        final effectiveStyle = DefaultTextStyle.of(
          element,
        ).style.merge(text.style);

        expect(effectiveStyle.fontFamily, expectedFontFamily);
        expect(effectiveStyle.fontWeight, minimumFontWeight);
        expect(Localizations.localeOf(element), const Locale('ja', 'JP'));

        final fontManifest = await rootBundle.loadString('FontManifest.json');
        final fontData = await rootBundle.load(
          'assets/fonts/NotoSansCJKtc-VF.ttf',
        );

        expect(fontManifest, contains('"family":"$expectedFontFamily"'));
        expect(
          fontManifest,
          contains('"asset":"assets/fonts/NotoSansCJKtc-VF.ttf"'),
        );
        expect(fontData.lengthInBytes, 36143328);
      },
    );
  });
}
