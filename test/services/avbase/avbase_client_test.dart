import 'package:avaca/services/avbase/avbase_client.dart';
import 'package:avaca/services/avbase/avbase_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'uses direct talent route and continues through AvBase pagination',
    () async {
      final transport = _FakeAvBaseTransport();
      final client = AvBaseClient(transport: transport, maxPages: 3);

      final search = await client.searchActresses('石川澪');
      final firstPage = await client.fetchActressPage(search.single.uri);
      final collection = await client.fetchAllActressWorks(
        search.single.uri,
        firstPage: firstPage,
      );

    expect(
      search.single.uri.path,
      '/talents/${Uri.encodeComponent('石川澪')}',
    );
      expect(collection.works.map((work) => work.code), [
        'MIZD-549',
        'MIZD-550',
      ]);
      expect(collection.issues, isEmpty);
      expect(
        transport.requests.any((uri) => uri.queryParameters['page'] == '1'),
        isTrue,
      );
    },
  );
}

final class _FakeAvBaseTransport implements AvBaseTransport {
  final requests = <Uri>[];

  @override
  Future<String> get(Uri uri) async {
    requests.add(uri);
    if (uri.queryParameters['page'] == '1') {
      return _talentPage(code: 'MIZD-550', pageLinks: '');
    }
    return _talentPage(
      code: 'MIZD-549',
      pageLinks: '<a href="?q=&page=0">0</a><a href="?q=&page=1">1</a>',
    );
  }

  String _talentPage({required String code, required String pageLinks}) {
    return '''
      <html><body>
        <h1>石川澪</h1>
        <div class="bg-background border border-light rounded-lg overflow-hidden h-full">
          <a data-slot="button" href="/works/$code">$code title</a>
        </div>
        $pageLinks
      </body></html>
    ''';
  }
}
