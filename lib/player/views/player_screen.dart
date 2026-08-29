import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/avaca_player_controller.dart';
import '../models/player_launch_request.dart';
import '../models/player_phase.dart';
import '../widgets/player_chrome.dart';
import '../widgets/player_interaction_layer.dart';
import '../widgets/player_ui_labels.dart';
import '../widgets/player_video_surface.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.controller,
    required this.request,
    required this.labels,
    this.seekSeconds = 5,
    this.holdSpeed = 2,
    this.surfaceBuilder,
    this.onBack,
    this.disposeController = true,
  });

  final AvacaPlayerController controller;
  final PlayerLaunchRequest request;
  final PlayerUiLabels labels;
  final int seekSeconds;
  final double holdSpeed;
  final PlayerSurfaceBuilder? surfaceBuilder;
  final VoidCallback? onBack;
  final bool disposeController;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.open(widget.request));
  }

  @override
  void dispose() {
    if (widget.disposeController) widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final isDesktop =
        !kIsWeb &&
        (platform == TargetPlatform.windows ||
            platform == TargetPlatform.macOS ||
            platform == TargetPlatform.linux);

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft): _PlayerActionIntent(
          _PlayerAction.seekBackward,
        ),
        SingleActivator(LogicalKeyboardKey.arrowRight): _PlayerActionIntent(
          _PlayerAction.seekForward,
        ),
        SingleActivator(LogicalKeyboardKey.space): _PlayerActionIntent(
          _PlayerAction.togglePlayback,
        ),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _PlayerActionIntent: CallbackAction<_PlayerActionIntent>(
            onInvoke: (intent) {
              if (!isDesktop) return null;
              switch (intent.action) {
                case _PlayerAction.seekBackward:
                  unawaited(
                    widget.controller.seekRelative(
                      Duration(seconds: -widget.seekSeconds),
                    ),
                  );
                case _PlayerAction.seekForward:
                  unawaited(
                    widget.controller.seekRelative(
                      Duration(seconds: widget.seekSeconds),
                    ),
                  );
                case _PlayerAction.togglePlayback:
                  unawaited(_togglePlayback());
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final state = widget.controller.state;
              return Scaffold(
                backgroundColor: Colors.black,
                body: SafeArea(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PlayerVideoSurface(
                        descriptor: widget.controller.surface,
                        builder: widget.surfaceBuilder,
                      ),
                      PlayerInteractionLayer(
                        controller: widget.controller,
                        seekSeconds: widget.seekSeconds,
                        holdSpeed: widget.holdSpeed,
                        desktop: isDesktop,
                      ),
                      PlayerChrome(
                        controller: widget.controller,
                        workCode: widget.request.workCode,
                        labels: widget.labels,
                        onBack:
                            widget.onBack ??
                            () => Navigator.of(context).maybePop(),
                      ),
                      if (state.phase == PlayerPhase.loading)
                        const Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      if (state.phase == PlayerPhase.error)
                        Center(
                          child: Semantics(
                            liveRegion: true,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  widget.labels.error,
                                  key: const Key('player-error-message'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _togglePlayback() async {
    if (widget.controller.state.phase == PlayerPhase.playing) {
      await widget.controller.pause();
    } else {
      await widget.controller.play();
    }
  }
}

enum _PlayerAction { seekBackward, seekForward, togglePlayback }

final class _PlayerActionIntent extends Intent {
  const _PlayerActionIntent(this.action);
  final _PlayerAction action;
}
