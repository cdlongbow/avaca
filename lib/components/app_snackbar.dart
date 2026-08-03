import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppSnackBar {
  AppSnackBar._();

  static const _maxWidth = 400.0;
  static const _duration = Duration(milliseconds: 3000);
  static const _horizontalPadding = 3.0;
  static const _verticalPadding = 2.0;
  static const _contentPadding = EdgeInsets.symmetric(
    horizontal: _horizontalPadding,
    vertical: _verticalPadding,
  );

  // 依照目前主題、字型與文字縮放實際測量提示內容，並限制在可用寬度內。
  static double _calculateWidth(
    BuildContext context,
    String message,
    TextStyle textStyle,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(text: message, style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();

    final viewportWidth = MediaQuery.maybeSizeOf(context)?.width ?? _maxWidth;
    final maxWidth = math.max(
      _horizontalPadding * 2,
      math.min(_maxWidth, viewportWidth),
    );
    final contentWidth = textPainter.size.width + (_horizontalPadding * 2);
    textPainter.dispose();

    return contentWidth.clamp(_horizontalPadding * 2, maxWidth);
  }

  static TextStyle _textStyle(BuildContext context) {
    final theme = Theme.of(context);
    final base =
        theme.snackBarTheme.contentTextStyle ??
        theme.textTheme.bodyMedium ??
        const TextStyle();
    return base.copyWith(color: theme.colorScheme.onSurface);
  }

  static Color _backgroundColor(BuildContext context) {
    final theme = Theme.of(context);
    return theme.snackBarTheme.backgroundColor ??
        (theme.brightness == Brightness.dark ? Colors.black : Colors.white);
  }

  // 顯示新的提示前先收起目前提示，讓畫面上一次只保留一個提示。
  static void _show(BuildContext context, String message) {
    final textStyle = _textStyle(context);
    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          softWrap: true,
          style: textStyle,
        ),
        backgroundColor: _backgroundColor(context),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        duration: _duration,
        width: _calculateWidth(context, message, textStyle),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: _contentPadding,
      ),
    );
  }

  // 顯示成功提示。
  static void showSuccess(BuildContext context, String message) {
    _show(context, message);
  }

  // 顯示錯誤提示。
  static void showError(BuildContext context, String message) {
    _show(context, message);
  }

  // 顯示一般提示。
  static void showInfo(BuildContext context, String message) {
    _show(context, message);
  }
}
