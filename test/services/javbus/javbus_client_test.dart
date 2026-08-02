import 'dart:convert';

import 'package:avaca/services/javbus/javbus_client.dart';
import 'package:avaca/services/javbus/prefix_exclusion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'fetches every actress page, excludes prefixes and deduplicates codes',
    () async {
      final transport = _FakeTransport({
        'https://www.javbus.com/star/uly': _page(
          pageCount: 2,
          works: const [('ABF-183', 'first'), ('fc2-123', 'excluded')],
        ),
        'https://www.javbus.com/star/uly/2': _page(
          pageCount: 2,
          works: const [('abf-183', 'duplicate'), ('SONE-833', 'second')],
        ),
      });
      final client = JavBusClient(transport: transport);

      final works = await client.fetchAllActressWorks(
        Uri.parse('https://www.javbus.com/star/uly'),
        exclusions: PrefixExclusion(['FC2']),
      );

      expect(works.map((work) => work.code), ['ABF-183', 'SONE-833']);
      expect(transport.requested, [
        'https://www.javbus.com/star/uly',
        'https://www.javbus.com/star/uly/2',
      ]);
    },
  );

  test('searches actresses and fetches selected work details', () async {
    final transport = _FakeTransport({
      'https://www.javbus.com/searchstar/remu': '''
        <a class="avatar-box text-center" href="/star/uly">
          <div class="photo-info"><span class="mleft">涼森れむ<button>有碼</button></span></div>
        </a>
      ''',
      'https://www.javbus.com/ABF-183': '''
        <h3>作品</h3><div class="info">
          <p><span class="header">識別碼:</span> ABF-183</p>
          <p><span class="header">長度:</span> 100分鐘</p>
        </div>
      ''',
    });
    final client = JavBusClient(transport: transport);

    final actresses = await client.searchActresses('remu');
    final work = await client.fetchWorkDetails(
      Uri.parse('https://www.javbus.com/ABF-183'),
    );

    expect(actresses.single.name, '涼森れむ');
    expect(work.durationMinutes, 100);
    expect(work.toWork().code, 'ABF-183');
  });

  test('HTTP transport decodes UTF-8 and rejects non-success status', () async {
    final successful = HttpJavBusTransport(
      client: MockClient(
        (_) async => http.Response.bytes(utf8.encode('涼森れむ'), 200),
      ),
    );
    expect(
      await successful.get(Uri.parse('https://www.javbus.com/ok')),
      '涼森れむ',
    );

    final failing = HttpJavBusTransport(
      client: MockClient((_) async => http.Response('', 503)),
    );
    await expectLater(
      failing.get(Uri.parse('https://www.javbus.com/fail')),
      throwsA(isA<JavBusRequestException>()),
    );
  });

  test(
    'HTTP transport retries a bounded number of transient failures',
    () async {
      var attempts = 0;
      final transport = HttpJavBusTransport(
        maxAttempts: 2,
        retryDelay: Duration.zero,
        client: MockClient((_) async {
          attempts++;
          return attempts == 1
              ? http.Response('', 503)
              : http.Response.bytes(utf8.encode('ok'), 200);
        }),
      );

      expect(
        await transport.get(Uri.parse('https://www.javbus.com/transient')),
        'ok',
      );
      expect(attempts, 2);
    },
  );

  test('completes driver verification in the same cookie session', () async {
    var requestNumber = 0;
    final transport = HttpJavBusTransport(
      retryDelay: Duration.zero,
      verificationHandler: (challenge) async {
        expect(challenge.questions.single.prompt, '你是否了解交通規則？');
        expect(challenge.questions.single.options.map((item) => item.label), [
          'A. 是',
          'B. 否',
        ]);
        expect(challenge.submitFields, {'submit': 'question'});
        return {'userAnswers[4]': 'A'};
      },
      client: MockClient((request) async {
        requestNumber++;
        switch (requestNumber) {
          case 1:
            return http.Response(
              '',
              302,
              headers: {
                'location':
                    '/doc/driver-verify?referer=https%3A%2F%2Fwww.javbus.com%2Fsearchstar%2Fremu',
                'set-cookie': 'PHPSESSID=session123; path=/',
              },
            );
          case 2:
            expect(request.headers['cookie'], contains('PHPSESSID=session123'));
            return http.Response.bytes(
              utf8.encode(_driverVerificationHtml),
              200,
            );
          case 3:
            expect(request.method, 'POST');
            expect(request.headers['cookie'], contains('PHPSESSID=session123'));
            expect(request.body, contains('userAnswers%5B4%5D=A'));
            expect(request.body, contains('submit=question'));
            return http.Response(
              '',
              302,
              headers: {
                'location': '/searchstar/remu',
                'set-cookie': 'driver=verified; path=/',
              },
            );
          default:
            expect(request.headers['cookie'], contains('driver=verified'));
            return http.Response('<html>works</html>', 200);
        }
      }),
    );

    final source = await transport.get(
      Uri.parse('https://www.javbus.com/searchstar/remu'),
    );

    expect(source, '<html>works</html>');
    expect(transport.cookieHeader, contains('driver=verified'));
  });

  test('completes the current JavBus age confirmation form', () async {
    var requestNumber = 0;
    final transport = HttpJavBusTransport(
      retryDelay: Duration.zero,
      verificationHandler: (challenge) async {
        expect(challenge.questions, isEmpty);
        expect(challenge.submitFields, {'Submit': '確認'});
        return const {};
      },
      client: MockClient((request) async {
        requestNumber++;
        switch (requestNumber) {
          case 1:
            return http.Response(
              '',
              302,
              headers: {
                'location':
                    '/doc/driver-verify?referer=https%3A%2F%2Fwww.javbus.com%2Fsearchstar%2Fremu',
                'set-cookie': 'PHPSESSID=session123; path=/',
              },
            );
          case 2:
            return http.Response.bytes(utf8.encode(_ageConfirmationHtml), 200);
          case 3:
            expect(request.method, 'POST');
            expect(request.headers['cookie'], contains('PHPSESSID=session123'));
            expect(request.body, contains('Submit=%E7%A2%BA%E8%AA%8D'));
            return http.Response(
              '',
              302,
              headers: {
                'location': '/searchstar/remu',
                'set-cookie': 'over18=yes; path=/',
              },
            );
          default:
            expect(request.headers['cookie'], contains('over18=yes'));
            return http.Response('<html>works</html>', 200);
        }
      }),
    );

    expect(
      await transport.get(Uri.parse('https://www.javbus.com/searchstar/remu')),
      '<html>works</html>',
    );
  });

  test(
    'rejects parsed navigation outside the configured JavBus origin',
    () async {
      final transport = _FakeTransport({});
      final client = JavBusClient(transport: transport);

      await expectLater(
        client.fetchWorkDetails(Uri.parse('https://example.com/ABF-183')),
        throwsA(isA<Exception>()),
      );
      expect(transport.requested, isEmpty);
    },
  );

  test(
    'rejects an unbounded pagination count before requesting page two',
    () async {
      final transport = _FakeTransport({
        'https://www.javbus.com/star/uly': _page(
          pageCount: 101,
          works: const [('ABF-183', 'first')],
        ),
      });
      final client = JavBusClient(transport: transport, maxPages: 100);

      await expectLater(
        client.fetchAllActressWorks(
          Uri.parse('https://www.javbus.com/star/uly'),
        ),
        throwsA(isA<JavBusPageLimitException>()),
      );
      expect(transport.requested, ['https://www.javbus.com/star/uly']);
    },
  );

  test('cancellation stops pagination before another page request', () async {
    var cancelled = false;
    final transport = _CallbackTransport({
      'https://www.javbus.com/star/uly': _page(
        pageCount: 3,
        works: const [('ABF-183', 'first')],
      ),
    }, afterGet: () => cancelled = true);
    final client = JavBusClient(transport: transport);

    final works = await client.fetchAllActressWorks(
      Uri.parse('https://www.javbus.com/star/uly'),
      isCancelled: () => cancelled,
    );

    expect(works.map((work) => work.code), ['ABF-183']);
    expect(transport.requested, ['https://www.javbus.com/star/uly']);
  });
}

const _driverVerificationHtml = '''
<html><body>
  <form method="POST" action="driver-verify.php?referer=/searchstar/remu">
    <input type="hidden" name="token" value="abc">
    <ul><li><label>
      你是否了解交通規則？<br>
      <input type="radio" name="userAnswers[4]" value="A"> A. 是<br>
      <input type="radio" name="userAnswers[4]" value="B"> B. 否<br>
    </label></li></ul>
    <button type="submit" name="submit" value="question">送出答案</button>
  </form>
</body></html>
''';

const _ageConfirmationHtml = '''
<html><body>
  <form class="form1" method="post" action="" id="form1">
    <label><input type="checkbox" value="">我已經成年</label>
    <input id="submit" value="確認" type="submit" name="Submit">
  </form>
</body></html>
''';

class _FakeTransport implements JavBusTransport {
  _FakeTransport(this.responses);

  final Map<String, String> responses;
  final List<String> requested = [];

  @override
  Future<String> get(Uri uri) async {
    requested.add(uri.toString());
    final response = responses[uri.toString()];
    if (response == null) {
      throw StateError('Unexpected URI: $uri');
    }
    return response;
  }
}

class _CallbackTransport extends _FakeTransport {
  _CallbackTransport(super.responses, {required this.afterGet});

  final void Function() afterGet;

  @override
  Future<String> get(Uri uri) async {
    final value = await super.get(uri);
    afterGet();
    return value;
  }
}

String _page({required int pageCount, required List<(String, String)> works}) {
  final cards = works
      .map(
        (work) =>
            '''
        <a class="movie-box" href="/${work.$1}">
          <div class="photo-info">
            <span>${work.$2}</span><date>${work.$1}</date><date>2024-01-01</date>
          </div>
        </a>
        ''',
      )
      .join();
  return '''
    <html><body>
      <div class="avatar-box"><div class="photo-info"><span>涼森れむ</span></div></div>
      $cards
      <ul class="pagination"><li><a>$pageCount</a></li></ul>
    </body></html>
  ''';
}
