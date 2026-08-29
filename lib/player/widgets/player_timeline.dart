import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/avaca_player_controller.dart';

final class PlayerTimeline extends StatefulWidget {
  const PlayerTimeline({
    super.key,
    required this.controller,
    required this.label,
  });

  final AvacaPlayerController controller;
  final String label;

  @override
  State<PlayerTimeline> createState() => _PlayerTimelineState();
}

class _PlayerTimelineState extends State<PlayerTimeline> {
  Duration? _scrubPosition;

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final duration = state.duration;
    final position = _scrubPosition ?? state.position;
    final maximum = duration.inMicroseconds.toDouble();
    final value = duration == Duration.zero
        ? 0.0
        : position.inMicroseconds.clamp(0, duration.inMicroseconds).toDouble();
    const foreground = Colors.white;

    return Column(
      key: const Key('player-timeline'),
      children: [
        Slider(
          key: const Key('player-timeline-slider'),
          min: 0,
          max: maximum == 0 ? 1 : maximum,
          value: value,
          onChanged: duration == Duration.zero
              ? null
              : (raw) {
                  setState(() {
                    _scrubPosition = Duration(
                      microseconds: raw.round().clamp(
                        0,
                        duration.inMicroseconds,
                      ),
                    );
                  });
                },
          onChangeEnd: duration == Duration.zero
              ? null
              : (raw) {
                  final target = Duration(
                    microseconds: raw.round().clamp(0, duration.inMicroseconds),
                  );
                  setState(() => _scrubPosition = null);
                  unawaited(widget.controller.seekTo(target));
                },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _format(position),
              key: const Key('player-position'),
              style: TextStyle(color: foreground),
            ),
            Semantics(
              label: widget.label,
              child: Text(
                _format(duration),
                key: const Key('player-duration'),
                style: TextStyle(color: foreground),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _format(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
