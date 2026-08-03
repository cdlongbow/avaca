import 'package:avaca/core/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default palettes expose semantic Snackbar backgrounds', () {
    expect(AppPalettes.light.snackbarBackground, Colors.white);
    expect(AppPalettes.dark.snackbarBackground, Colors.black);
    expect(AppPalettes.light.onSurface, isNot(Colors.white));
  });

  test('Snackbar theme follows the resolved custom palette', () {
    const background = Color(0xFF123456);
    const text = Color(0xFFEEDDCC);
    final palette = AppPalettes.dark.copyWith(
      snackbarBackground: background,
      onSurface: text,
    );

    final theme = AppTheme.fromPalette(palette);

    expect(theme.snackBarTheme.backgroundColor, background);
    expect(theme.snackBarTheme.contentTextStyle?.color, text);
    expect(theme.snackBarTheme.elevation, 0);
    expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
  });
}
