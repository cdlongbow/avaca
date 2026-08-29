import 'package:avaca/services/avbase/avbase_html_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = AvBaseHtmlParser();

  test('parses exact work metadata and source-owned image evidence', () {
    final uri = Uri.parse('https://www.avbase.net/works/moodyz:MIZD-549');
    final details = parser.parseWorkPage('''
      <html><body>
        <h1>MIZD-549 作品標題</h1>
        <dl>
          <dt>発売日</dt><dd>2026/08/20</dd>
          <dt>メーカー</dt><dd>MOODYZ</dd>
          <dt>レーベル</dt><dd>MOODYZ Best</dd>
          <dt>シリーズ</dt><dd>テストシリーズ</dd>
          <dt>収録分数</dt><dd>57分</dd>
        </dl>
        <section>
          <h2>出演者</h2>
          <a href="/talents/example">石川澪</a>
        </section>
        <section>
          <h2>紹介文</h2>
          <p>真実の紹介文。この作品そのものの説明です。</p>
        </section>
        <section>
          <h2>収録作品</h2>
          <a href="/works/OLD-001">收錄舊作品</a>
        </section>
        <img src="https://pics.dmm.co.jp/digital/video/mizd00549/mizd00549pl.jpg">
      </body></html>
    ''', pageUri: uri);

    expect(details.code, 'MIZD-549');
    expect(details.title, '作品標題');
    expect(details.releaseDate, '2026-08-20');
    expect(details.durationMinutes, 57);
    expect(details.studio, 'MOODYZ');
    expect(details.publisher, 'MOODYZ Best');
    expect(details.performers?.single.name, '石川澪');
    expect(details.provenanceFacts.includedWorks, ['OLD-001']);
    expect(details.originalImageEvidenceUris.single.host, 'pics.dmm.co.jp');
  });

  test('finds an exact work URI from a search result', () {
    final uri = parser.findWorkUriByCode(
      '<a href="/works/moodyz:MIZD-549">MIZD-549</a>',
      pageUri: Uri.parse('https://www.avbase.net/works?q=MIZD-549'),
      code: 'MIZD-549',
    );

    expect(uri, Uri.parse('https://www.avbase.net/works/moodyz:MIZD-549'));
  });
}
