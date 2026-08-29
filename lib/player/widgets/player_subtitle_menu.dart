import 'package:flutter/material.dart';

import '../controllers/avaca_player_controller.dart';
import 'player_ui_labels.dart';

final class PlayerSubtitleMenu extends StatelessWidget {
  const PlayerSubtitleMenu({
    super.key,
    required this.controller,
    required this.labels,
  });

  final AvacaPlayerController controller;
  final PlayerUiLabels labels;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    const offValue = '__player_subtitle_off__';
    return SafeArea(
      child: RadioGroup<String>(
        groupValue: state.selectedSubtitleTrackId ?? offValue,
        onChanged: (value) {
          if (value == null) return;
          controller.selectSubtitle(value == offValue ? null : value);
          Navigator.of(context).pop();
        },
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(labels.subtitle),
              key: const Key('player-subtitle-menu-title'),
            ),
            RadioListTile<String>(
              key: const Key('player-subtitle-option-off'),
              value: offValue,
              title: Text(labels.subtitleOff),
            ),
            for (final track in state.subtitleTracks)
              RadioListTile<String>(
                key: Key('player-subtitle-option-${track.id}'),
                value: track.id,
                title: Text(track.displayLabel),
              ),
          ],
        ),
      ),
    );
  }
}
