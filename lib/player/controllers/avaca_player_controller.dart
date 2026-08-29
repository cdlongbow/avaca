import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/player_diagnostics.dart';
import '../models/player_error.dart';
import '../models/player_launch_request.dart';
import '../models/player_phase.dart';
import '../models/player_state.dart';
import '../platform/player_platform.dart';
import 'player_seek_coordinator.dart';

/// Owns the single Dart representation of a native player session.
final class AvacaPlayerController extends ChangeNotifier {
  AvacaPlayerController({required PlayerPlatform platform})
    : _platform = platform;

  final PlayerPlatform _platform;
  final PlayerSeekCoordinator _seeks = PlayerSeekCoordinator();

  PlayerState _state = const PlayerState();
  PlayerState get state => _state;

  PlayerPlatformSession? _session;
  StreamSubscription<PlayerPlatformEvent>? _subscription;
  PlayerLaunchRequest? _request;
  int _openGeneration = 0;
  int _sessionNumber = 0;
  int _lastEventSequence = 0;
  bool _preferredSubtitleApplied = false;
  bool _disposed = false;

  bool get isDisposed => _disposed;
  String? get sessionId => _session?.sessionId;
  PlayerSurfaceDescriptor? get surface => _session?.surface;

  /// Opens a source lazily. Reopening replaces the current session without
  /// creating a second live backend.
  Future<void> open(PlayerLaunchRequest request) {
    _ensureActive();
    return _open(request);
  }

  Future<void> _open(PlayerLaunchRequest request) async {
    final generation = ++_openGeneration;
    await _detachSession();
    if (_disposed || generation != _openGeneration) return;

    final id = 'player-${++_sessionNumber}';
    _request = request;
    _lastEventSequence = 0;
    _preferredSubtitleApplied = false;
    _set(
      _state.copyWith(
        phase: PlayerPhase.loading,
        position: Duration.zero,
        duration: Duration.zero,
        bufferedPosition: Duration.zero,
        subtitleTracks: const [],
        selectedSubtitleTrackId: null,
        error: null,
        temporarySpeed: null,
        diagnostics: _state.diagnostics.copyWith(
          sessionId: id,
          lastEvent: 'session-created',
          droppedEvents: 0,
        ),
      ),
    );

    late final PlayerPlatformSession session;
    try {
      session = await _platform.createSession(id);
    } catch (_) {
      _setFailure(
        const PlayerError(
          type: PlayerErrorType.backendInitialization,
          localizedMessageKey: 'playerErrorBackendInitialization',
          diagnosticCode: 'backend_initialization',
        ),
        generation,
      );
      return;
    }

    if (_disposed || generation != _openGeneration) {
      await session.close();
      return;
    }

    _session = session;
    _subscription = session.events.listen(
      (event) => _handleEvent(event, generation),
      onError: (Object error, StackTrace stackTrace) {
        _setFailure(
          const PlayerError(
            type: PlayerErrorType.lifecycleFailure,
            localizedMessageKey: 'playerErrorLifecycle',
            diagnosticCode: 'event_stream',
            recoverable: true,
          ),
          generation,
        );
      },
    );

    try {
      await session.open(request);
    } catch (_) {
      _setFailure(
        const PlayerError(
          type: PlayerErrorType.mediaOpenFailed,
          localizedMessageKey: 'playerErrorMediaOpenFailed',
          diagnosticCode: 'media_open_failed',
        ),
        generation,
      );
      return;
    }

    if (_disposed || generation != _openGeneration) return;
    if (_state.phase == PlayerPhase.loading) {
      _set(_state.copyWith(phase: PlayerPhase.ready));
    }
    await _sendSpeed(session);
  }

  void _handleEvent(PlayerPlatformEvent event, int generation) {
    if (_disposed ||
        generation != _openGeneration ||
        _session?.sessionId != event.sessionId) {
      _dropEvent();
      return;
    }
    if (event.sequence <= _lastEventSequence) {
      _dropEvent();
      return;
    }
    _lastEventSequence = event.sequence;

    if (event is PlayerPlatformErrorEvent) {
      _setFailure(event.error, generation);
      return;
    }
    if (_state.phase == PlayerPhase.error &&
        event is PlayerPlatformStateEvent &&
        event.phase != PlayerPhase.error) {
      _dropEvent();
      return;
    }
    if (event is! PlayerPlatformStateEvent) return;
    if (event.seekGeneration != null &&
        !_seeks.accepts(event.seekGeneration!)) {
      _dropEvent();
      return;
    }

    var next = _state;
    final phase = _phaseFor(event);
    if (phase != null) next = next.copyWith(phase: phase);
    if (event.position != null) {
      next = next.copyWith(position: _clamp(event.position!, event.duration));
    }
    if (event.duration != null) {
      next = next.copyWith(
        duration: _nonNegative(event.duration!),
        position: _clamp(next.position, event.duration),
      );
    }
    if (event.bufferedPosition != null) {
      next = next.copyWith(
        bufferedPosition: _nonNegative(event.bufferedPosition!),
      );
    }
    if (event.tracks != null) {
      next = next.copyWith(subtitleTracks: event.tracks);
      if (next.selectedSubtitleTrackId != null &&
          !event.tracks!.any(
            (track) => track.id == next.selectedSubtitleTrackId,
          )) {
        next = next.copyWith(selectedSubtitleTrackId: null);
      }
    }
    if (!event.subtitleSelectionChanged &&
        event.selectedSubtitleTrackId != null &&
        next.subtitleTracks.any(
          (track) => track.id == event.selectedSubtitleTrackId,
        )) {
      next = next.copyWith(
        selectedSubtitleTrackId: event.selectedSubtitleTrackId,
      );
    }
    if (event.subtitleSelectionChanged) {
      next = next.copyWith(
        selectedSubtitleTrackId: event.selectedSubtitleTrackId,
      );
      if (event.selectedSubtitleTrackId == _request?.preferredSubtitleTrackId) {
        _preferredSubtitleApplied = true;
      }
    }
    if (event.speed != null && next.temporarySpeed == null) {
      next = next.copyWith(
        persistentSpeed: event.speed!.clamp(0.5, 2.0).toDouble(),
      );
    }
    if (event.fullscreen != null) {
      next = next.copyWith(fullscreen: event.fullscreen);
    }
    if (event.diagnostics != null) {
      next = next.copyWith(diagnostics: event.diagnostics);
    } else {
      next = next.copyWith(
        diagnostics: next.diagnostics.copyWith(
          lastEvent: event.phase?.name ?? 'state',
        ),
      );
    }
    _set(next);

    final preferred = _request?.preferredSubtitleTrackId;
    if (!_preferredSubtitleApplied &&
        preferred != null &&
        next.selectedSubtitleTrackId == null &&
        next.subtitleTracks.any((track) => track.id == preferred)) {
      _preferredSubtitleApplied = true;
      unawaited(selectSubtitle(preferred));
    }
  }

  PlayerPhase? _phaseFor(PlayerPlatformStateEvent event) {
    if (event.phase != null) return event.phase;
    if (event.completed == true) return PlayerPhase.completed;
    if (event.buffering == true) return PlayerPhase.buffering;
    if (event.playing == true) return PlayerPhase.playing;
    if (event.playing == false && _state.phase != PlayerPhase.loading) {
      return PlayerPhase.paused;
    }
    return _state.phase == PlayerPhase.loading ? PlayerPhase.ready : null;
  }

  Future<void> play() async {
    _ensureActive();
    final session = _session;
    if (session == null) return;
    try {
      await session.play();
    } catch (_) {
      _setFailure(
        const PlayerError(
          type: PlayerErrorType.lifecycleFailure,
          localizedMessageKey: 'playerErrorLifecycle',
          diagnosticCode: 'play_failed',
          recoverable: true,
        ),
        _openGeneration,
      );
    }
  }

  Future<void> pause() async {
    _ensureActive();
    final session = _session;
    if (session == null) return;
    try {
      await session.pause();
    } catch (_) {
      _setFailure(
        const PlayerError(
          type: PlayerErrorType.lifecycleFailure,
          localizedMessageKey: 'playerErrorLifecycle',
          diagnosticCode: 'pause_failed',
          recoverable: true,
        ),
        _openGeneration,
      );
    }
  }

  Future<void> seekTo(Duration target) async {
    _ensureActive();
    final session = _session;
    if (session == null) return;
    final generation = _seeks.next();
    final bounded = _clamp(target, _state.duration);
    try {
      await session.seek(bounded, generation: generation);
    } catch (_) {
      if (_seeks.accepts(generation)) {
        _setFailure(
          const PlayerError(
            type: PlayerErrorType.seekFailure,
            localizedMessageKey: 'playerErrorSeekFailed',
            diagnosticCode: 'seek_failed',
            recoverable: true,
          ),
          _openGeneration,
        );
      }
    }
  }

  Future<void> seekRelative(Duration delta) => seekTo(_state.position + delta);

  Future<void> setPersistentSpeed(double speed) async {
    _ensureActive();
    final value = speed.clamp(0.5, 2.0).toDouble();
    final session = _session;
    _set(_state.copyWith(persistentSpeed: value));
    if (session == null) return;
    await _sendSpeed(session);
  }

  /// Sets the temporary effective speed used by a press-and-hold gesture.
  /// Passing null restores the persistent speed and never starts playback.
  Future<void> setTemporarySpeed(double? speed) async {
    _ensureActive();
    final value = speed?.clamp(1.25, 4.0).toDouble();
    final session = _session;
    _set(_state.copyWith(temporarySpeed: value));
    if (session == null) return;
    await _sendSpeed(session);
  }

  Future<void> beginTemporarySpeed([double speed = 2.0]) =>
      setTemporarySpeed(speed);

  Future<void> endTemporarySpeed() => setTemporarySpeed(null);

  Future<void> _sendSpeed(PlayerPlatformSession session) async {
    try {
      await session.setSpeed(_state.effectiveSpeed);
    } catch (_) {
      _setFailure(
        const PlayerError(
          type: PlayerErrorType.lifecycleFailure,
          localizedMessageKey: 'playerErrorLifecycle',
          diagnosticCode: 'rate_failed',
          recoverable: true,
        ),
        _openGeneration,
      );
    }
  }

  Future<void> selectSubtitle(String? trackId) async {
    _ensureActive();
    final session = _session;
    if (session == null) return;
    if (trackId != null &&
        !_state.subtitleTracks.any((track) => track.id == trackId)) {
      return;
    }
    _set(_state.copyWith(selectedSubtitleTrackId: trackId));
    try {
      await session.selectSubtitle(trackId);
    } catch (_) {
      _setFailure(
        const PlayerError(
          type: PlayerErrorType.subtitleFailure,
          localizedMessageKey: 'playerErrorSubtitleFailed',
          diagnosticCode: 'subtitle_selection_failed',
          recoverable: true,
        ),
        _openGeneration,
      );
    }
  }

  Future<void> setFullscreen(bool value) async {
    _ensureActive();
    final session = _session;
    if (session == null) return;
    try {
      await session.setFullscreen(value);
      _set(_state.copyWith(fullscreen: value));
    } catch (_) {
      _setFailure(
        const PlayerError(
          type: PlayerErrorType.rendererFailure,
          localizedMessageKey: 'playerErrorFullscreenFailed',
          diagnosticCode: 'fullscreen_failed',
          recoverable: true,
        ),
        _openGeneration,
      );
    }
  }

  Future<PlayerDiagnostics> getDiagnostics() async {
    _ensureActive();
    final session = _session;
    if (session == null) return _state.diagnostics;
    final diagnostics = await session.getDiagnostics();
    if (!_disposed) _set(_state.copyWith(diagnostics: diagnostics));
    return diagnostics;
  }

  void _setFailure(PlayerError error, int generation) {
    if (_disposed || generation != _openGeneration) return;
    _set(
      _state.copyWith(
        phase: PlayerPhase.error,
        error: error,
        temporarySpeed: null,
      ),
    );
  }

  void _dropEvent() {
    if (_disposed) return;
    _state = _state.copyWith(
      diagnostics: _state.diagnostics.copyWith(
        droppedEvents: _state.diagnostics.droppedEvents + 1,
      ),
    );
    notifyListeners();
  }

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    ++_openGeneration;
    await _detachSession();
  }

  Future<void> _detachSession() async {
    await _subscription?.cancel();
    _subscription = null;
    final session = _session;
    _session = null;
    if (session != null) await session.close();
  }

  Duration _clamp(Duration value, Duration? upperBound) {
    final nonNegative = _nonNegative(value);
    final duration = upperBound == null
        ? _state.duration
        : _nonNegative(upperBound);
    return nonNegative > duration ? duration : nonNegative;
  }

  Duration _nonNegative(Duration value) =>
      value < Duration.zero ? Duration.zero : value;

  void _set(PlayerState value) {
    if (_disposed || value == _state) return;
    _state = value;
    notifyListeners();
  }

  void _ensureActive() {
    if (_disposed) throw StateError('The player controller is disposed.');
  }

  @override
  void dispose() {
    if (_disposed) return;
    unawaited(close());
    super.dispose();
  }
}
