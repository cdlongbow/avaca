import 'dart:async';

import 'package:avaca_player_native/avaca_player_native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/player_diagnostics.dart';
import '../models/player_error.dart';
import '../models/player_launch_request.dart';
import '../models/player_phase.dart';
import '../models/player_subtitle_track.dart';
import 'player_platform.dart';

/// Dart bridge for the private native player plugin.
///
/// The event channel is shared by all sessions and filtered by session id;
/// source headers are sent only in the open method call and never copied into
/// diagnostics or event payloads.
final class MethodChannelPlayerPlatform implements PlayerPlatform {
  MethodChannelPlayerPlatform({MethodChannel? control, EventChannel? events})
    : _control = control ?? AvacaPlayerNative.control,
      _rawEvents = (events ?? AvacaPlayerNative.events)
          .receiveBroadcastStream();

  final MethodChannel _control;
  final Stream<dynamic> _rawEvents;

  @override
  Future<PlayerPlatformSession> createSession(String sessionId) async {
    final surface = await _createSurface(sessionId);
    return MethodChannelPlayerPlatformSession(
      sessionId: sessionId,
      control: _control,
      rawEvents: _rawEvents,
      surface: surface,
    );
  }

  Future<PlayerSurfaceDescriptor> _createSurface(String sessionId) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.windows)) {
      return const PlayerSurfaceDescriptor(type: PlayerSurfaceType.none);
    }
    final raw = await _control.invokeMethod<dynamic>('createSession', {
      'sessionId': sessionId,
    });
    return _decodeSurfaceDescriptor(raw, sessionId);
  }
}

final class MethodChannelPlayerPlatformSession
    implements PlayerPlatformSession {
  MethodChannelPlayerPlatformSession({
    required this.sessionId,
    required MethodChannel control,
    required Stream<dynamic> rawEvents,
    required this.surface,
  }) : _control = control,
       _events = rawEvents
           .where((event) => _eventSessionId(event) == sessionId)
           .map(_decodeEvent)
           .where((event) => event != null)
           .cast<PlayerPlatformEvent>();

  final MethodChannel _control;
  final Stream<PlayerPlatformEvent> _events;
  bool _closed = false;

  @override
  final String sessionId;

  @override
  final PlayerSurfaceDescriptor surface;

  @override
  Stream<PlayerPlatformEvent> get events => _events;

  @override
  Future<void> open(PlayerLaunchRequest request) {
    return _invoke('open', <String, Object?>{'request': request.toJson()});
  }

  @override
  Future<void> play() => _invoke('play');

  @override
  Future<void> pause() => _invoke('pause');

  @override
  Future<void> seek(Duration position, {int generation = 0}) {
    return _invoke('seek', <String, Object?>{
      'positionMs': position.inMilliseconds,
      'seekGeneration': generation,
    });
  }

  @override
  Future<void> setSpeed(double speed) {
    return _invoke('setSpeed', <String, Object?>{'speed': speed});
  }

  @override
  Future<void> selectSubtitle(String? trackId) {
    return _invoke('selectSubtitle', <String, Object?>{'trackId': trackId});
  }

  @override
  Future<void> setFullscreen(bool fullscreen) {
    return _invoke('setFullscreen', <String, Object?>{
      'fullscreen': fullscreen,
    });
  }

  @override
  Future<PlayerDiagnostics> getDiagnostics() async {
    final raw = await _invoke('getDiagnostics');
    if (raw is! Map) {
      return PlayerDiagnostics(sessionId: sessionId, lastEvent: 'native');
    }
    return _decodeDiagnostics(sessionId, _asMap(raw));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _invoke('close');
    } on MissingPluginException {
      // A platform without the private plugin can still dispose the Dart
      // session cleanly; open/play calls retain their real platform error.
    }
  }

  Future<dynamic> _invoke(String method, [Map<String, Object?>? arguments]) {
    if (_closed && method != 'close') {
      return Future<dynamic>.error(StateError('Player session is closed.'));
    }
    final payload = <String, Object?>{'sessionId': sessionId};
    if (arguments != null) payload.addAll(arguments);
    return _control.invokeMethod<dynamic>(method, payload);
  }
}

String? _eventSessionId(dynamic event) {
  if (event is! Map) return null;
  return event['sessionId']?.toString();
}

PlayerPlatformEvent? _decodeEvent(dynamic raw) {
  if (raw is! Map) return null;
  final event = _asMap(raw);
  final sessionId = event['sessionId']?.toString();
  final sequence = _asInt(event['sequence']);
  if (sessionId == null || sequence == null) return null;

  if (event['type'] == 'error') {
    return PlayerPlatformErrorEvent(
      sessionId: sessionId,
      sequence: sequence,
      error: PlayerError(
        type: _errorType(event['errorType']),
        localizedMessageKey:
            event['localizedMessageKey']?.toString() ?? 'playerErrorUnknown',
        diagnosticCode: event['diagnosticCode']?.toString() ?? 'native_error',
        recoverable: event['recoverable'] == true,
      ),
    );
  }
  if (event['type'] != 'state') return null;

  final tracks = event['tracks'];
  return PlayerPlatformStateEvent(
    sessionId: sessionId,
    sequence: sequence,
    phase: _phase(event['phase']),
    position: _duration(event['positionMs']),
    duration: _duration(event['durationMs']),
    bufferedPosition: _duration(event['bufferedPositionMs']),
    playing: _asBoolOrNull(event['playing']),
    buffering: _asBoolOrNull(event['buffering']),
    completed: _asBoolOrNull(event['completed']),
    tracks: tracks is List
        ? tracks
              .map(_decodeSubtitleTrack)
              .whereType<PlayerSubtitleTrack>()
              .toList()
        : null,
    selectedSubtitleTrackId: event['selectedSubtitleTrackId']?.toString(),
    subtitleSelectionChanged: event['subtitleSelectionChanged'] == true,
    speed: _asDouble(event['speed']),
    fullscreen: _asBoolOrNull(event['fullscreen']),
    seekGeneration: _asInt(event['seekGeneration']),
    diagnostics: event['diagnostics'] is Map
        ? _decodeDiagnostics(sessionId, _asMap(event['diagnostics'] as Map))
        : null,
  );
}

PlayerSubtitleTrack? _decodeSubtitleTrack(dynamic raw) {
  if (raw is! Map) return null;
  final value = _asMap(raw);
  final id = value['id']?.toString();
  if (id == null || id.isEmpty) return null;
  final uriValue = value['uri']?.toString();
  return PlayerSubtitleTrack(
    id: id,
    title: value['title']?.toString(),
    language: value['language']?.toString(),
    format: switch (value['format']?.toString().toLowerCase()) {
      'ass' => PlayerSubtitleFormat.ass,
      'ssa' => PlayerSubtitleFormat.ssa,
      _ => PlayerSubtitleFormat.other,
    },
    uri: uriValue == null
        ? Uri.parse('native://subtitle/$id')
        : Uri.parse(uriValue),
  );
}

PlayerDiagnostics _decodeDiagnostics(
  String sessionId,
  Map<Object?, Object?> value,
) {
  final values = value['values'];
  return PlayerDiagnostics(
    sessionId: value['sessionId']?.toString() ?? sessionId,
    lastEvent: value['lastEvent']?.toString(),
    droppedEvents: _asInt(value['droppedEvents']) ?? 0,
    values: values is Map
        ? <String, String>{
            for (final entry in values.entries)
              entry.key.toString(): entry.value.toString(),
          }
        : const <String, String>{},
  );
}

Map<Object?, Object?> _asMap(Map value) => Map<Object?, Object?>.from(value);

Duration? _duration(dynamic value) {
  final milliseconds = _asInt(value);
  return milliseconds == null ? null : Duration(milliseconds: milliseconds);
}

PlayerPhase? _phase(dynamic value) {
  final name = value?.toString();
  for (final phase in PlayerPhase.values) {
    if (phase.name == name) return phase;
  }
  return null;
}

PlayerErrorType _errorType(dynamic value) {
  final name = value?.toString();
  for (final type in PlayerErrorType.values) {
    if (type.name == name) return type;
  }
  return PlayerErrorType.unknown;
}

int? _asInt(dynamic value) => value is num ? value.toInt() : null;

double? _asDouble(dynamic value) => value is num ? value.toDouble() : null;

bool? _asBoolOrNull(dynamic value) => value is bool ? value : null;

PlayerSurfaceDescriptor _decodeSurfaceDescriptor(
  dynamic raw,
  String sessionId,
) {
  if (raw is! Map) {
    throw PlatformException(
      code: 'PLAYER_SURFACE_INVALID',
      message: 'The native player returned no surface descriptor.',
    );
  }
  final value = _asMap(raw);
  switch (value['surfaceType']?.toString()) {
    case 'androidPlatformView':
      final viewType = value['viewType']?.toString();
      if (viewType == null || viewType.isEmpty) {
        throw PlatformException(
          code: 'PLAYER_SURFACE_INVALID',
          message: 'The Android player returned no view type.',
        );
      }
      final params = value['creationParams'];
      return PlayerSurfaceDescriptor(
        type: PlayerSurfaceType.androidPlatformView,
        viewType: viewType,
        creationParams: params is Map
            ? <String, Object?>{
                for (final entry in params.entries)
                  entry.key.toString(): entry.value,
              }
            : <String, Object?>{'sessionId': sessionId},
      );
    case 'windowsTexture':
      final textureId = _asInt(value['textureId']);
      if (textureId == null || textureId < 0) {
        throw PlatformException(
          code: 'PLAYER_SURFACE_INVALID',
          message: 'The Windows player returned no texture id.',
        );
      }
      return PlayerSurfaceDescriptor(
        type: PlayerSurfaceType.windowsTexture,
        textureId: textureId,
      );
    case 'none':
      return const PlayerSurfaceDescriptor(type: PlayerSurfaceType.none);
    default:
      throw PlatformException(
        code: 'PLAYER_SURFACE_INVALID',
        message: 'The native player returned an unknown surface type.',
      );
  }
}
