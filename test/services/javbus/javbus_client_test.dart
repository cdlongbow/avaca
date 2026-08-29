import 'package:avaca/services/javbus/javbus_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('resolves an exact work code through the direct source route', () async {
    final transport = _FakeTransport({
      'https://www.javbus.com/ABF-183': '''
        <h3>ABF-183 測試作品</h3>
        <div class="info">
          <p><span class="header">識別碼:</span> ABF-183</p>
          <p><span class="header">長度:</span> 100分鐘</p>
        </div>
      ''',
    });

    final details = await JavBusClient(
      transport: transport,
    ).fetchWorkDetailsByCode('ABF-183');

    expect(details.code, 'ABF-183');
    expect(details.durationMinutes, 100);
    expect(transport.requested, ['https://www.javbus.com/ABF-183']);
  });

  test('rejects exact detail requests outside the configured origin', () async {
    final transport = _FakeTransport({});
    final client = JavBusClient(transport: transport);

    await expectLater(
      client.fetchWorkDetails(Uri.parse('https://example.com/ABF-183')),
      throwsA(isA<Exception>()),
    );
    expect(transport.requested, isEmpty);
  });

  test('HTTP transport retries a bounded transient failure', () async {
    var attempts = 0;
    final transport = HttpJavBusTransport(
      maxAttempts: 2,
      retryDelay: Duration.zero,
      client: MockClient((_) async {
        attempts++;
        return attempts == 1
            ? http.Response('', 503)
            : http.Response('ok', 200);
      }),
    );
    addTearDown(transport.close);

    expect(
      await transport.get(Uri.parse('https://www.javbus.com/ABF-183')),
      'ok',
    );
    expect(attempts, 2);
  });
}

final class _FakeTransport implements JavBusTransport {
  _FakeTransport(this.responses);

  final Map<String, String> responses;
  final List<String> requested = [];

  @override
  Future<String> get(Uri uri) async {
    requested.add(uri.toString());
    final response = responses[uri.toString()];
    if (response == null) throw StateError('Unexpected URI: $uri');
    return response;
  }
}
