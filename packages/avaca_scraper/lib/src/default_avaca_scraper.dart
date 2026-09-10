part of '../avaca_scraper.dart';

/// Optional lifecycle hook for a Server-owned scraper that owns network
/// resources.  The client never sees this interface.
abstract interface class CloseableAvacaScraper implements AvacaScraper {
  Future<void> close();
}

/// The default Server composition used by the Windows management app.
///
/// Each source is limited to HTTPS, an explicit host allow-list, bounded
/// response bodies, and bounded redirects.  A source returning a challenge,
/// malformed page, or transport failure is treated as unavailable and the
/// next source is tried.  The importer therefore records real metadata only;
/// it never invents a title from a filename.
final class DefaultAvacaScraper
    implements CloseableAvacaScraper, AvacaRichScraper {
  DefaultAvacaScraper({
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
    this.artworkCacheDirectory,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _timeout = timeout,
       _sources = <_DefaultAvacaSource>[
         _DefaultAvacaSource.avWiki(),
         _DefaultAvacaSource.avBase(),
         _DefaultAvacaSource.javBus(),
       ];

  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;
  final List<_DefaultAvacaSource> _sources;
  bool _closed = false;

  @override
  Future<AvacaWorkSummary> resolveWork(String code) async {
    if (_closed) {
      throw const AvacaScraperException(
        'scraper_closed',
        'the Server scraper is closed',
      );
    }
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw const AvacaScraperException(
        'invalid_work_code',
        'work code is empty',
      );
    }
    final composite = CompositeAvacaScraper(
      _sources
          .map((source) => source.asSource(client: _client, timeout: _timeout))
          .toList(growable: false),
    );
    return composite.resolveWork(normalized);
  }

  @override
  Future<AvacaWorkMetadata> resolveWorkDetails(String code) async {
    if (_closed) {
      throw const AvacaScraperException(
        'scraper_closed',
        'the Server scraper is closed',
      );
    }
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw const AvacaScraperException(
        'invalid_work_code',
        'work code is empty',
      );
    }
    final composite = CompositeAvacaScraper(
      _sources
          .map((source) => source.asSource(client: _client, timeout: _timeout))
          .toList(growable: false),
    );
    final details = await composite.resolveWorkDetails(normalized);
    final artwork = details.artwork;
    if (artwork == null || artwork.cachedPath != null) return details;
    _DefaultAvacaSource? source;
    for (final candidate in _sources) {
      if (candidate.allowedHosts.contains(artwork.uri.host.toLowerCase())) {
        source = candidate;
        break;
      }
    }
    if (source == null) return details;
    try {
      final response = await _SafeHtmlHttpClient(
        client: _client,
        allowedHosts: source.allowedHosts,
        timeout: _timeout,
      ).getBytes(artwork.uri);
      final contentType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          response.bytes.isEmpty ||
          contentType == null ||
          !contentType.startsWith('image/')) {
        return details;
      }
      final cacheRoot = Directory(
        artworkCacheDirectory ??
            '${Directory.systemTemp.path}${Platform.pathSeparator}avaca-server-artwork',
      );
      await cacheRoot.create(recursive: true);
      final assetId = 'asset.${_stableToken(artwork.uri.toString())}';
      final extension = _artworkExtension(
        response.headers['content-type'],
        artwork.uri.path,
      );
      final file = File(
        '${cacheRoot.path}${Platform.pathSeparator}$assetId$extension',
      );
      await file.writeAsBytes(response.bytes, flush: true);
      return details.copyWith(
        artwork: AvacaArtworkMetadata(
          uri: artwork.uri,
          mimeType: contentType,
          assetId: assetId,
          cachedPath: file.path,
          length: response.bytes.length,
        ),
      );
    } on Object {
      // Artwork is optional metadata.  A failed image fetch must not discard
      // the physical media row or the textual work details.
      return details;
    }
  }

  final String? artworkCacheDirectory;

  String _stableToken(String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash = (hash ^ unit) * 16777619 & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }

  String _artworkExtension(String? contentType, String path) {
    final type = contentType?.split(';').first.trim().toLowerCase();
    return switch (type) {
      'image/png' => '.png',
      'image/webp' => '.webp',
      'image/gif' => '.gif',
      'image/avif' => '.avif',
      _ when type == 'image/jpeg' || type == 'image/jpg' => '.jpg',
      _ => switch (path.toLowerCase().split('.').last) {
        'png' => '.png',
        'webp' => '.webp',
        'gif' => '.gif',
        _ => '.jpg',
      },
    };
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_ownsClient) _client.close();
  }
}

final class _DefaultAvacaSource {
  const _DefaultAvacaSource._({
    required this.id,
    required this.baseUri,
    required this.kind,
    required this.allowedHosts,
  });

  factory _DefaultAvacaSource.avWiki() => const _DefaultAvacaSource._(
    id: 'avwiki',
    baseUri: 'https://av-wiki.net/',
    kind: _DefaultSourceKind.avWiki,
    allowedHosts: <String>{'av-wiki.net', 'www.av-wiki.net'},
  );

  factory _DefaultAvacaSource.avBase() => const _DefaultAvacaSource._(
    id: 'avbase',
    baseUri: 'https://www.avbase.net/',
    kind: _DefaultSourceKind.avBase,
    allowedHosts: <String>{'www.avbase.net'},
  );

  factory _DefaultAvacaSource.javBus() => const _DefaultAvacaSource._(
    id: 'javbus',
    baseUri: 'https://www.javbus.com/',
    kind: _DefaultSourceKind.javBus,
    allowedHosts: <String>{'www.javbus.com'},
  );

  final String id;
  final String baseUri;
  final _DefaultSourceKind kind;
  final Set<String> allowedHosts;

  AvacaScrapeSource asSource({
    required http.Client client,
    required Duration timeout,
  }) => _HttpAvacaSource(
    id: id,
    baseUri: Uri.parse(baseUri),
    kind: kind,
    allowedHosts: allowedHosts,
    client: client,
    timeout: timeout,
  );
}

enum _DefaultSourceKind { avWiki, avBase, javBus }

final class _HttpAvacaSource
    implements AvacaScrapeSource, AvacaDetailedScrapeSource {
  _HttpAvacaSource({
    required this.id,
    required this.baseUri,
    required this.kind,
    required Set<String> allowedHosts,
    required http.Client client,
    required Duration timeout,
  }) : _http = _SafeHtmlHttpClient(
         client: client,
         allowedHosts: allowedHosts,
         timeout: timeout,
       );

  @override
  final String id;
  final Uri baseUri;
  final _DefaultSourceKind kind;
  final _SafeHtmlHttpClient _http;

  @override
  Future<AvacaWorkSummary?> fetchWork(String code) async {
    final details = await fetchWorkDetails(code);
    return details?.summary;
  }

  @override
  Future<AvacaWorkMetadata?> fetchWorkDetails(String code) async {
    final normalized = code.trim().toUpperCase();
    final pages = switch (kind) {
      _DefaultSourceKind.avWiki => <Uri>[
        baseUri.resolve('${normalized.toLowerCase()}/'),
        baseUri.replace(queryParameters: <String, String>{'s': normalized}),
      ],
      _DefaultSourceKind.avBase => <Uri>[
        baseUri.replace(
          path: '${baseUri.path}works',
          queryParameters: <String, String>{'q': normalized},
        ),
      ],
      _DefaultSourceKind.javBus => <Uri>[baseUri.resolve('$normalized/')],
    };

    for (final page in pages) {
      final response = await _http.get(page);
      if (response.statusCode == 404) continue;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AvacaScraperException(
          '${id}_http_${response.statusCode}',
          '$id returned HTTP ${response.statusCode}',
        );
      }
      final document = html.parse(response.body);
      final direct = _detailsFromDocument(document, response.uri, normalized);
      if (direct != null) return direct;
      final detailUris = _detailUris(document, response.uri, normalized);
      for (final detailUri in detailUris) {
        final detail = await _http.get(detailUri);
        if (detail.statusCode == 404) continue;
        if (detail.statusCode < 200 || detail.statusCode >= 300) {
          throw AvacaScraperException(
            '${id}_detail_http_${detail.statusCode}',
            '$id detail page returned HTTP ${detail.statusCode}',
          );
        }
        final details = _detailsFromDocument(
          html.parse(detail.body),
          detail.uri,
          normalized,
        );
        if (details != null) return details;
      }
      if (kind == _DefaultSourceKind.javBus) break;
    }
    return null;
  }

  AvacaWorkMetadata? _detailsFromDocument(
    dom.Document document,
    Uri pageUri,
    String normalizedCode,
  ) {
    final summary = _summaryFromDocument(document, normalizedCode);
    if (summary == null) return null;
    final body = document.body;
    final description = _firstText(<String?>[
      document.querySelector('[itemprop="description"]')?.text,
      document.querySelector('.description')?.text,
      document.querySelector('meta[name="description"]')?.attributes['content'],
    ]);
    final releaseDate = _firstText(<String?>[
      document
          .querySelector('[itemprop="datePublished"]')
          ?.attributes['content'],
      document.querySelector('[itemprop="datePublished"]')?.text,
      document.querySelector('time')?.attributes['datetime'],
    ]);
    final performers = <AvacaPerformerMetadata>[];
    for (final element in document.querySelectorAll(
      '[itemprop="actor"], .actor a, .performer a, .star a',
    )) {
      final name = _clean(element.text);
      if (name.isEmpty || performers.any((item) => item.displayName == name)) {
        continue;
      }
      final href = element.attributes['href'];
      performers.add(
        AvacaPerformerMetadata(
          performerId: AvacaActressId(
            'performer.${_stableToken(href ?? name)}',
          ),
          displayName: name.length > 256 ? name.substring(0, 256) : name,
          externalId: href,
        ),
      );
      if (performers.length == 128) break;
    }
    final image = _firstImage(document, pageUri);
    return AvacaWorkMetadata(
      summary: summary,
      description: description,
      releaseDate: releaseDate,
      performers: performers,
      artwork: image == null ? null : AvacaArtworkMetadata(uri: image),
      source: id,
      sourceUri: pageUri,
      diagnostics: body == null
          ? const <String>['empty_body']
          : const <String>[],
    );
  }

  Uri? _firstImage(dom.Document document, Uri pageUri) {
    final candidates = <String?>[
      document
          .querySelector('meta[property="og:image"]')
          ?.attributes['content'],
      document.querySelector('img[src]')?.attributes['src'],
    ];
    for (final candidate in candidates) {
      final value = candidate?.trim();
      if (value == null || value.isEmpty) continue;
      try {
        final uri = pageUri.resolve(value);
        if (uri.scheme == 'https' && uri.host == pageUri.host) return uri;
      } on FormatException {
        // Ignore malformed artwork candidates and retain metadata.
      }
    }
    return null;
  }

  String? _firstText(Iterable<String?> candidates) {
    for (final candidate in candidates) {
      final value = _clean(candidate ?? '');
      if (value.isNotEmpty) {
        return value.length > 4096 ? value.substring(0, 4096) : value;
      }
    }
    return null;
  }

  String _stableToken(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return 'unknown';
    var hash = 2166136261;
    for (final unit in normalized.codeUnits) {
      hash = (hash ^ unit) * 16777619 & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }

  AvacaWorkSummary? _summaryFromDocument(
    dom.Document document,
    String normalizedCode,
  ) {
    final visibleText = _clean(document.body?.text ?? '');
    final pageText = visibleText.toUpperCase();
    if (_looksLikeChallenge(pageText)) {
      throw AvacaScraperException(
        '${id}_blocked',
        '$id returned a verification or block page',
      );
    }
    if (!pageText.contains(normalizedCode)) return null;

    final candidates = <String?>[
      document
          .querySelector('meta[property="og:title"]')
          ?.attributes['content'],
      document
          .querySelector('meta[name="twitter:title"]')
          ?.attributes['content'],
      document.querySelector('h1')?.text,
      document.querySelector('h3')?.text,
      document.querySelector('title')?.text,
    ];
    for (final candidate in candidates) {
      final title = _titleFromCandidate(candidate, normalizedCode);
      if (title == null) continue;
      return AvacaWorkSummary(
        workId: AvacaWorkId('work.${normalizedCode.toLowerCase()}'),
        code: normalizedCode,
        title: title,
      );
    }
    return null;
  }

  List<Uri> _detailUris(
    dom.Document document,
    Uri pageUri,
    String normalizedCode,
  ) {
    final results = <Uri>[];
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      if (href == null || href.trim().isEmpty) continue;
      final candidate = pageUri.resolve(href);
      if (candidate.host.toLowerCase() != baseUri.host.toLowerCase()) {
        continue;
      }
      final haystack = '${anchor.text} ${candidate.path}'.toUpperCase();
      if (!haystack.contains(normalizedCode)) continue;
      if (!results.contains(candidate)) results.add(candidate);
      if (results.length == 3) break;
    }
    return results;
  }

  String? _titleFromCandidate(String? raw, String normalizedCode) {
    final value = _clean(raw ?? '');
    if (value.isEmpty) return null;
    var title = value
        .replaceFirst(
          RegExp(
            '^${RegExp.escape(normalizedCode)}\\s*[-|:：]?\\s*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(
          RegExp(
            r'\s*[-|:：]?\s*' + RegExp.escape(normalizedCode) + r'$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (title.isEmpty || title.toUpperCase() == normalizedCode) return null;
    final generic = <String>{'AV-WIKI', 'AV WIKI', 'AVBASE', 'JAVBUS'};
    if (generic.contains(title.toUpperCase())) return null;
    if (title.length > 512) title = title.substring(0, 512).trim();
    return title.isEmpty ? null : title;
  }

  bool _looksLikeChallenge(String text) =>
      text.contains('JUST A MOMENT') ||
      text.contains('ACCESS DENIED') ||
      text.contains('VERIFY YOU ARE HUMAN') ||
      text.contains('CF-CHL-') ||
      text.contains('SECURITY CHECK');
}

final class _SafeHtmlResponse {
  const _SafeHtmlResponse({
    required this.statusCode,
    required this.body,
    required this.bytes,
    required this.uri,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final List<int> bytes;
  final Uri uri;
  final Map<String, String> headers;
}

final class _SafeHtmlHttpClient {
  _SafeHtmlHttpClient({
    required this.client,
    required Set<String> allowedHosts,
    required this.timeout,
  }) : allowedHosts = allowedHosts
           .map((host) => host.trim().toLowerCase())
           .toSet();

  final http.Client client;
  final Set<String> allowedHosts;
  final Duration timeout;
  static const int maxBytes = 5 * 1024 * 1024;
  static const int maxRedirects = 3;

  Future<_SafeHtmlResponse> get(Uri uri) async {
    final stopwatch = Stopwatch()..start();
    var current = uri;
    for (var redirect = 0; redirect <= maxRedirects; redirect++) {
      _validate(current);
      final request = http.Request('GET', current)..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(_remaining(stopwatch));
      if (_isRedirect(response.statusCode)) {
        await response.stream.drain<void>();
        final location = response.headers['location'];
        if (location == null || redirect == maxRedirects) {
          throw AvacaScraperException(
            'scraper_redirect_invalid',
            'scraper redirect is missing or exceeds the safety limit',
          );
        }
        current = current.resolve(location);
        continue;
      }
      final declaredLength = response.contentLength;
      if (declaredLength != null && declaredLength > maxBytes) {
        throw AvacaScraperException(
          'scraper_response_too_large',
          'scraper response exceeds the safety limit',
        );
      }
      final bytes = await _readBounded(response, stopwatch);
      return _SafeHtmlResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes, allowMalformed: true),
        bytes: bytes,
        uri: current,
        headers: response.headers,
      );
    }
    throw const AvacaScraperException(
      'scraper_redirect_invalid',
      'scraper redirect is invalid',
    );
  }

  Future<_SafeHtmlResponse> getBytes(Uri uri) => get(uri);

  Future<List<int>> _readBounded(
    http.StreamedResponse response,
    Stopwatch stopwatch,
  ) async {
    final builder = BytesBuilder(copy: false);
    var received = 0;
    final iterator = StreamIterator<List<int>>(response.stream);
    try {
      while (await iterator.moveNext().timeout(_remaining(stopwatch))) {
        final chunk = iterator.current;
        received += chunk.length;
        if (received > maxBytes) {
          throw AvacaScraperException(
            'scraper_response_too_large',
            'scraper response exceeds the safety limit',
          );
        }
        builder.add(chunk);
      }
    } finally {
      await iterator.cancel();
    }
    return builder.takeBytes();
  }

  Duration _remaining(Stopwatch stopwatch) {
    final remaining = timeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('scraper request exceeded $timeout');
    }
    return remaining;
  }

  void _validate(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !allowedHosts.contains(uri.host.toLowerCase())) {
      throw AvacaScraperException(
        'scraper_uri_not_allowed',
        'scraper navigation URI is not allowed',
      );
    }
  }

  bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;
}

String _clean(String value) => value.replaceAll(RegExp(r'\\s+'), ' ').trim();
