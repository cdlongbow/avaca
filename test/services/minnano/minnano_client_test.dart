import 'package:avaca/services/minnano/minnano_client.dart';
import 'package:avaca/services/minnano/minnano_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the real search form and actress.php pagination shape', () async {
    final transport = _RecordingMinnanoTransport();
    final client = MinnanoClient(transport: transport);

    final matches = await client.searchActresses('小湊よつ葉');
    expect(matches.single.uri.toString(), contains('actress618082.html'));
    expect(
      transport.requested.first.queryParameters['search_scope'],
      'actress',
    );
    expect(transport.requested.first.queryParameters['search_word'], '小湊よつ葉');
    expect(transport.requested.first.queryParameters['search'], ' Go ');

    final firstPage = await client.fetchActressPage(matches.single.uri);
    final works = await client.fetchAllActressWorks(
      matches.single.uri,
      firstPage: firstPage,
    );

    expect(works.map((work) => work.detailUri.path), [
      '/av1.html',
      '/av2.html',
    ]);
    expect(
      transport.requested.any(
        (uri) =>
            uri.path == '/actress.php' &&
            uri.queryParameters['actress_id'] == '618082' &&
            uri.queryParameters['page'] == '2',
      ),
      isTrue,
    );
  });
}

final class _RecordingMinnanoTransport implements MinnanoTransport {
  final requested = <Uri>[];

  @override
  Future<String> get(Uri uri) async {
    requested.add(uri);
    if (uri.path == '/search_result.php') {
      return '<a href="actress618082.html">小湊よつ葉</a>';
    }
    if (uri.path == '/actress618082.html') {
      return _actressPage(
        '<tr><td><a href="av1.html"><h3 class="ttl">第一作</h3></a></td>'
        '<td>2026/05/18</td></tr>',
      );
    }
    if (uri.path == '/actress.php') {
      return _actressPage(
        '<tr><td><a href="av2.html"><h3 class="ttl">第二作</h3></a></td>'
        '<td>2026/05/19</td></tr>',
      );
    }
    throw StateError('Unexpected URI: $uri');
  }

  String _actressPage(String workRow) {
    return '''
      <h2>小湊よつ葉</h2>
      <table><tr><td><span>生年月日</span><p>1996年05月29日</p></td></tr></table>
      <table class="tbllist av">$workRow</table>
      <a href="/actress.php?actress_id=618082&page=2">2</a>
    ''';
  }
}
