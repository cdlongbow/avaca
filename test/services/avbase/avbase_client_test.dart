import 'package:avaca/services/avbase/avbase_client.dart';
import 'package:avaca/services/avbase/avbase_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves an exact work code through the source search route', () async {
    final transport = _FakeAvBaseTransport();
    final client = AvBaseClient(transport: transport);

    final details = await client.fetchWorkDetailsByCode('SETH-012');

    expect(details.code, 'SETH-012');
    expect(transport.requests[0].path, '/works');
    expect(transport.requests[0].queryParameters['q'], 'SETH-012');
    expect(transport.requests[1].path, '/works/sodcreate:SETH-012');
  });
}

final class _FakeAvBaseTransport implements AvBaseTransport {
  final requests = <Uri>[];

  @override
  Future<String> get(Uri uri) async {
    requests.add(uri);
    if (uri.path == '/works' && uri.queryParameters['q'] == 'SETH-012') {
      return '<a href="/works/sodcreate:SETH-012">SETH-012</a>';
    }
    if (uri.path == '/works/sodcreate:SETH-012') {
      return '''
        <html><body><h1>SETH-012 制服限定</h1>
        <dl><dt>発売日</dt><dd>2024/06/17</dd></dl>
        </body></html>
      ''';
    }
    throw StateError('Unexpected URI: $uri');
  }
}
