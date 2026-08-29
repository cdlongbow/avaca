enum PlayerErrorType {
  backendInitialization,
  mediaNotFound,
  mediaOpenFailed,
  invalidSource,
  unsupportedMedia,
  demuxFailure,
  decoderFailure,
  rendererFailure,
  audioFailure,
  subtitleFailure,
  seekFailure,
  remoteRequestFailure,
  lifecycleFailure,
  unknown,
}

final class PlayerError {
  const PlayerError({
    required this.type,
    required this.localizedMessageKey,
    required this.diagnosticCode,
    this.recoverable = false,
  });
  final PlayerErrorType type;
  final String localizedMessageKey;
  final String diagnosticCode;
  final bool recoverable;

  String get sanitizedDiagnosticCode {
    final sanitized = diagnosticCode.replaceAll(
      RegExp(r'[^A-Za-z0-9_.-]'),
      '_',
    );
    if (sanitized.isEmpty) return 'unknown';
    return sanitized.substring(0, sanitized.length.clamp(0, 64));
  }

  @override
  String toString() =>
      'PlayerError(type: $type, key: $localizedMessageKey, '
      'code: $sanitizedDiagnosticCode, recoverable: $recoverable)';

  @override
  bool operator ==(Object other) =>
      other is PlayerError &&
      other.type == type &&
      other.localizedMessageKey == localizedMessageKey &&
      other.diagnosticCode == diagnosticCode &&
      other.recoverable == recoverable;

  @override
  int get hashCode =>
      Object.hash(type, localizedMessageKey, diagnosticCode, recoverable);
}
