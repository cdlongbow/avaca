import 'dart:async';
import '../models/player_diagnostics.dart';
import '../models/player_launch_request.dart';
import '../models/player_phase.dart';
import '../models/player_subtitle_track.dart';
import 'player_platform.dart';

class InMemoryPlayerPlatform implements PlayerPlatform {
  InMemoryPlayerPlatform({
    this.duration = const Duration(minutes: 90),
    this.subtitleTracks = const [],
  });
  final Duration duration;
  final List<PlayerSubtitleTrack> subtitleTracks;
  final List<InMemoryPlayerPlatformSession> sessions = [];
  @override
  Future<PlayerPlatformSession> createSession(String sessionId) async {
    final s = InMemoryPlayerPlatformSession(
      sessionId,
      duration,
      subtitleTracks,
    );
    sessions.add(s);
    return s;
  }
}

class InMemoryPlayerPlatformSession implements PlayerPlatformSession {
  InMemoryPlayerPlatformSession(
    this.sessionId,
    this.duration,
    List<PlayerSubtitleTrack> tracks,
  ) : _tracks = List.unmodifiable(tracks);
  @override
  final String sessionId;
  final Duration duration;
  final List<PlayerSubtitleTrack> _tracks;
  @override
  final PlayerSurfaceDescriptor surface = const PlayerSurfaceDescriptor(
    type: PlayerSurfaceType.none,
  );
  final _events = StreamController<PlayerPlatformEvent>.broadcast();
  Duration position = Duration.zero;
  double speed = 1;
  bool playing = false;
  bool _opened = false;
  bool _hasStarted = false;
  bool fullscreen = false;
  String? selectedSubtitleTrackId;
  bool closed = false;
  int _sequence = 0;
  @override
  Stream<PlayerPlatformEvent> get events => _events.stream;
  @override
  Future<void> open(PlayerLaunchRequest request) async {
    _opened = true;
    position = request.initialPosition < Duration.zero
        ? Duration.zero
        : request.initialPosition > duration
        ? duration
        : request.initialPosition;
    selectedSubtitleTrackId =
        request.preferredSubtitleTrackId != null &&
            _tracks.any((track) => track.id == request.preferredSubtitleTrackId)
        ? request.preferredSubtitleTrackId
        : null;
    _emit(subtitleSelectionChanged: true);
  }

  @override
  Future<void> play() async {
    _hasStarted = true;
    playing = true;
    _emit();
  }

  @override
  Future<void> pause() async {
    _hasStarted = true;
    playing = false;
    _emit();
  }

  @override
  Future<void> seek(Duration value, {int generation = 0}) async {
    position = value < Duration.zero
        ? Duration.zero
        : (value > duration ? duration : value);
    _emit(seekGeneration: generation);
  }

  @override
  Future<void> setSpeed(double value) async {
    speed = value;
    _emit();
  }

  @override
  Future<void> selectSubtitle(String? trackId) async {
    if (trackId != null && !_tracks.any((track) => track.id == trackId)) {
      return;
    }
    selectedSubtitleTrackId = trackId;
    _emit(subtitleSelectionChanged: true);
  }

  @override
  Future<void> setFullscreen(bool value) async {
    fullscreen = value;
    _emit();
  }

  @override
  Future<PlayerDiagnostics> getDiagnostics() async => PlayerDiagnostics(
    sessionId: sessionId,
    lastEvent: 'in-memory',
    values: {'backend': 'in-memory'},
  );
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _events.close();
  }

  void _emit({int? seekGeneration, bool subtitleSelectionChanged = false}) {
    if (closed) return;
    _events.add(
      PlayerPlatformStateEvent(
        sessionId: sessionId,
        sequence: ++_sequence,
        phase: !_opened
            ? PlayerPhase.idle
            : playing
            ? PlayerPhase.playing
            : position == duration
            ? PlayerPhase.completed
            : !_hasStarted
            ? PlayerPhase.ready
            : PlayerPhase.paused,
        position: position,
        duration: duration,
        bufferedPosition: position,
        playing: playing,
        completed: position == duration,
        tracks: _tracks,
        selectedSubtitleTrackId: selectedSubtitleTrackId,
        subtitleSelectionChanged: subtitleSelectionChanged,
        speed: speed,
        fullscreen: fullscreen,
        seekGeneration: seekGeneration,
      ),
    );
  }
}
