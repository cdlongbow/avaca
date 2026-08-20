import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../http_safety.dart';
import 'avbase_models.dart';

abstract interface class AvBaseTransport {
  Future<String> get(Uri uri);
}

final class HttpAvBaseTransport implements AvBaseTransport {
  HttpAvBaseTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.maxAttempts = 2,
    this.retryDelay = const Duration(milliseconds: 300),
    Set<String> allowedHosts = const {'www.avbase.net'},
    String? initialCookieHeader,
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

  String get cookieHeader => _fetcher.cookieHeader;

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
          throw AvBaseRequestException(
            uri,
            response.statusCode,
            kind: AvBaseFailureKind.blocked,
          );
        }
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        if (!_isTransient(response.statusCode) || attempt == maxAttempts) {
          throw AvBaseRequestException(
            uri,
            response.statusCode,
            kind: _kindForStatus(response.statusCode),
          );
        }
        attemptDelay = _retryDelayFor(response);
      } on TimeoutException {
        if (attempt == maxAttempts) {
          throw AvBaseRequestException(
            uri,
            null,
            kind: AvBaseFailureKind.timeout,
          );
        }
      } on http.ClientException {
        if (attempt == maxAttempts) {
          throw AvBaseRequestException(
            uri,
            null,
            kind: AvBaseFailureKind.transport,
          );
        }
      }
      if (attemptDelay > Duration.zero) {
        await Future<void>.delayed(attemptDelay);
      }
    }
    throw StateError('Unreachable AvBase retry state.');
  }

  void close() {
    _fetcher.close();
  }

  bool _isTransient(int statusCode) {
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }

  Duration _retryDelayFor(SafeHttpResponse response) {
    final raw = response.headers['retry-after']?.trim();
    final seconds = raw == null ? null : double.tryParse(raw);
    if (seconds == null || seconds.isNegative) {
      return retryDelay;
    }
    final serverDelay = Duration(milliseconds: (seconds * 1000).ceil());
    return serverDelay > retryDelay ? serverDelay : retryDelay;
  }

  AvBaseFailureKind _kindForStatus(int statusCode) {
    if (statusCode == 404) {
      return AvBaseFailureKind.notFound;
    }
    if (statusCode == 408 || statusCode >= 500) {
      return AvBaseFailureKind.transientTransport;
    }
    if (statusCode == 429) {
      return AvBaseFailureKind.rateLimited;
    }
    if (statusCode == 403) {
      return AvBaseFailureKind.blocked;
    }
    return AvBaseFailureKind.transport;
  }

  bool _looksBlocked(SafeHttpResponse response) {
    if (response.statusCode == 403) {
      return true;
    }
    final body = utf8
        .decode(response.bodyBytes, allowMalformed: true)
        .toLowerCase();
    return body.contains('access denied') ||
        body.contains('just a moment') ||
        body.contains('cf-chl-');
  }
}
