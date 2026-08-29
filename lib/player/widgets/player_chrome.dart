import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/avaca_player_controller.dart';
import '../models/player_phase.dart';
import 'player_speed_menu.dart';
import 'player_subtitle_menu.dart';
import 'player_timeline.dart';
import 'player_ui_labels.dart';

final class PlayerChrome extends StatelessWidget {
  const PlayerChrome({
    super.key,
    required this.controller,
    required this.workCode,
    required this.labels,
    required this.onBack,
  });

  final AvacaPlayerController controller;
  final String workCode;
  final PlayerUiLabels labels;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    const foreground = Colors.white;
    return Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.topStart,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    button: true,
                    label: labels.back,
                    child: IconButton(
                      key: const Key('player-back'),
                      tooltip: labels.back,
                      color: foreground,
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      workCode,
                      key: const Key('player-work-code'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            PlayerTimeline(controller: controller, label: labels.position),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Semantics(
                  button: true,
                  label: state.phase == PlayerPhase.playing
                      ? labels.pause
                      : labels.play,
                  child: IconButton(
                    key: const Key('player-play-pause'),
                    tooltip: state.phase == PlayerPhase.playing
                        ? labels.pause
                        : labels.play,
                    color: foreground,
                    onPressed: () => unawaited(_togglePlayback()),
                    icon: Icon(
                      state.phase == PlayerPhase.playing
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                  ),
                ),
                const Spacer(),
                Semantics(
                  button: true,
                  label: labels.speed,
                  child: IconButton(
                    key: const Key('player-speed'),
                    tooltip: labels.speed,
                    color: foreground,
                    onPressed: () => _showSpeedMenu(context),
                    icon: const Icon(Icons.speed),
                  ),
                ),
                Semantics(
                  button: true,
                  label: labels.subtitle,
                  child: IconButton(
                    key: const Key('player-subtitle'),
                    tooltip: labels.subtitle,
                    color: foreground,
                    onPressed: () => _showSubtitleMenu(context),
                    icon: const Icon(Icons.closed_caption_outlined),
                  ),
                ),
                Semantics(
                  button: true,
                  label: state.fullscreen
                      ? labels.exitFullscreen
                      : labels.fullscreen,
                  child: IconButton(
                    key: const Key('player-fullscreen'),
                    tooltip: state.fullscreen
                        ? labels.exitFullscreen
                        : labels.fullscreen,
                    color: foreground,
                    onPressed: () =>
                        unawaited(controller.setFullscreen(!state.fullscreen)),
                    icon: Icon(
                      state.fullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePlayback() async {
    if (controller.state.phase == PlayerPhase.playing) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  Future<void> _showSpeedMenu(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) =>
          PlayerSpeedMenu(controller: controller, label: labels.speed),
    );
  }

  Future<void> _showSubtitleMenu(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) =>
          PlayerSubtitleMenu(controller: controller, labels: labels),
    );
  }
}
