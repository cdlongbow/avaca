import 'package:avaca/components/app_snackbar.dart';
import 'package:avaca/core/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'uses the light palette Snackbar surface for every semantic type',
    (tester) async {
      await _pumpSnackBarHarness(tester, AppPalettes.light);

      await tester.tap(find.byKey(const Key('show-success')));
      await tester.pump();
      final success = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(success.backgroundColor, AppPalettes.light.snackbarBackground);

      await tester.tap(find.byKey(const Key('show-error')));
      await tester.pump();
      final error = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(error.backgroundColor, AppPalettes.light.snackbarBackground);

      await tester.tap(find.byKey(const Key('show-info')));
      await tester.pump();
      final info = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(info.backgroundColor, AppPalettes.light.snackbarBackground);
    },
  );

  testWidgets('uses black background and primary text in dark mode', (
    tester,
  ) async {
    await _pumpSnackBarHarness(tester, AppPalettes.dark);

    await tester.tap(find.byKey(const Key('show-success')));
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    final text = snackBar.content as Text;
    expect(snackBar.backgroundColor, AppPalettes.dark.snackbarBackground);
    expect(text.style?.color, AppPalettes.dark.onSurface);
  });

  testWidgets(
    'custom palette controls Snackbar background without semantic overrides',
    (tester) async {
      const customBackground = Color(0xFF203040);
      final palette = AppPalettes.light.copyWith(
        snackbarBackground: customBackground,
      );
      await _pumpSnackBarHarness(tester, palette);

      await tester.tap(find.byKey(const Key('show-error')));
      await tester.pump();

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, customBackground);
    },
  );

  testWidgets('is floating, flat, tightly padded, and content-sized', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSnackBarHarness(tester, AppPalettes.light);
    await tester.tap(find.byKey(const Key('show-short')));
    await tester.pump();

    final shortSnackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    final shortWidth = shortSnackBar.width!;
    expect(shortSnackBar.behavior, SnackBarBehavior.floating);
    expect(shortSnackBar.elevation, 0);
    expect(
      shortSnackBar.padding,
      const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
    );
    final shortText = shortSnackBar.content as Text;
    expect(
      shortText.style?.letterSpacing,
      isNull,
      reason: '2–3px applies to content padding, not character spacing.',
    );
    final shortPainter = TextPainter(
      text: TextSpan(text: 'ok', style: shortText.style),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(shortWidth, closeTo(shortPainter.width + 6, 0.001));
    shortPainter.dispose();
    expect(
      shortSnackBar.shape,
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    await tester.tap(find.byKey(const Key('show-long')));
    await tester.pump();
    final longWidth = tester.widget<SnackBar>(find.byType(SnackBar)).width!;
    expect(longWidth, greaterThan(shortWidth));
    expect(longWidth, lessThanOrEqualTo(320));
  });
}

Future<void> _pumpSnackBarHarness(WidgetTester tester, AppPalette palette) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.fromPalette(palette),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              ElevatedButton(
                key: const Key('show-success'),
                onPressed: () => AppSnackBar.showSuccess(context, 'saved'),
                child: const Text('success'),
              ),
              ElevatedButton(
                key: const Key('show-error'),
                onPressed: () => AppSnackBar.showError(context, 'failed'),
                child: const Text('error'),
              ),
              ElevatedButton(
                key: const Key('show-info'),
                onPressed: () => AppSnackBar.showInfo(context, 'info'),
                child: const Text('info'),
              ),
              ElevatedButton(
                key: const Key('show-short'),
                onPressed: () => AppSnackBar.showInfo(context, 'ok'),
                child: const Text('short'),
              ),
              ElevatedButton(
                key: const Key('show-long'),
                onPressed: () => AppSnackBar.showInfo(
                  context,
                  'This notification contains enough words to wrap within the available viewport width.',
                ),
                child: const Text('long'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
