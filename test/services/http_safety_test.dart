import 'dart:async';

import 'package:avaca/services/http_safety.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('rejects non-HTTPS and non-allowlisted hosts before sending', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('unexpected', 200);
    });
    final fetcher = SafeHttpFetcher(
      client: client,
      allowedHosts: const {'www.javbus.com'},
    );

    await expectLater(
      fetcher.get(Uri.parse('http://www.javbus.com/star/uly')),
      throwsA(isA<UnsafeHttpUriException>()),
    );
    await expectLater(
      fetcher.get(Uri.parse('https://example.com/star/uly')),
      throwsA(isA<UnsafeHttpUriException>()),
    );
    expect(requests, 0);
  });

  test('rejects a non-allowlisted referer before sending', () async {
    var requests = 0;
    final fetcher = SafeHttpFetcher(
      client: MockClient((_) async {
        requests++;
        return http.Response('unexpected', 200);
      }),
      allowedHosts: const {'www.javbus.com'},
    );

    await expectLater(
      fetcher.get(
        Uri.parse('https://www.javbus.com/pics/actress/zh5_a.jpg'),
        referer: Uri.parse('https://example.com/'),
      ),
      throwsA(isA<UnsafeHttpUriException>()),
    );
    expect(requests, 0);
  });

  test(
    'follows allowlisted redirects but rejects an offsite redirect',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/start') {
          return http.Response('', 302, headers: {'location': '/final'});
        }
        if (request.url.path == '/offsite') {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://example.com/pivot'},
          );
        }
        return http.Response('ok', 200);
      });
      final fetcher = SafeHttpFetcher(
        client: client,
        allowedHosts: const {'www.javbus.com'},
      );

      final response = await fetcher.get(
        Uri.parse('https://www.javbus.com/start'),
      );
      expect(response.bodyBytes, 'ok'.codeUnits);
      expect(response.finalUri.path, '/final');
      await expectLater(
        fetcher.get(Uri.parse('https://www.javbus.com/offsite')),
        throwsA(isA<UnsafeHttpUriException>()),
      );
    },
  );

  test('rejects responses larger than the configured byte limit', () async {
    final fetcher = SafeHttpFetcher(
      client: MockClient((_) async => http.Response('12345', 200)),
      allowedHosts: const {'www.javbus.com'},
      maxBytes: 4,
    );

    await expectLater(
      fetcher.get(Uri.parse('https://www.javbus.com/large')),
      throwsA(isA<HttpBodyTooLargeException>()),
    );
  });

  test(
    'enforces one absolute deadline across the complete response body',
    () async {
      final fetcher = SafeHttpFetcher(
        client: _SlowStreamingClient(),
        allowedHosts: const {'www.javbus.com'},
        timeout: const Duration(milliseconds: 35),
      );

      await expectLater(
        fetcher.get(Uri.parse('https://www.javbus.com/slow')),
        throwsA(isA<TimeoutException>()),
      );
    },
  );
}

class _SlowStreamingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stream = Stream<List<int>>.periodic(
      const Duration(milliseconds: 10),
      (_) => const [49],
    ).take(10);
    return http.StreamedResponse(stream, 200);
  }
}
