import 'package:avaca/core/config.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/views/settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'system',
      'pure_black': true,
      'app_locale': 'en',
    });
  });

  testWidgets('settings root shows categories but hides their details', (
    tester,
  ) async {
    await _pumpSettings(tester);

    expect(find.text('Theme & Colors'), findsOneWidget);
    expect(find.text('Interface'), findsOneWidget);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
    expect(find.byIcon(Icons.language), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    _expectOutlinedCategoryCard(tester, 'Theme & Colors');
    _expectOutlinedCategoryCard(tester, 'Interface');
    expect(find.text('Theme Mode'), findsNothing);
    expect(find.text('Language'), findsNothing);
    expect(find.text('Pure Black AMOLED'), findsNothing);
  });

  testWidgets('all visible settings text uses the bundled variable font', (
    tester,
  ) async {
    await _pumpSettings(tester);

    for (final element in find.byType(Text).evaluate()) {
      final text = element.widget as Text;
      final inheritedStyle = DefaultTextStyle.of(element).style;
      final effectiveStyle = inheritedStyle.merge(text.style);

      expect(
        effectiveStyle.fontFamily,
        'NotoSansCjkTcVariable',
        reason: 'Missing bundled font on "${text.data}"',
      );
      expect(
        effectiveStyle.fontWeight?.value,
        greaterThanOrEqualTo(FontWeight.w300.value),
        reason: 'Text is lighter than w300 on "${text.data}"',
      );
    }
  });

  testWidgets(
    'system dark nests AMOLED under Dark without changing the selected mode',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await _pumpSettings(tester);
      await tester.tap(find.text('Theme & Colors'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Theme & Colors'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.text('Theme Mode'), findsOneWidget);
      _expectStyledExpansionTile(tester, 'Theme Mode');
      expect(find.text('Follow System'), findsNothing);
      expect(find.text('Dark'), findsNothing);
      expect(find.text('Pure Black AMOLED'), findsNothing);

      await tester.tap(find.text('Theme Mode'));
      await tester.pumpAndSettle();

      expect(find.text('Follow System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Custom Theme'), findsOneWidget);
      final darkOption = find.byKey(const PageStorageKey('theme-option-dark'));
      expect(darkOption, findsOneWidget);
      _expectSecondaryExpansionTile(tester, darkOption);
      expect(find.text('Pure Black AMOLED'), findsNothing);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('theme_mode'), 'system');

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(find.text('Pure Black AMOLED'), findsOneWidget);
      expect(preferences.getString('theme_mode'), 'system');

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(find.text('Pure Black AMOLED'), findsNothing);
      final darkRadio = find.descendant(
        of: darkOption,
        matching: find.byType(Radio<String>),
      );
      expect(darkRadio, findsOneWidget);

      await tester.tap(darkRadio);
      await tester.pumpAndSettle();

      expect(preferences.getString('theme_mode'), 'dark');
      expect(find.text('Pure Black AMOLED'), findsNothing);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(find.text('Pure Black AMOLED'), findsOneWidget);
      expect(find.byType(Divider), findsNothing);
    },
  );

  testWidgets(
    'system light promotes Dark from a radio option after it is selected',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await _pumpSettings(tester);
      await tester.tap(find.text('Theme & Colors'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theme Mode'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const PageStorageKey('theme-option-dark')),
        findsNothing,
      );
      final darkRadio = find.widgetWithText(RadioListTile<String>, 'Dark');
      expect(darkRadio, findsOneWidget);
      expect(find.text('Pure Black AMOLED'), findsNothing);

      await tester.tap(darkRadio);
      await tester.pumpAndSettle();

      final darkOption = find.byKey(const PageStorageKey('theme-option-dark'));
      expect(darkOption, findsOneWidget);
      _expectSecondaryExpansionTile(tester, darkOption);
      expect(find.text('Pure Black AMOLED'), findsNothing);
      expect(find.byType(Divider), findsNothing);
    },
  );

  testWidgets(
    'custom mode in platform dark keeps Dark a radio and hides AMOLED',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'custom',
        'pure_black': true,
        'app_locale': 'en',
      });
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await _pumpSettings(tester);
      await tester.tap(find.text('Theme & Colors'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theme Mode'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const PageStorageKey('theme-option-custom')),
        findsOneWidget,
      );
      expect(
        find.byKey(const PageStorageKey('theme-option-dark')),
        findsNothing,
      );
      expect(
        find.widgetWithText(RadioListTile<String>, 'Dark'),
        findsOneWidget,
      );
      expect(find.text('Pure Black AMOLED'), findsNothing);
    },
  );

  testWidgets('fixed dark AMOLED copy excludes custom theme', (tester) async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'dark',
      'pure_black': true,
      'app_locale': 'en',
    });

    await _pumpSettings(tester);
    await tester.tap(find.text('Theme & Colors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme Mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const PageStorageKey('theme-option-dark')));
    await tester.pumpAndSettle();

    expect(find.text('Only works with dark theme'), findsOneWidget);
    expect(find.textContaining('/ custom theme'), findsNothing);
  });

  testWidgets('selecting Custom promotes it into a collapsed color submenu', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await _pumpSettings(tester);
    await tester.tap(find.text('Theme & Colors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme Mode'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const PageStorageKey('theme-option-custom')),
      findsNothing,
    );
    final customRadio = find.widgetWithText(
      RadioListTile<String>,
      'Custom Theme',
    );
    expect(customRadio, findsOneWidget);

    await tester.ensureVisible(customRadio);
    await tester.pumpAndSettle();
    await tester.tap(customRadio);
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('theme_mode'), 'custom');
    final customOption = find.byKey(
      const PageStorageKey('theme-option-custom'),
    );
    expect(customOption, findsOneWidget);
    _expectSecondaryExpansionTile(tester, customOption);
    expect(find.text('Background'), findsNothing);

    await tester.ensureVisible(customOption);
    await tester.pumpAndSettle();
    await tester.tap(customOption);
    await tester.pumpAndSettle();

    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Primary Accent'), findsOneWidget);
  });

  testWidgets('interface category expands all language choices', (
    tester,
  ) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Interface'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Interface'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    _expectStyledExpansionTile(tester, 'Language');
    expect(find.text('Follow System'), findsNothing);
    expect(find.text('Traditional Chinese (Taiwan)'), findsNothing);
    expect(find.text('Simplified Chinese'), findsNothing);
    expect(find.text('Japanese'), findsNothing);
    expect(find.text('English'), findsNothing);

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();

    expect(find.text('Follow System'), findsOneWidget);
    expect(find.text('Traditional Chinese (Taiwan)'), findsOneWidget);
    expect(find.text('Simplified Chinese'), findsOneWidget);
    expect(find.text('Japanese'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    await tester.tap(find.text('Traditional Chinese (Taiwan)'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '介面'), findsOneWidget);
    expect(find.text('語言'), findsOneWidget);
  });

  testWidgets('interface category exposes works page size choices', (
    tester,
  ) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Interface'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(find.text('Works page size'), findsOneWidget);

    await tester.tap(find.byKey(const PageStorageKey('works-page-size')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const PageStorageKey('works-page-size-option-small')),
      findsOneWidget,
    );
    expect(
      find.byKey(const PageStorageKey('works-page-size-option-large')),
      findsOneWidget,
    );
    expect(find.text('Small'), findsOneWidget);
    expect(find.text('Large'), findsOneWidget);

    await tester.tap(
      find.byKey(const PageStorageKey('works-page-size-option-large')),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('works_page_size'), 'large');
  });

  testWidgets('AMOLED is hidden in effective light mode', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await _pumpSettings(tester);
    await tester.tap(find.text('Theme & Colors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme Mode'));
    await tester.pumpAndSettle();

    expect(find.text('Pure Black AMOLED'), findsNothing);
    expect(find.byKey(const PageStorageKey('theme-option-dark')), findsNothing);
  });

  testWidgets(
    'AMOLED follows effective system darkness and preserves its preference',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await _pumpSettings(tester);
      await tester.tap(find.text('Theme & Colors'));
      await tester.pumpAndSettle();

      expect(find.text('Pure Black AMOLED'), findsNothing);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();

      await tester.tap(find.text('Theme Mode'));
      await tester.pumpAndSettle();

      final darkOption = find.byKey(const PageStorageKey('theme-option-dark'));
      expect(darkOption, findsOneWidget);
      expect(find.text('Pure Black AMOLED'), findsNothing);

      await tester.tap(darkOption);
      await tester.pumpAndSettle();

      expect(find.text('Pure Black AMOLED'), findsOneWidget);
      final pureBlackSwitch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Pure Black AMOLED'),
      );
      expect(pureBlackSwitch.value, isTrue);
    },
  );

  testWidgets('custom theme nests the complete color editor under Custom', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'custom',
      'pure_black': false,
      'app_locale': 'en',
    });

    await _pumpSettings(tester);
    await tester.tap(find.text('Theme & Colors'));
    await tester.pumpAndSettle();

    expect(find.text('Background'), findsNothing);
    expect(find.text('Primary Accent'), findsNothing);

    await tester.tap(find.text('Theme Mode'));
    await tester.pumpAndSettle();

    final customOption = find.byKey(
      const PageStorageKey('theme-option-custom'),
    );
    expect(customOption, findsOneWidget);
    _expectSecondaryExpansionTile(tester, customOption);
    expect(find.text('Background'), findsNothing);
    expect(find.text('Primary Accent'), findsNothing);

    await tester.ensureVisible(customOption);
    await tester.pumpAndSettle();
    await tester.tap(customOption);
    await tester.pumpAndSettle();

    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Card Background'), findsOneWidget);
    expect(find.text('Primary Text'), findsOneWidget);
    expect(find.text('Secondary Text'), findsOneWidget);
    expect(find.text('Primary Accent'), findsOneWidget);
    expect(find.text('Text on Primary'), findsOneWidget);
    expect(find.text('Border / Divider'), findsOneWidget);
    expect(find.text('Snackbar Background'), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('color dialog previews the selected color on its outline', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'custom',
      'pure_black': false,
      'app_locale': 'en',
    });

    await _pumpSettings(tester);
    await tester.tap(find.text('Theme & Colors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme Mode'));
    await tester.pumpAndSettle();
    final customOption = find.byKey(
      const PageStorageKey('theme-option-custom'),
    );
    await tester.ensureVisible(customOption);
    await tester.pumpAndSettle();
    await tester.tap(customOption);
    await tester.pumpAndSettle();
    final background = find.text('Background');
    await tester.ensureVisible(background);
    await tester.pumpAndSettle();
    await tester.tap(background);
    await tester.pumpAndSettle();

    _expectDialogOutline(tester, Colors.black);

    final colorPicker = tester.widget<ColorPicker>(find.byType(ColorPicker));
    colorPicker.onColorChanged(const Color(0xFF123456));
    await tester.pump();

    _expectDialogOutline(tester, const Color(0xFF123456));
  });

  testWidgets(
    'category press uses a transparent tile overlay and local feedback dot',
    (tester) async {
      await _pumpSettings(tester);

      final category = find.ancestor(
        of: find.text('Theme & Colors'),
        matching: find.byType(Card),
      );
      final pressPosition = tester.getCenter(category) + const Offset(80, 0);
      final gesture = await tester.startGesture(pressPosition);
      await tester.pump();

      _expectTransparentPressedOverlay(tester, category);
      final feedbackDot = find.byKey(
        const ValueKey('settings-feedback-dot-category-theme-colors'),
      );
      _expectLocalFeedbackDot(tester, feedbackDot, pressPosition);

      await gesture.cancel();
      await tester.pump(const Duration(milliseconds: 40));
      expect(feedbackDot, findsOneWidget);
      await tester.pumpAndSettle();
      expect(feedbackDot, findsNothing);
    },
  );

  testWidgets(
    'nested setting press shares the transparent local feedback behavior',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'dark',
        'pure_black': false,
        'app_locale': 'en',
      });

      await _pumpSettings(tester);
      await tester.tap(find.text('Theme & Colors'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theme Mode'));
      await tester.pumpAndSettle();

      final darkOption = find.byKey(const PageStorageKey('theme-option-dark'));
      final pressPosition =
          tester.getTopLeft(darkOption) + const Offset(180, 28);
      final gesture = await tester.startGesture(pressPosition);
      await tester.pump();

      _expectTransparentPressedOverlay(tester, darkOption);
      final feedbackDot = find.byKey(
        const ValueKey('settings-feedback-dot-theme-mode'),
      );
      _expectLocalFeedbackDot(tester, feedbackDot, pressPosition);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 40));
      expect(feedbackDot, findsOneWidget);
      await tester.pumpAndSettle();
      expect(feedbackDot, findsNothing);
    },
  );

  testWidgets('custom settings remain scrollable on a narrow scaled viewport', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'custom',
      'pure_black': true,
      'app_locale': 'en',
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 480);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpSettings(tester, textScaler: const TextScaler.linear(1.25));
    await tester.tap(find.text('Theme & Colors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme Mode'));
    await tester.pumpAndSettle();

    final customOption = find.byKey(
      const PageStorageKey('theme-option-custom'),
    );
    await tester.ensureVisible(customOption);
    await tester.pumpAndSettle();
    await tester.tap(customOption);
    await tester.pumpAndSettle();

    final outline = find.text('Border / Divider');
    await tester.ensureVisible(outline);
    await tester.pumpAndSettle();

    expect(outline, findsOneWidget);
    expect(find.text('Pure Black AMOLED'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _expectOutlinedCategoryCard(WidgetTester tester, String label) {
  final cardFinder = find.ancestor(
    of: find.text(label),
    matching: find.byType(Card),
  );

  expect(cardFinder, findsOneWidget);

  final card = tester.widget<Card>(cardFinder);
  final shape = card.shape;

  expect(shape, isA<RoundedRectangleBorder>());

  final roundedShape = shape! as RoundedRectangleBorder;
  expect(roundedShape.borderRadius, BorderRadius.circular(12));
  expect(roundedShape.side.width, 1);
  expect(
    roundedShape.side.color,
    Theme.of(tester.element(cardFinder)).colorScheme.outline,
  );
}

void _expectStyledExpansionTile(WidgetTester tester, String label) {
  final tileFinder = find.widgetWithText(ExpansionTile, label);

  expect(tileFinder, findsOneWidget);

  final tile = tester.widget<ExpansionTile>(tileFinder);
  expect(tile.leading, isNull);
  expect(tile.trailing, isNull);
  expect(tile.showTrailingIcon, isTrue);
  expect(tile.clipBehavior, Clip.antiAlias);
  _expectOutlinedShape(tester, tileFinder, tile.shape);
  _expectOutlinedShape(tester, tileFinder, tile.collapsedShape);

  final animationStyle = tile.expansionAnimationStyle;
  expect(animationStyle, isNotNull);
  expect(animationStyle!.duration, const Duration(milliseconds: 180));
  expect(animationStyle.curve, Curves.easeOutCubic);
  expect(animationStyle.reverseCurve, Curves.easeInCubic);
}

void _expectSecondaryExpansionTile(WidgetTester tester, Finder tileFinder) {
  final tile = tester.widget<ExpansionTile>(tileFinder);

  expect(tile.leading, isA<Radio<String>>());
  expect(tile.trailing, isNull);
  expect(tile.showTrailingIcon, isTrue);
  expect(tile.shape, const Border());
  expect(tile.collapsedShape, const Border());
  expect(tile.backgroundColor, Colors.transparent);
  expect(tile.collapsedBackgroundColor, Colors.transparent);

  final animationStyle = tile.expansionAnimationStyle;
  expect(animationStyle, isNotNull);
  expect(animationStyle!.duration, const Duration(milliseconds: 180));
}

void _expectDialogOutline(WidgetTester tester, Color expectedColor) {
  final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
  final shape = dialog.shape;

  expect(shape, isA<RoundedRectangleBorder>());

  final roundedShape = shape! as RoundedRectangleBorder;
  expect(roundedShape.borderRadius, BorderRadius.circular(12));
  expect(roundedShape.side.width, 1);
  expect(roundedShape.side.color, expectedColor);
}

void _expectTransparentPressedOverlay(
  WidgetTester tester,
  Finder tappableRegion,
) {
  final inkWellFinder = find.descendant(
    of: tappableRegion,
    matching: find.byType(InkWell),
  );
  expect(inkWellFinder, findsOneWidget);

  final inkWell = tester.widget<InkWell>(inkWellFinder);
  final theme = Theme.of(tester.element(inkWellFinder));
  expect(
    inkWell.overlayColor?.resolve({WidgetState.pressed}) ??
        theme.highlightColor,
    Colors.transparent,
  );
  expect(theme.splashFactory, NoSplash.splashFactory);
  expect(theme.splashColor, Colors.transparent);
}

void _expectLocalFeedbackDot(
  WidgetTester tester,
  Finder feedbackDot,
  Offset pressPosition,
) {
  expect(feedbackDot, findsOneWidget);
  expect(tester.getCenter(feedbackDot).dx, closeTo(pressPosition.dx, 1));
  expect(tester.getCenter(feedbackDot).dy, closeTo(pressPosition.dy, 1));

  final size = tester.getSize(feedbackDot);
  expect(size.width, lessThanOrEqualTo(16));
  expect(size.height, size.width);

  final dot = tester.widget<DecoratedBox>(feedbackDot);
  final decoration = dot.decoration;
  expect(decoration, isA<BoxDecoration>());
  expect((decoration as BoxDecoration).shape, BoxShape.circle);
}

void _expectOutlinedShape(
  WidgetTester tester,
  Finder tileFinder,
  ShapeBorder? shape,
) {
  expect(shape, isA<RoundedRectangleBorder>());

  final roundedShape = shape! as RoundedRectangleBorder;
  expect(roundedShape.borderRadius, BorderRadius.circular(12));
  expect(roundedShape.side.width, 1);
  expect(
    roundedShape.side.color,
    Theme.of(tester.element(tileFinder)).colorScheme.outline,
  );
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(_SettingsHarness(textScaler: textScaler));
  await tester.pumpAndSettle();
}

class _SettingsHarness extends StatefulWidget {
  const _SettingsHarness({this.textScaler = TextScaler.noScaling});

  final TextScaler textScaler;

  @override
  State<_SettingsHarness> createState() => _SettingsHarnessState();
}

class _SettingsHarnessState extends State<_SettingsHarness> {
  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale = const Locale('en');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.fromPalette(AppPalettes.light),
      darkTheme: AppTheme.fromPalette(AppPalettes.dark),
      themeMode: _themeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: widget.textScaler),
        child: child!,
      ),
      home: SettingsView(
        db: _FakeAppDatabase(),
        onThemeChanged: (themeMode, _, _) {
          if (_themeMode == themeMode) return;
          setState(() => _themeMode = themeMode);
        },
        onLocaleChanged: (locale) {
          if (_locale == locale) return;
          setState(() => _locale = locale);
        },
      ),
    );
  }
}

class _FakeAppDatabase extends AppDatabase {
  final Map<String, String> _settings = {};

  @override
  Future<String?> getSetting(String key) async => _settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    _settings[key] = value;
  }
}
