import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../http_safety.dart';
import 'javbus_html_parser.dart';
import 'javbus_models.dart';
import 'javbus_verification.dart';
import 'prefix_exclusion.dart';
import 'work_image_downloader.dart';

abstract interface class JavBusTransport {
  Future<String> get(Uri uri);
}

abstract interface class JavBusBinarySession {
  Future<BinaryResponse> getBinary(Uri uri);
}

class HttpJavBusTransport implements JavBusTransport, JavBusBinarySession {
  HttpJavBusTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.maxAttempts = 2,
    this.retryDelay = const Duration(milliseconds: 300),
    Set<String> allowedHosts = const {'www.javbus.com'},
    String? initialCookieHeader,
    this.verificationHandler,
  }) : assert(maxAttempts > 0),
       _fetcher = SafeHttpFetcher(
         client: client,
         allowedHosts: allowedHosts,
         timeout: timeout,
         maxBytes: 5 * 1024 * 1024,
         initialCookieHeader: initialCookieHeader,
       );

  final SafeHttpFetcher _fetcher;
  final Duration timeout;
  final int maxAttempts;
  final Duration retryDelay;
  final JavBusVerificationHandler? verificationHandler;

  String get cookieHeader => _fetcher.cookieHeader;

  @override
  Future<String> get(Uri uri) async {
    final response = await _getResponse(uri);
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  @override
  Future<BinaryResponse> getBinary(Uri uri) async {
    final response = await _getResponse(
      uri,
      referer: uri.replace(path: '/', query: null, fragment: null),
    );
    return BinaryResponse(
      statusCode: response.statusCode,
      bodyBytes: response.bodyBytes,
    );
  }

  Future<SafeHttpResponse> _getResponse(Uri uri, {Uri? referer}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        var response = await _fetcher.get(uri, referer: referer);
        for (
          var verificationRound = 0;
          _isVerificationPage(response.finalUri) && verificationRound < 3;
          verificationRound++
        ) {
          final source = utf8.decode(response.bodyBytes, allowMalformed: true);
          final challenge = JavBusVerificationChallenge.parse(
            source,
            pageUri: response.finalUri,
          );
          final handler = verificationHandler;
          if (challenge == null || handler == null) {
            throw const JavBusVerificationCancelledException();
          }
          final answers = await handler(challenge);
          if (answers == null) {
            throw const JavBusVerificationCancelledException();
          }
          await _fetcher.postForm(challenge.submitUri, {
            ...challenge.hiddenFields,
            ...challenge.submitFields,
            ...answers,
          });
          response = await _fetcher.get(uri, referer: referer);
        }
        if (_isVerificationPage(response.finalUri)) {
          throw const JavBusVerificationCancelledException();
        }
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        if (!_isTransient(response.statusCode) || attempt == maxAttempts) {
          throw JavBusRequestException(uri, response.statusCode);
        }
      } on TimeoutException {
        if (attempt == maxAttempts) {
          rethrow;
        }
      } on http.ClientException {
        if (attempt == maxAttempts) {
          rethrow;
        }
      }
      if (retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay);
      }
    }
    throw StateError('Unreachable JavBus retry state.');
  }

  void close() {
    _fetcher.close();
  }

  bool _isTransient(int statusCode) {
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }

  bool _isVerificationPage(Uri uri) {
    return uri.path.contains('/doc/driver-verify');
  }
}

class JavBusRequestException implements Exception {
  const JavBusRequestException(this.uri, this.statusCode);

  final Uri uri;
  final int statusCode;

  @override
  String toString() => 'JavBus request failed ($statusCode): $uri';
}

class JavBusClient {
  JavBusClient({
    required JavBusTransport transport,
    JavBusHtmlParser? parser,
    Uri? baseUri,
    this.maxPages = 100,
  }) : _transport = transport,
       _parser = parser ?? JavBusHtmlParser(),
       _baseUri = baseUri ?? Uri.parse('https://www.javbus.com/') {
    if (maxPages < 1) {
      throw ArgumentError.value(maxPages, 'maxPages', 'Must be positive.');
    }
    _validateNavigationUri(_baseUri);
  }

  final JavBusTransport _transport;
  final JavBusHtmlParser _parser;
  final Uri _baseUri;
  final int maxPages;

  Future<List<JavBusActressSearchResult>> searchActresses(String name) async {
    final uri = _baseUri.replace(
      pathSegments: [
        ..._baseUri.pathSegments.where((part) => part.isNotEmpty),
        'searchstar',
        name.trim(),
      ],
    );
    final source = await _transport.get(uri);
    return _parser.parseActressSearchResults(source, pageUri: uri);
  }

  Future<JavBusActressPage> fetchActressPage(Uri uri) async {
    _validateNavigationUri(uri);
    final source = await _transport.get(uri);
    return _parser.parseActressPage(source, pageUri: uri);
  }

  Future<JavBusWorkDetails> fetchWorkDetails(Uri uri) async {
    _validateNavigationUri(uri);
    final source = await _transport.get(uri);
    return _parser.parseWorkPage(source, pageUri: uri);
  }

  Future<List<JavBusWorkSummary>> fetchAllActressWorks(
    Uri actressUri, {
    PrefixExclusion? exclusions,
    bool Function()? isCancelled,
    JavBusActressPage? firstPage,
  }) async {
    _validateNavigationUri(actressUri);
    if (isCancelled?.call() ?? false) {
      return const [];
    }
    final resolvedFirstPage = firstPage ?? await fetchActressPage(actressUri);
    if (resolvedFirstPage.pageCount > maxPages) {
      throw JavBusPageLimitException(resolvedFirstPage.pageCount, maxPages);
    }
    final result = <JavBusWorkSummary>[];
    final codes = <String>{};

    void append(Iterable<JavBusWorkSummary> works) {
      for (final work in works) {
        final normalizedCode = work.code.trim().toUpperCase();
        if ((exclusions?.matches(normalizedCode) ?? false) ||
            !codes.add(normalizedCode)) {
          continue;
        }
        result.add(work);
      }
    }

    append(resolvedFirstPage.works);
    for (var page = 2; page <= resolvedFirstPage.pageCount; page++) {
      if (isCancelled?.call() ?? false) {
        break;
      }
      final pageUri = Uri.parse(
        '${actressUri.toString().replaceFirst(RegExp(r'/$'), '')}/$page',
      );
      append((await fetchActressPage(pageUri)).works);
    }
    return result;
  }

  void close() {
    final transport = _transport;
    if (transport is HttpJavBusTransport) {
      transport.close();
    }
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

class JavBusPageLimitException implements Exception {
  const JavBusPageLimitException(this.actual, this.maximum);

  final int actual;
  final int maximum;

  @override
  String toString() => 'JavBus page count $actual exceeds limit $maximum.';
}
