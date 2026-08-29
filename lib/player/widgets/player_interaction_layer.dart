import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../controllers/avaca_player_controller.dart';
import '../models/player_phase.dart';

final class PlayerInteractionLayer extends StatelessWidget {
  const PlayerInteractionLayer({
    super.key,
    required this.controller,
    required this.seekSeconds,
    required this.holdSpeed,
    this.desktop = false,
  });

  final AvacaPlayerController controller;
  final int seekSeconds;
  final double holdSpeed;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, _) => Row(
        children: [
          _zone(
            key: const Key('player-zone-left'),
            flex: 35,
            onDoubleTap: () => _seek(-seekSeconds),
          ),
          _zone(
            key: const Key('player-zone-center'),
            flex: 30,
            onDoubleTap: _togglePlayback,
          ),
          _zone(
            key: const Key('player-zone-right'),
            flex: 35,
            onDoubleTap: () => _seek(seekSeconds),
          ),
        ],
      ),
    );
  }

  Widget _zone({
    required Key key,
    required int flex,
    required VoidCallback onDoubleTap,
  }) {
    return Expanded(
      flex: flex,
      child: _PlayerGestureZone(
        key: key,
        controller: controller,
        desktop: desktop,
        holdSpeed: holdSpeed,
        onDoubleTap: onDoubleTap,
        onDesktopTap: _togglePlayback,
        child: const SizedBox.expand(),
      ),
    );
  }

  void _seek(int seconds) {
    unawaited(controller.seekRelative(Duration(seconds: seconds)));
  }

  void _togglePlayback() {
    unawaited(
      controller.state.phase == PlayerPhase.playing
          ? controller.pause()
          : controller.play(),
    );
  }
}

final class _PlayerGestureZone extends StatefulWidget {
  const _PlayerGestureZone({
    super.key,
    required this.controller,
    required this.desktop,
    required this.holdSpeed,
    required this.onDoubleTap,
    required this.onDesktopTap,
    required this.child,
  });

  final AvacaPlayerController controller;
  final bool desktop;
  final double holdSpeed;
  final VoidCallback onDoubleTap;
  final VoidCallback onDesktopTap;
  final Widget child;

  @override
  State<_PlayerGestureZone> createState() => _PlayerGestureZoneState();
}

class _PlayerGestureZoneState extends State<_PlayerGestureZone> {
  Timer? _tapTimer;
  bool _temporarySpeedActive = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      onLongPressStart: widget.desktop
          ? null
          : (_) {
              _tapTimer?.cancel();
              _tapTimer = null;
              _temporarySpeedActive = true;
              unawaited(
                widget.controller.beginTemporarySpeed(widget.holdSpeed),
              );
            },
      onLongPressEnd: widget.desktop ? null : (_) => _endTemporarySpeed(),
      onLongPressCancel: widget.desktop ? null : _endTemporarySpeed,
      child: widget.child,
    );
  }

  void _handleTap() {
    if (widget.desktop) {
      widget.onDesktopTap();
      return;
    }
    if (_tapTimer != null) {
      _tapTimer!.cancel();
      _tapTimer = null;
      widget.onDoubleTap();
      return;
    }
    // Mobile single tap is intentionally a no-op. Waiting briefly lets the
    // second tap become a deterministic double-tap without hiding controls.
    _tapTimer = Timer(kDoubleTapTimeout, () => _tapTimer = null);
  }

  void _endTemporarySpeed() {
    if (!_temporarySpeedActive) return;
    _temporarySpeedActive = false;
    if (!widget.controller.isDisposed) {
      unawaited(widget.controller.endTemporarySpeed());
    }
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    _endTemporarySpeed();
    super.dispose();
  }
}
