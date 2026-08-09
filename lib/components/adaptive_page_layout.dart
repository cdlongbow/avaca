import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/layout.dart';

/// Shared adaptive page skeleton for the primary views.
///
/// Both builders receive the same semantic content contract. A view can use
/// one shared content builder for both classes while changing only the
/// composition details that genuinely need more horizontal space.
class AdaptivePageLayout extends StatelessWidget {
  const AdaptivePageLayout({
    super.key,
    required this.compactBuilder,
    required this.expandedBuilder,
    this.padding,
    this.maxWidth,
  });

  final Widget Function(BuildContext context, AppLayoutTokens tokens)
  compactBuilder;
  final Widget Function(BuildContext context, AppLayoutTokens tokens)
  expandedBuilder;

  /// When omitted, the layout class's page padding token is applied.
  final EdgeInsets? padding;

  /// Optional surface-specific max width. Defaults to the shared token.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tokens = AppLayoutPolicy.resolve(constraints);
        final width = constraints.hasBoundedWidth
            ? math.min(constraints.maxWidth, maxWidth ?? tokens.contentMaxWidth)
            : maxWidth ?? tokens.contentMaxWidth;
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : null;
        final child = tokens.isCompact
            ? compactBuilder(context, tokens)
            : expandedBuilder(context, tokens);

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: height,
            child: Padding(
              padding: padding ?? tokens.pagePadding,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
