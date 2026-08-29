import 'player_diagnostics.dart';
import 'player_error.dart';
import 'player_phase.dart';
import 'player_subtitle_track.dart';

class PlayerState {
  const PlayerState({
    this.phase = PlayerPhase.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.persistentSpeed = 1,
    this.temporarySpeed,
    this.subtitleTracks = const [],
    this.selectedSubtitleTrackId,
    this.fullscreen = false,
    this.bufferedPosition = Duration.zero,
    this.error,
    this.diagnostics = const PlayerDiagnostics(),
  });
  final PlayerPhase phase;
  final Duration position;
  final Duration duration;
  final double persistentSpeed;

  /// A temporary speed is an effective-rate override, not a multiplier.
  /// This keeps 1.5x persistent speed + 2.0x hold speed at 2.0x.
  final double? temporarySpeed;
  final List<PlayerSubtitleTrack> subtitleTracks;
  final String? selectedSubtitleTrackId;
  final bool fullscreen;
  final Duration bufferedPosition;
  final PlayerError? error;
  final PlayerDiagnostics diagnostics;
  double get effectiveSpeed => temporarySpeed ?? persistentSpeed;
  PlayerState copyWith({
    PlayerPhase? phase,
    Duration? position,
    Duration? duration,
    double? persistentSpeed,
    Object? temporarySpeed = _unset,
    List<PlayerSubtitleTrack>? subtitleTracks,
    Object? selectedSubtitleTrackId = _unset,
    bool? fullscreen,
    Duration? bufferedPosition,
    Object? error = _unset,
    PlayerDiagnostics? diagnostics,
  }) => PlayerState(
    phase: phase ?? this.phase,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    persistentSpeed: persistentSpeed ?? this.persistentSpeed,
    temporarySpeed: identical(temporarySpeed, _unset)
        ? this.temporarySpeed
        : temporarySpeed as double?,
    subtitleTracks: List.unmodifiable(subtitleTracks ?? this.subtitleTracks),
    selectedSubtitleTrackId: identical(selectedSubtitleTrackId, _unset)
        ? this.selectedSubtitleTrackId
        : selectedSubtitleTrackId as String?,
    fullscreen: fullscreen ?? this.fullscreen,
    bufferedPosition: bufferedPosition ?? this.bufferedPosition,
    error: identical(error, _unset) ? this.error : error as PlayerError?,
    diagnostics: diagnostics ?? this.diagnostics,
  );
  static const _unset = Object();
  @override
  bool operator ==(Object other) =>
      other is PlayerState &&
      other.phase == phase &&
      other.position == position &&
      other.duration == duration &&
      other.persistentSpeed == persistentSpeed &&
      other.temporarySpeed == temporarySpeed &&
      other.fullscreen == fullscreen &&
      other.bufferedPosition == bufferedPosition &&
      other.selectedSubtitleTrackId == selectedSubtitleTrackId &&
      other.error == error &&
      other.diagnostics == diagnostics &&
      _listEqual(other.subtitleTracks, subtitleTracks);
  @override
  int get hashCode => Object.hash(
    phase,
    position,
    duration,
    persistentSpeed,
    temporarySpeed,
    fullscreen,
    bufferedPosition,
    selectedSubtitleTrackId,
    error,
    diagnostics,
    Object.hashAll(subtitleTracks),
  );
  static bool _listEqual(List<Object> a, List<Object> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);
}
