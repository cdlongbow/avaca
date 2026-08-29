import 'dart:async';

import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/player/player.dart';
import 'package:flutter/material.dart';

void main() {
  const useNative = bool.fromEnvironment('AVACA_PLAYER_NATIVE');
  const fixturePath = String.fromEnvironment('AVACA_PLAYER_FIXTURE');
  const harnessScenario = String.fromEnvironment(
    'AVACA_PLAYER_HARNESS_SCENARIO',
  );
  const diagnosticsEnabled = bool.fromEnvironment(
    'AVACA_PLAYER_HARNESS_DIAGNOSTICS',
  );
  final platform = useNative
      ? MethodChannelPlayerPlatform()
      : InMemoryPlayerPlatform(
          duration: const Duration(minutes: 6),
          subtitleTracks: [
            PlayerSubtitleTrack(
              id: 'ass',
              title: 'ASS',
              language: 'zh-TW',
              format: PlayerSubtitleFormat.ass,
              uri: Uri.parse('harness://ass'),
            ),
            PlayerSubtitleTrack(
              id: 'ssa',
              title: 'SSA',
              language: 'ja',
              format: PlayerSubtitleFormat.ssa,
              uri: Uri.parse('harness://ssa'),
            ),
          ],
        );
  final controller = AvacaPlayerController(platform: platform);

  runApp(
    _PlayerHarnessApp(
      controller: controller,
      request: PlayerLaunchRequest(
        workCode: 'PLAYER-HARNESS',
        source: LocalPlayerMediaSource(
          fixturePath.isEmpty ? 'player-harness' : fixturePath,
        ),
      ),
      scenario: harnessScenario,
      diagnosticsEnabled: diagnosticsEnabled,
    ),
  );
}

final class _PlayerHarnessApp extends StatelessWidget {
  const _PlayerHarnessApp({
    required this.controller,
    required this.request,
    required this.scenario,
    required this.diagnosticsEnabled,
  });

  final AvacaPlayerController controller;
  final PlayerLaunchRequest request;
  final String scenario;
  final bool diagnosticsEnabled;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => 'AVACA player harness',
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Stack(
          fit: StackFit.expand,
          children: [
            PlayerScreen(
              controller: controller,
              request: request,
              labels: PlayerUiLabels.fromLocalizations(
                AppLocalizations.of(context),
              ),
              disposeController: true,
            ),
            if (diagnosticsEnabled)
              _PlayerHarnessDiagnostics(
                controller: controller,
                scenario: scenario,
              ),
          ],
        ),
      ),
    );
  }
}

final class _PlayerHarnessDiagnostics extends StatefulWidget {
  const _PlayerHarnessDiagnostics({
    required this.controller,
    required this.scenario,
  });

  final AvacaPlayerController controller;
  final String scenario;

  @override
  State<_PlayerHarnessDiagnostics> createState() =>
      _PlayerHarnessDiagnosticsState();
}

final class _PlayerHarnessDiagnosticsState
    extends State<_PlayerHarnessDiagnostics> {
  bool _scenarioStarted = false;
  double? _lastEffectiveSpeed;
  double? _lastTemporarySpeed;
  String _line = 'HARNESS waiting';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    _handleControllerChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: IgnorePointer(
        child: Semantics(
          container: true,
          label: _line,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                _line,
                key: const Key('player-harness-diagnostics'),
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleControllerChanged() {
    final state = widget.controller.state;
    final temporarySpeedChanged = state.temporarySpeed != _lastTemporarySpeed;
    final effectiveSpeedChanged = state.effectiveSpeed != _lastEffectiveSpeed;
    if (temporarySpeedChanged || effectiveSpeedChanged) {
      _lastTemporarySpeed = state.temporarySpeed;
      _lastEffectiveSpeed = state.effectiveSpeed;
      debugPrint(
        'HARNESS_SPEED_STATE '
        'persistent=${state.persistentSpeed} '
        'temporary=${state.temporarySpeed ?? 'none'} '
        'effective=${state.effectiveSpeed} '
        'phase=${state.phase.name} '
        'positionMs=${state.position.inMilliseconds}',
      );
    }

    if (mounted) {
      setState(() {
        _line = _formatState(state);
      });
    }

    if (_scenarioStarted || widget.scenario.isEmpty) return;
    if (state.duration < const Duration(seconds: 10) ||
        state.phase == PlayerPhase.idle ||
        state.phase == PlayerPhase.loading ||
        state.phase == PlayerPhase.error) {
      return;
    }
    _scenarioStarted = true;
    unawaited(_runScenario());
  }

  String _formatState(PlayerState state) {
    final temporary = state.temporarySpeed?.toStringAsFixed(2) ?? 'none';
    return 'HARNESS ${widget.scenario.isEmpty ? 'idle' : widget.scenario} '
        'phase=${state.phase.name} '
        'positionMs=${state.position.inMilliseconds} '
        'durationMs=${state.duration.inMilliseconds} '
        'effectiveSpeed=${state.effectiveSpeed.toStringAsFixed(2)} '
        'temporarySpeed=$temporary '
        'closed=${widget.controller.isDisposed}';
  }

  Future<void> _runScenario() async {
    switch (widget.scenario) {
      case 'seek':
        await _runSeekScenario();
      case 'hold':
        await _preparePlayback();
        debugPrint(
          'HARNESS_HOLD_READY '
          'persistentSpeed=${widget.controller.state.persistentSpeed} '
          'holdSpeed=2.0',
        );
      case 'lifecycle':
        await _runLifecycleScenario();
    }
  }

  Future<void> _preparePlayback() async {
    if (widget.controller.state.phase != PlayerPhase.playing) {
      await widget.controller.play();
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  Future<void> _runSeekScenario() async {
    await _preparePlayback();
    await widget.controller.pause();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    const firstTarget = Duration(seconds: 30);
    const latestTarget = Duration(seconds: 120);
    final firstSeek = widget.controller.seekTo(firstTarget);
    final latestSeek = widget.controller.seekTo(latestTarget);
    await Future.wait<void>([firstSeek, latestSeek]);
    await Future<void>.delayed(const Duration(seconds: 1));
    await widget.controller.pause();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final state = widget.controller.state;
    final actualMs = state.position.inMilliseconds;
    final latestWins = (actualMs - latestTarget.inMilliseconds).abs() <= 1500;
    debugPrint(
      'HARNESS_SEEK_RESULT '
      'firstTargetMs=${firstTarget.inMilliseconds} '
      'latestTargetMs=${latestTarget.inMilliseconds} '
      'actualPositionMs=$actualMs '
      'durationMs=${state.duration.inMilliseconds} '
      'latestWins=$latestWins '
      'controllerDroppedEvents=${state.diagnostics.droppedEvents}',
    );
    if (mounted) {
      setState(() {
        _line = '${_formatState(state)} latestWins=$latestWins';
      });
    }
  }

  Future<void> _runLifecycleScenario() async {
    await _preparePlayback();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await widget.controller.close();
    debugPrint(
      'HARNESS_LIFECYCLE_RESULT '
      'controllerClosed=${widget.controller.isDisposed} '
      'processExpectedAlive=true',
    );
    if (mounted) {
      setState(() {
        _line = _formatState(widget.controller.state);
      });
    }
  }
}
