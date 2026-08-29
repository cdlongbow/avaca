import 'package:flutter/material.dart';

import '../controllers/avaca_player_controller.dart';

final class PlayerSpeedMenu extends StatelessWidget {
  const PlayerSpeedMenu({
    super.key,
    required this.controller,
    required this.label,
  });

  static const choices = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  final AvacaPlayerController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    final selected = controller.state.persistentSpeed;
    return SafeArea(
      child: RadioGroup<double>(
        groupValue: selected,
        onChanged: (value) {
          if (value == null) return;
          controller.setPersistentSpeed(value);
          Navigator.of(context).pop();
        },
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(label),
              key: const Key('player-speed-menu-title'),
            ),
            for (final speed in choices)
              RadioListTile<double>(
                key: Key('player-speed-option-${speed.toString()}'),
                value: speed,
                title: Text('${_format(speed)}x'),
              ),
          ],
        ),
      ),
    );
  }

  String _format(double speed) =>
      speed == speed.roundToDouble() ? speed.toStringAsFixed(0) : '$speed';
}
