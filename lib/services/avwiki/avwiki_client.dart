import 'dart:async';

import '../http_safety.dart';
import '../scrape/work_identity.dart';
import 'avwiki_html_parser.dart';
import 'avwiki_models.dart';
import 'avwiki_transport.dart';

final class AvWikiClient {
  AvWikiClient({
    required AvWikiTransport transport,
    AvWikiHtmlParser? parser,
    Uri? baseUri,
    this.requestDelay = const Duration(milliseconds: 250),
  }) : _transport = transport,
       _parser = parser ?? AvWikiHtmlParser(),
       _baseUri = baseUri ?? Uri.parse('https://av-wiki.net/') {
    _validateNavigationUri(_baseUri);
  }

  final AvWikiTransport _transport;
  final AvWikiHtmlParser _parser;
  final Uri _baseUri;
  final Duration requestDelay;
  Future<void> _requestTail = Future<void>.value();
  DateTime? _lastRequestAt;

  Future<AvWikiWorkDetails> fetchWorkDetails(Uri uri) async {
    _validateNavigationUri(uri);
    final source = await _get(uri);
    final details = _parser.parseWorkPage(source, pageUri: uri);
    if (details.code.trim().isEmpty) {
      throw AvWikiRequestException(
        uri,
        null,
        kind: AvWikiFailureKind.parserInvalid,
      );
    }
    return details;
  }

  Future<AvWikiWorkDetails> fetchWorkDetailsByCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(code, 'code', 'Must not be empty.');
    }
    final directUri = _directWorkUri(trimmed);
    try {
      final direct = await fetchWorkDetails(directUri);
      if (_codesMatch(trimmed, direct)) return direct;
    } on AvWikiRequestException catch (error) {
      if (error.kind == AvWikiFailureKind.blocked ||
          error.kind == AvWikiFailureKind.rateLimited ||
          error.kind == AvWikiFailureKind.timeout ||
          error.kind == AvWikiFailureKind.transport ||
          error.kind == AvWikiFailureKind.transientTransport) {
        rethrow;
      }
    }
    return _fetchWorkDetailsBySearch(trimmed);
  }

  Future<AvWikiWorkDetails> _fetchWorkDetailsBySearch(String code) async {
    final searchUri = _baseUri.replace(queryParameters: {'s': code});
    final source = await _get(searchUri);
    final uri = _parser.findWorkUriByCode(
      source,
      pageUri: searchUri,
      code: code,
    );
    if (uri == null) {
      throw AvWikiRequestException(
        searchUri,
        404,
        kind: AvWikiFailureKind.notFound,
      );
    }
    final details = await fetchWorkDetails(uri);
    if (!_codesMatch(code, details)) {
      throw AvWikiRequestException(
        uri,
        null,
        kind: AvWikiFailureKind.parserInvalid,
      );
    }
    return details;
  }

  void close() => _transport.close();

  bool _codesMatch(String expected, AvWikiWorkDetails details) {
    final expectedSurface = normalizeScrapeWorkCodeSurface(expected);
    final actualSurface = normalizeScrapeWorkCodeSurface(details.code);
    if (expectedSurface == null || actualSurface == null) return false;
    if (expectedSurface == actualSurface) return true;
    final identity = details.externalIdentity;
    final evidence = identity == null
        ? null
        : ScrapeWorkIdentityEvidence(
            canonicalCode: identity.canonicalCode,
            makerCode: identity.makerCode,
            manufacturer: identity.manufacturer,
            label: identity.label,
            series: identity.series,
            aliases: identity.aliases,
            platformIds: identity.platformIds,
          );
    if (scrapeWorkCodesEqual(expected, details.code, evidence: evidence)) {
      return true;
    }
    final expectedKey = scrapeWorkResolvedIdentityKey(
      rawCode: expected,
      externalIdentity: identity,
      fallback: 'expected:$expectedSurface',
    );
    final actualKey = scrapeWorkResolvedIdentityKey(
      rawCode: details.rawCode ?? details.code,
      externalIdentity: identity,
      fallback: 'actual:$actualSurface',
    );
    return expectedKey == actualKey;
  }

  Uri _directWorkUri(String code) {
    final safe = code.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]+'), '-');
    return _baseUri.resolve('${safe.replaceAll(RegExp(r'-+'), '-')}/');
  }

  Future<String> _get(Uri uri) {
    _validateNavigationUri(uri);
    final completer = Completer<String>();
    _requestTail = _requestTail.then<void>((_) async {
      try {
        final last = _lastRequestAt;
        if (last != null && requestDelay > Duration.zero) {
          final remaining = requestDelay - DateTime.now().difference(last);
          if (remaining > Duration.zero) await Future<void>.delayed(remaining);
        }
        _lastRequestAt = DateTime.now();
        completer.complete(await _transport.get(uri));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _validateNavigationUri(Uri uri) {
    final expectedPort = _baseUri.hasPort ? _baseUri.port : 443;
    final actualPort = uri.hasPort ? uri.port : 443;
    if (_baseUri.scheme != 'https' ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != _baseUri.host.toLowerCase() ||
        actualPort != expectedPort) {
      throw UnsafeHttpUriException(uri);
    }
  }
}
