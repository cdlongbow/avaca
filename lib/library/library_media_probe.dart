import 'dart:async';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/media_information_session.dart';

import 'library_models.dart';

abstract interface class LibraryMediaProbe {
  Future<MediaProbeResult> probe(String filePath);

  void close();
}

class FfmpegKitMediaProbe implements LibraryMediaProbe {
  static const Duration _probeTimeout = Duration(seconds: 30);

  const FfmpegKitMediaProbe({
    this.backendVersion = 'ffmpeg_kit_flutter_new/4.6.2',
  });

  final String backendVersion;

  @override
  Future<MediaProbeResult> probe(String filePath) async {
    try {
      final completed = Completer<MediaInformationSession>();
      final session = await MediaInformationSession.create(
        [
          '-v',
          'error',
          '-hide_banner',
          '-print_format',
          'json',
          '-show_format',
          '-show_streams',
          '-show_chapters',
          '-i',
          filePath,
        ],
        (finished) {
          if (!completed.isCompleted) completed.complete(finished);
        },
      );
      try {
        await FFmpegKitConfig.asyncGetMediaInformationExecute(session).timeout(
          _probeTimeout,
          onTimeout: () => throw TimeoutException(
            'ffprobe launch timed out after ${_probeTimeout.inSeconds}s',
          ),
        );
      } on TimeoutException catch (error) {
        await session.cancel().catchError((_) {});
        return _error(error.message ?? 'ffprobe startup timed out');
      }
      final finished = await completed.future.timeout(
        _probeTimeout,
        onTimeout: () async {
          await session.cancel();
          throw TimeoutException(
            'ffprobe timed out after ${_probeTimeout.inSeconds}s',
          );
        },
      );
      final returnCode = await finished.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        return _error('ffprobe returned ${returnCode ?? 'no return code'}');
      }
      var information =
          finished.getMediaInformation() ?? session.getMediaInformation();
      if (information == null) {
        final sessions = await FFprobeKit.listMediaInformationSessions();
        for (final candidate in sessions) {
          if (candidate.getSessionId() == finished.getSessionId()) {
            information = candidate.getMediaInformation();
            break;
          }
        }
      }
      if (information == null) {
        return _error('ffprobe returned no media information');
      }
      final streams = information.getStreams();
      final videoIndex = streams.indexWhere(
        (stream) => stream.getType() == 'video',
      );
      if (videoIndex < 0) return _error('media has no video stream');
      final stream = streams[videoIndex];
      final frameRate = _parseFrameRate(
        stream.getAverageFrameRate() ?? stream.getRealFrameRate(),
      );
      final width = stream.getWidth();
      final height = stream.getHeight();
      if (width == null || height == null || width <= 0 || height <= 0) {
        return _error('video stream has no usable dimensions');
      }
      return MediaProbeResult(
        width: width,
        height: height,
        frameRateNumerator: frameRate?.$1,
        frameRateDenominator: frameRate?.$2,
        durationMs: _parseDurationMs(information.getDuration()),
        container: information.getFormat(),
        codec: stream.getCodec(),
        backend: 'ffprobe',
        backendVersion: backendVersion,
        selectedStreamIndex: stream.getIndex() ?? videoIndex,
      );
    } on Object catch (error) {
      return _error('${error.runtimeType}: $error');
    }
  }

  MediaProbeResult _error(String message) => MediaProbeResult(
    width: null,
    height: null,
    frameRateNumerator: null,
    frameRateDenominator: null,
    durationMs: null,
    container: null,
    codec: null,
    backend: 'ffprobe',
    backendVersion: backendVersion,
    selectedStreamIndex: null,
    error: message,
  );

  @override
  void close() {}
}

class UnavailableMediaProbe implements LibraryMediaProbe {
  const UnavailableMediaProbe({this.reason = 'media probing is unavailable'});

  final String reason;

  @override
  Future<MediaProbeResult> probe(String filePath) async => MediaProbeResult(
    width: null,
    height: null,
    frameRateNumerator: null,
    frameRateDenominator: null,
    durationMs: null,
    container: null,
    codec: null,
    backend: 'unavailable',
    backendVersion: 'none',
    selectedStreamIndex: null,
    error: reason,
  );

  @override
  void close() {}
}

/// Small testable helper for parsing ffprobe's rational frame-rate fields.
(int, int)? parseLibraryFrameRate(String? value) => _parseFrameRate(value);

(int, int)? _parseFrameRate(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final rational = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(raw);
  if (rational != null) {
    final numerator = int.tryParse(rational.group(1)!);
    final denominator = int.tryParse(rational.group(2)!);
    if (numerator != null &&
        denominator != null &&
        numerator > 0 &&
        denominator > 0) {
      final divisor = _gcd(numerator, denominator);
      return (numerator ~/ divisor, denominator ~/ divisor);
    }
    return null;
  }
  final decimal = double.tryParse(raw);
  if (decimal == null || !decimal.isFinite || decimal <= 0) return null;
  const scale = 1000000;
  final numerator = (decimal * scale).round();
  final divisor = _gcd(numerator, scale);
  return (numerator ~/ divisor, scale ~/ divisor);
}

int? _parseDurationMs(String? value) {
  final duration = double.tryParse(value?.trim() ?? '');
  if (duration == null || !duration.isFinite || duration < 0) return null;
  return (duration * 1000).round();
}

int _gcd(int left, int right) {
  var a = left.abs();
  var b = right.abs();
  while (b != 0) {
    final remainder = a % b;
    a = b;
    b = remainder;
  }
  return a == 0 ? 1 : a;
}
