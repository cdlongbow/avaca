import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../http_safety.dart';
import 'avwiki_models.dart';

abstract interface class AvWikiTransport {
  Future<String> get(Uri uri);
}

extension AvWikiTransportClose on AvWikiTransport {
  void close() {
    final transport = this;
    if (transport is HttpAvWikiTransport) transport.close();
  }
}

/// HTTPS-only AV-Wiki transport with an explicit host allow-list, bounded
/// bodies, bounded redirects, retry classification, and polite retry delay.
final class HttpAvWikiTransport implements AvWikiTransport {
  HttpAvWikiTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.maxAttempts = 2,
    this.retryDelay = const Duration(milliseconds: 400),
    Set<String> allowedHosts = const {'av-wiki.net', 'www.av-wiki.net'},
    String? initialCookieHeader,
  }) : assert(maxAttempts > 0),
       _fetcher = SafeHttpFetcher(
         client: client,
         allowedHosts: allowedHosts,
         timeout: timeout,
         maxBytes: 5 * 1024 * 1024,
         maxRedirects: 3,
         initialCookieHeader: initialCookieHeader,
       );

  final SafeHttpFetcher _fetcher;
  final Duration timeout;
  final int maxAttempts;
  final Duration retryDelay;

  @override
  Future<String> get(Uri uri) async {
    final response = await _getResponse(uri);
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<SafeHttpResponse> _getResponse(Uri uri) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      var attemptDelay = retryDelay;
      try {
        final response = await _fetcher.get(uri);
        if (_looksBlocked(response)) {
          throw AvWikiRequestException(
            uri,
            response.statusCode,
            kind: AvWikiFailureKind.blocked,
          );
        }
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        if (!_isTransient(response.statusCode) || attempt == maxAttempts) {
          throw AvWikiRequestException(
            uri,
            response.statusCode,
            kind: _kindForStatus(response.statusCode),
          );
        }
        attemptDelay = _retryDelayFor(response);
      } on AvWikiRequestException catch (error) {
        if (error.kind == AvWikiFailureKind.blocked ||
            error.kind == AvWikiFailureKind.rateLimited ||
            error.kind == AvWikiFailureKind.notFound ||
            error.kind == AvWikiFailureKind.parserInvalid ||
            attempt == maxAttempts) {
          rethrow;
        }
      } on TimeoutException {
        if (attempt == maxAttempts) {
          throw AvWikiRequestException(
            uri,
            null,
            kind: AvWikiFailureKind.timeout,
          );
        }
      } on http.ClientException {
        if (attempt == maxAttempts) {
          throw AvWikiRequestException(
            uri,
            null,
            kind: AvWikiFailureKind.transport,
          );
        }
      } on OSError {
        if (attempt == maxAttempts) {
          throw AvWikiRequestException(
            uri,
            null,
            kind: AvWikiFailureKind.transport,
          );
        }
      } on UnsafeHttpUriException {
        rethrow;
      } on HttpBodyTooLargeException {
        throw AvWikiRequestException(
          uri,
          null,
          kind: AvWikiFailureKind.parserInvalid,
        );
      }
      if (attemptDelay > Duration.zero) {
        await Future<void>.delayed(attemptDelay);
      }
    }
    throw StateError('Unreachable AV-Wiki retry state.');
  }

  void close() => _fetcher.close();

  bool _isTransient(int statusCode) {
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }

  Duration _retryDelayFor(SafeHttpResponse response) {
    final raw = response.headers['retry-after']?.trim();
    final seconds = raw == null ? null : double.tryParse(raw);
    if (seconds == null || seconds.isNegative) return retryDelay;
    final serverDelay = Duration(milliseconds: (seconds * 1000).ceil());
    return serverDelay > retryDelay ? serverDelay : retryDelay;
  }

  AvWikiFailureKind _kindForStatus(int statusCode) {
    if (statusCode == 404) return AvWikiFailureKind.notFound;
    if (statusCode == 408 || statusCode >= 500) {
      return AvWikiFailureKind.transientTransport;
    }
    if (statusCode == 429) return AvWikiFailureKind.rateLimited;
    if (statusCode == 403) return AvWikiFailureKind.blocked;
    return AvWikiFailureKind.transport;
  }

  bool _looksBlocked(SafeHttpResponse response) {
    if (response.statusCode == 403) return true;
    final body = utf8
        .decode(response.bodyBytes, allowMalformed: true)
        .toLowerCase();
    return body.contains('access denied') ||
        body.contains('just a moment') ||
        body.contains('cf-chl-') ||
        body.contains('cloudflare ray id');
  }
}
