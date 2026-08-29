import 'package:flutter/foundation.dart';

import '../../l10n/app_localizations.dart';

/// All user-visible player copy is supplied by the host localization layer.
@immutable
final class PlayerUiLabels {
  const PlayerUiLabels({
    required this.back,
    required this.play,
    required this.pause,
    required this.speed,
    required this.subtitle,
    required this.fullscreen,
    required this.exitFullscreen,
    required this.subtitleOff,
    required this.holdSpeed,
    required this.position,
    required this.error,
  });

  final String back;
  final String play;
  final String pause;
  final String speed;
  final String subtitle;
  final String fullscreen;
  final String exitFullscreen;
  final String subtitleOff;
  final String holdSpeed;
  final String position;
  final String error;

  factory PlayerUiLabels.fromLocalizations(AppLocalizations localizations) {
    return PlayerUiLabels(
      back: localizations.playerBack,
      play: localizations.playerPlay,
      pause: localizations.playerPause,
      speed: localizations.playerSpeed,
      subtitle: localizations.playerSubtitles,
      fullscreen: localizations.playerFullscreen,
      exitFullscreen: localizations.playerExitFullscreen,
      subtitleOff: localizations.playerSubtitleOff,
      holdSpeed: localizations.playerHoldSpeed,
      position: localizations.playerPosition,
      error: localizations.playerPlaybackError,
    );
  }
}
