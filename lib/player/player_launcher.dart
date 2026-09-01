import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../library/library_media_resolver.dart';
import 'controllers/avaca_player_controller.dart';
import 'models/player_launch_request.dart';
import 'models/player_media_source.dart';
import 'platform/method_channel_player_platform.dart';
import 'platform/player_platform.dart';
import 'views/player_screen.dart';
import 'widgets/player_ui_labels.dart';

/// App-level integration seam for launching the existing Player Core.
///
/// It resolves persisted media identity before constructing a controller. No
/// screen is pushed when the managed file is unavailable or unsafe.
final class PlayerLauncher {
  PlayerLauncher({
    required this.mediaResolver,
    PlayerPlatform Function()? platformFactory,
  }) : platformFactory = platformFactory ?? MethodChannelPlayerPlatform.new;

  final LibraryMediaResolver mediaResolver;
  final PlayerPlatform Function() platformFactory;

  Future<void> launch({
    required BuildContext context,
    required String workCode,
    required String mediaPortableId,
    int? expectedWorkId,
    String? expectedWorkPortableId,
    required AppLocalizations localizations,
  }) async {
    final resolved = await mediaResolver.resolveByPortableId(
      mediaPortableId,
      expectedWorkId: expectedWorkId,
      expectedWorkPortableId: expectedWorkPortableId,
      verifyIntegrity: true,
    );
    if (!context.mounted) return;
    final request = PlayerLaunchRequest(
      workCode: workCode,
      source: LocalPlayerMediaSource(resolved.absolutePath),
    );
    final controller = AvacaPlayerController(platform: platformFactory());
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          controller: controller,
          request: request,
          labels: PlayerUiLabels.fromLocalizations(localizations),
        ),
      ),
    );
  }
}
