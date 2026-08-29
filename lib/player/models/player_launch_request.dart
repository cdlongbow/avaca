import 'player_media_source.dart';

class PlayerLaunchRequest {
  const PlayerLaunchRequest({
    required this.workCode,
    required this.source,
    this.initialPosition = Duration.zero,
    this.preferredSubtitleTrackId,
  });
  final String workCode;
  final PlayerMediaSource source;
  final Duration initialPosition;
  final String? preferredSubtitleTrackId;

  Map<String, Object?> toJson({bool redactSecrets = false}) => {
    'workCode': workCode,
    'source': source.toJson(redactSecrets: redactSecrets),
    'initialPositionMs': initialPosition.inMilliseconds,
    'preferredSubtitleTrackId': preferredSubtitleTrackId,
  };

  @override
  bool operator ==(Object other) =>
      other is PlayerLaunchRequest &&
      other.workCode == workCode &&
      other.source.toString() == source.toString() &&
      other.initialPosition == initialPosition &&
      other.preferredSubtitleTrackId == preferredSubtitleTrackId;

  @override
  int get hashCode => Object.hash(
    workCode,
    source.toString(),
    initialPosition,
    preferredSubtitleTrackId,
  );
}
