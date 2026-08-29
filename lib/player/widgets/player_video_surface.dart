import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/player_platform.dart';

typedef PlayerSurfaceBuilder =
    Widget Function(BuildContext context, PlayerSurfaceDescriptor? descriptor);

/// The Dart layer receives a native surface/texture widget, never decoded
/// frame pixels. A missing builder is an intentional black surface for tests
/// and for hosts that have not installed a native backend yet.
final class PlayerVideoSurface extends StatelessWidget {
  const PlayerVideoSurface({super.key, this.descriptor, this.builder});

  final PlayerSurfaceDescriptor? descriptor;
  final PlayerSurfaceBuilder? builder;

  @override
  Widget build(BuildContext context) {
    final currentDescriptor = descriptor;
    final nativeSurface = builder?.call(context, descriptor);
    if (nativeSurface != null) {
      return ColoredBox(color: Colors.black, child: nativeSurface);
    }
    if (currentDescriptor?.type == PlayerSurfaceType.androidPlatformView &&
        currentDescriptor?.viewType != null) {
      return ColoredBox(
        color: Colors.black,
        child: AndroidView(
          viewType: currentDescriptor!.viewType!,
          creationParams: currentDescriptor.creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        ),
      );
    }
    if (currentDescriptor?.type == PlayerSurfaceType.windowsTexture &&
        currentDescriptor?.textureId != null) {
      return ColoredBox(
        color: Colors.black,
        child: Texture(textureId: currentDescriptor!.textureId!),
      );
    }
    return ColoredBox(color: Colors.black, child: const SizedBox.expand());
  }
}
