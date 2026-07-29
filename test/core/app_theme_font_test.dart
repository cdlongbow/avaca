import 'package:avaca/core/config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const expectedFontFamilyFallback = <String>['AvacaNotoSansTC'];

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

  group('AppTheme bundled font family fallback', () {
    test(
      'uses the Traditional Chinese fallback order for the light palette',
      () {
        final theme = AppTheme.fromPalette(AppPalettes.light);

        expect(
          theme.textTheme.bodyMedium?.fontFamilyFallback,
          expectedFontFamilyFallback,
        );
      },
    );

    test(
      'uses the Traditional Chinese fallback order for the dark palette',
      () {
        final theme = AppTheme.fromPalette(AppPalettes.dark);

        expect(
          theme.textTheme.bodyMedium?.fontFamilyFallback,
          expectedFontFamilyFallback,
        );
      },
    );

    test('keeps Android Roboto as the primary font for Latin and digits', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final theme = AppTheme.fromPalette(AppPalettes.light);

      expect(theme.textTheme.bodyMedium?.fontFamily, 'Roboto');
      expect(
        theme.textTheme.bodyMedium?.fontFamilyFallback,
        expectedFontFamilyFallback,
      );
    });

    test('applies the fallback order to every Material text style', () {
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
        expect(style?.fontFamilyFallback, expectedFontFamilyFallback);
      }
    });

    test('applies the bundled font to every custom component text style', () {
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
        expect(style?.fontFamilyFallback, expectedFontFamilyFallback);
      }
    });

    testWidgets('loads the registered font and license from rootBundle', (
      tester,
    ) async {
      final fontManifest = await rootBundle.loadString('FontManifest.json');
      final fontData = await rootBundle.load('assets/fonts/NotoSansTC-VF.ttf');
      final license = await rootBundle.loadString('assets/fonts/OFL.txt');

      expect(fontManifest, contains('"family":"AvacaNotoSansTC"'));
      expect(
        fontManifest,
        contains('"asset":"assets/fonts/NotoSansTC-VF.ttf"'),
      );
      expect(fontData.lengthInBytes, 11942912);
      expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));
    });
  });
}
