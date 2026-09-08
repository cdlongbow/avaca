import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:avaca_remote_core/avaca_remote_core.dart';

/// Channel names shared by the AVACA player Dart adapter and native plugin.
final class AvacaPlayerNative {
  AvacaPlayerNative._();

  static const String viewType = 'avaca_player_native/video';
  static const String controlChannelName = 'avaca/player/control';
  static const String eventsChannelName = 'avaca/player/events';
  static const String discoveryChannelName = 'avaca/remote/discovery';
  static const String discoveryEventsChannelName =
      'avaca/remote/discovery_events';

  static const MethodChannel control = MethodChannel(controlChannelName);
  static const EventChannel events = EventChannel(eventsChannelName);
  static const MethodChannel discovery = MethodChannel(discoveryChannelName);
  static const EventChannel discoveryEvents = EventChannel(
    discoveryEventsChannelName,
  );
}

/// Native DNS-SD / NsdManager discovery for the AVACA client.
///
/// The stream yields candidates only.  The caller must still show the
/// endpoint and certificate pin to the user and require an invitation before
/// persisting a profile.
final class NativeAvacaRemoteDiscovery implements AvacaRemoteDiscovery {
  const NativeAvacaRemoteDiscovery({
    MethodChannel? channel,
    EventChannel? eventsChannel,
  }) : _channel = channel ?? AvacaPlayerNative.discovery,
       _eventsChannel = eventsChannel ?? AvacaPlayerNative.discoveryEvents;

  final MethodChannel _channel;
  final EventChannel _eventsChannel;

  @override
  Stream<AvacaRemoteDiscoveryCandidate> candidates() => _eventsChannel
      .receiveBroadcastStream()
      .map(AvacaRemoteDiscoveryEvent.fromPlatformValue)
      .map((event) => event.candidate);

  Stream<AvacaRemoteDiscoveryEvent> events() => _eventsChannel
      .receiveBroadcastStream()
      .map(AvacaRemoteDiscoveryEvent.fromPlatformValue);

  Future<void> start() => _channel.invokeMethod<void>('start');

  Future<void> stop() => _channel.invokeMethod<void>('stop');
}

/// Native player composition for the separated AVACA client.  The method
/// channel carries descriptors and control only; media bytes stay in the
/// Windows libmpv or Android Media3 native data-plane.
final class NativeAvacaRemotePlaybackBridge
    implements AvacaRemotePlaybackBridge {
  NativeAvacaRemotePlaybackBridge({
    required this.profile,
    MethodChannel? channel,
  }) : _channel = channel ?? AvacaPlayerNative.control;

  final AvacaRemoteClientProfile profile;
  final MethodChannel _channel;
  NativeAvacaPlayerSurfaceInfo? _lastSurface;

  NativeAvacaPlayerSurfaceInfo? get lastSurface => _lastSurface;

  @override
  Future<AvacaRemotePlaybackHandle> open(
    AvacaRemoteResourceDescriptor descriptor,
  ) async {
    final sessionId = descriptor.playbackSessionId;
    final grant = descriptor.playbackGrant;
    if (sessionId == null || grant == null || grant.length != 32) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidInput,
        'native playback descriptor is incomplete',
      );
    }
    final created = await _channel.invokeMethod<Object?>('createSession', {
      'sessionId': sessionId,
    });
    _lastSurface = NativeAvacaPlayerSurfaceInfo.fromPlatformValue(
      sessionId,
      created,
    );
    await _channel.invokeMethod<void>('configureRemote', {
      'sessionId': sessionId,
      'profile': {
        'serverId': profile.serverId,
        'clientId': profile.clientId,
        'host': profile.host,
        'port': profile.port,
        'certificateSha256Pin': profile.leafCertificateSha256,
        'pairingSecret': profile.pairingSecret,
      },
    });
    try {
      await _channel.invokeMethod<void>('open', {
        'sessionId': sessionId,
        'request': {
          'source': {
            'kind': 'remote',
            'uri': 'avaca-quic://${descriptor.resourceId}',
            'resourceId': descriptor.resourceId,
            'playbackSessionId': sessionId,
            'playbackGrant': grant,
            'contentLength': descriptor.length,
          },
        },
      });
    } on Object {
      await _closeSession(sessionId);
      rethrow;
    }
    return _NativeAvacaPlaybackHandle(_channel, sessionId);
  }

  Future<void> _closeSession(String sessionId) async {
    try {
      await _channel.invokeMethod<void>('close', {'sessionId': sessionId});
    } on Object {
      // The server-side session close remains authoritative when the native
      // player has already lost its connection.
    }
  }
}

final class _NativeAvacaPlaybackHandle implements AvacaRemotePlaybackHandle {
  _NativeAvacaPlaybackHandle(this._channel, this._sessionId);

  final MethodChannel _channel;
  final String _sessionId;
  bool _closed = false;

  @override
  int get length => throw UnsupportedError(
    'native player owns the range stream; Dart cannot expose media bytes',
  );

  @override
  Future<Uint8List> readAt(int offset, int length) => throw UnsupportedError(
    'native player owns the range stream; Dart cannot expose media bytes',
  );

  @override
  Future<void> cancel() async {
    if (_closed) return;
    await _channel.invokeMethod<void>('close', {'sessionId': _sessionId});
    _closed = true;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _channel.invokeMethod<void>('close', {'sessionId': _sessionId});
    } on Object {
      // A native close racing a transport failure is already terminal.
    }
  }
}

final class NativeAvacaPlayerSurfaceInfo {
  const NativeAvacaPlayerSurfaceInfo({
    required this.sessionId,
    required this.surfaceType,
    this.textureId,
    this.viewType,
  });

  final String sessionId;
  final String surfaceType;
  final int? textureId;
  final String? viewType;

  static NativeAvacaPlayerSurfaceInfo fromPlatformValue(
    String sessionId,
    Object? value,
  ) {
    if (value is! Map) {
      throw const FormatException('native player surface is invalid');
    }
    final surfaceType = value['surfaceType']?.toString();
    if (surfaceType == null) {
      throw const FormatException('native player surface type is missing');
    }
    final texture = value['textureId'];
    final textureId = texture is int ? texture : null;
    final viewType = value['viewType']?.toString();
    if (surfaceType == 'windowsTexture' && textureId == null) {
      throw const FormatException('native Windows texture id is missing');
    }
    if (surfaceType == 'androidPlatformView' && viewType == null) {
      throw const FormatException('native Android view type is missing');
    }
    return NativeAvacaPlayerSurfaceInfo(
      sessionId: sessionId,
      surfaceType: surfaceType,
      textureId: textureId,
      viewType: viewType,
    );
  }
}

/// Renders the surface returned by `createSession`.  It contains no media
/// source logic; the platform plugin owns libmpv/Media3 and the QUIC adapter.
final class NativeAvacaPlayerSurface extends StatelessWidget {
  const NativeAvacaPlayerSurface({required this.surface, super.key});

  final NativeAvacaPlayerSurfaceInfo surface;

  @override
  Widget build(BuildContext context) {
    if (surface.surfaceType == 'windowsTexture' && surface.textureId != null) {
      return Texture(textureId: surface.textureId!);
    }
    if (surface.surfaceType == 'androidPlatformView' &&
        surface.viewType != null) {
      return AndroidView(
        viewType: surface.viewType!,
        creationParams: {'sessionId': surface.sessionId},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return const Center(child: Text('原生播放器 surface 尚未建立。'));
  }
}
