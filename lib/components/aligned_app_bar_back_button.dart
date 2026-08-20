import 'package:flutter/material.dart';

/// Back button whose arrow stays aligned with the AppBar title.
class AlignedAppBarBackButton extends StatelessWidget {
  const AlignedAppBarBackButton({
    super.key,
    this.onPressed,
    this.verticalOffset = 2,
    this.expandToToolbar = false,
  });

  final VoidCallback? onPressed;
  final double verticalOffset;
  final bool expandToToolbar;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      icon: Transform.translate(
        offset: Offset(0, verticalOffset),
        child: const Icon(Icons.arrow_back),
      ),
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
    );
    if (!expandToToolbar) return button;
    return SizedBox.expand(child: Center(child: button));
  }
}
