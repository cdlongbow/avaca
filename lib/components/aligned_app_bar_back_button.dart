import 'package:flutter/material.dart';

/// Back button whose arrow is aligned with the visual center of the AppBar
/// title rendered with the bundled CJK font.
class AlignedAppBarBackButton extends StatelessWidget {
  const AlignedAppBarBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      icon: Transform.translate(
        offset: const Offset(0, 2),
        child: const Icon(Icons.arrow_back),
      ),
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
    );
  }
}
