sealed class PlayerMediaSource {
  const PlayerMediaSource();
  String get kind;

  Map<String, Object?> toJson({bool redactSecrets = false});

  @override
  String toString() => 'PlayerMediaSource($kind)';
}

final class LocalPlayerMediaSource extends PlayerMediaSource {
  const LocalPlayerMediaSource(this.path)
    : assert(path != '', 'A local media path is required.');
  final String path;

  @override
  String get kind => 'local';

  @override
  Map<String, Object?> toJson({bool redactSecrets = false}) => {
    'kind': kind,
    'path': path,
  };

  @override
  String toString() => 'LocalPlayerMediaSource(path: <local-file>)';
}

final class RemotePlayerMediaSource extends PlayerMediaSource {
  RemotePlayerMediaSource({
    required this.uri,
    Map<String, String> headers = const {},
    this.contentLength,
    this.mimeType,
  }) : headers = Map.unmodifiable(headers);
  final Uri uri;
  final Map<String, String> headers;
  final int? contentLength;
  final String? mimeType;

  Map<String, String> get sanitizedHeaders => Map.unmodifiable({
    for (final entry in headers.entries)
      entry.key: _sensitive(entry.key) ? '<redacted>' : entry.value,
  });

  Uri get sanitizedUri => Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  );

  static bool _sensitive(String key) => RegExp(
    r'(authorization|cookie|token|secret|password|api[-_]?key)',
    caseSensitive: false,
  ).hasMatch(key);

  @override
  String get kind => 'remote';

  @override
  Map<String, Object?> toJson({bool redactSecrets = false}) => {
    'kind': kind,
    'uri': (redactSecrets ? sanitizedUri : uri).toString(),
    'headers': Map<String, String>.unmodifiable(
      redactSecrets ? sanitizedHeaders : headers,
    ),
    'contentLength': contentLength,
    'mimeType': mimeType,
  };

  @override
  String toString() =>
      'RemotePlayerMediaSource(uri: $sanitizedUri, headers: '
      '$sanitizedHeaders, contentLength: $contentLength, mimeType: $mimeType)';
}
