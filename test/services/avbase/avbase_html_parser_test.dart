import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/services/avbase/avbase_html_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = AvBaseHtmlParser();
  final talentUri = Uri.parse(
    'https://www.avbase.net/talents/%E7%9F%B3%E5%B7%9D%E6%BE%AA',
  );

  test('parses talent profile, paged work cards, and DMM avatar policy', () {
    final page = parser.parseActressPage('''
      <html><body>
        <h1>石川澪</h1>
        <img alt="石川澪" src="https://pics.dmm.co.jp/mono/actjpgs/isikawa_mio.jpg">
        <div class="flex justify-between items-start"><span>生年月日</span><span>2002-03-02</span></div>
        <div class="flex justify-between items-start"><span>身長</span><span>158 cm</span></div>
        <div class="flex justify-between items-start"><span>サイズ</span><span>B82(B) W58 H86</span></div>
        <div class="bg-background border border-light rounded-lg overflow-hidden h-full">
          <a data-slot="button" href="/works/moodyz:MIZD-549">作品標題</a>
          <a href="/works/date/2026-08-20">2026/08/20</a>
        </div>
        <nav>
          <a href="?q=&amp;page=0">0</a>
          <a href="?q=&amp;page=1">1</a>
          <a href="?q=&amp;page=6">6</a>
        </nav>
      </body></html>
      ''', pageUri: talentUri);

    expect(page.details.name, '石川澪');
    expect(page.details.birthDate, '2002-03-02');
    expect(page.details.height, '158');
    expect(page.details.cup, 'B');
    expect(page.details.bust, '82');
    expect(page.details.waist, '58');
    expect(page.details.hip, '86');
    expect(
      page.details.avatarUrl.toString(),
      'https://pics.dmm.co.jp/mono/actjpgs/isikawa_mio.jpg',
    );
    expect(page.pageCount, 7);
    expect(page.works.single.code, 'MIZD-549');
    expect(page.works.single.releaseDate, '2026-08-20');
  });

  test('parses work metadata, performers, and original evidence only', () {
    final uri = Uri.parse('https://www.avbase.net/works/moodyz:MIZD-549');
    final details = parser.parseWorkPage('''
      <html><body>
        <h1>MIZD-549 作品標題</h1>
        <dl>
          <dt>発売日</dt><dd>2026/08/20</dd>
          <dt>メーカー</dt><dd>MOODYZ</dd>
          <dt>シリーズ</dt><dd>テストシリーズ</dd>
          <dt>収録分数</dt><dd>57分</dd>
        </dl>
        <section class="p-3">
          <h2>出演者・メモ</h2>
          <a href="/talents/%E7%9F%B3%E5%B7%9D%E6%BE%AA">石川澪</a>
        </section>
        <img src="https://pics.dmm.co.jp/digital/video/mizd00549/mizd00549pl.jpg">
        <img src="https://www.avbase.net/assets/not-a-work-image.jpg">
      </body></html>
      ''', pageUri: uri);

    expect(details.code, 'MIZD-549');
    expect(details.title, '作品標題');
    expect(details.releaseDate, '2026-08-20');
    expect(details.durationMinutes, 57);
    expect(details.studio, 'MOODYZ');
    expect(details.series, 'テストシリーズ');
    expect(details.performerCount, 1);
    expect(details.performers?.single.name, '石川澪');
    expect(details.originalImageEvidenceUris, hasLength(1));
    expect(details.originalImageEvidenceUris.single.host, 'pics.dmm.co.jp');
  });

  test('parses direct talent route as a single AvBase search result', () {
    final result = parser.parseActressSearchResult(
      '<html><body><h1>石川澪</h1></body></html>',
      pageUri: talentUri,
      query: '石川澪',
    );

    expect(result?.source, ScrapeSourceId.avbase);
    expect(result?.name, '石川澪');
    expect(result?.uri, talentUri);
  });
}
