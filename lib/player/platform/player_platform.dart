import '../models/player_launch_request.dart';
import '../models/player_diagnostics.dart';
import '../models/player_error.dart';
import '../models/player_phase.dart';
import '../models/player_subtitle_track.dart';

enum PlayerSurfaceType { none, androidPlatformView, windowsTexture }

final class PlayerSurfaceDescriptor {
  const PlayerSurfaceDescriptor({
    required this.type,
    this.textureId,
    this.viewId,
    this.viewType,
    this.creationParams,
  });

  final PlayerSurfaceType type;
  final int? textureId;
  final int? viewId;
  final String? viewType;
  final Map<String, Object?>? creationParams;
}

sealed class PlayerPlatformEvent {
  const PlayerPlatformEvent();
  String get sessionId;
  int get sequence;
}

final class PlayerPlatformStateEvent extends PlayerPlatformEvent {
  const PlayerPlatformStateEvent({
    required this.sessionId,
    required this.sequence,
    this.phase,
    this.position,
    this.duration,
    this.bufferedPosition,
    this.playing,
    this.buffering,
    this.completed,
    this.tracks,
    this.selectedSubtitleTrackId,
    this.subtitleSelectionChanged = false,
    this.speed,
    this.fullscreen,
    this.seekGeneration,
    this.diagnostics,
  });
  @override
  final String sessionId;
  @override
  final int sequence;
  final PlayerPhase? phase;
  final Duration? position, duration, bufferedPosition;
  final bool? playing, buffering, completed;
  final List<PlayerSubtitleTrack>? tracks;
  final String? selectedSubtitleTrackId;
  final bool subtitleSelectionChanged;
  final double? speed;
  final bool? fullscreen;
  final int? seekGeneration;
  final PlayerDiagnostics? diagnostics;
}

final class PlayerPlatformErrorEvent extends PlayerPlatformEvent {
  const PlayerPlatformErrorEvent({
    required this.sessionId,
    required this.sequence,
    required this.error,
  });
  @override
  final String sessionId;
  @override
  final int sequence;
  final PlayerError error;
}

abstract interface class PlayerPlatformSession {
  String get sessionId;
  PlayerSurfaceDescriptor get surface;
  Stream<PlayerPlatformEvent> get events;
  Future<void> open(PlayerLaunchRequest request);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position, {int generation = 0});
  Future<void> setSpeed(double speed);
  Future<void> selectSubtitle(String? trackId);
  Future<void> setFullscreen(bool fullscreen);
  Future<PlayerDiagnostics> getDiagnostics();
  Future<void> close();
}

abstract interface class PlayerPlatform {
  Future<PlayerPlatformSession> createSession(String sessionId);
}
