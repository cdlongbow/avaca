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
        <p><a href="/talents/%E7%9F%B3%E5%B7%9D%E6%BE%AA">いしかわみお</a></p>
        <img alt="石川澪" src="https://pics.dmm.co.jp/mono/actjpgs/isikawa_mio.jpg">
        <div class="flex justify-between items-start"><span>生年月日</span><span>2002-03-02</span></div>
        <div class="flex justify-between items-start"><span>身長</span><span>158 cm</span></div>
        <div class="flex justify-between items-start"><span>サイズ</span><span>B82(B) W58 H86</span></div>
        <div class="bg-background border border-light rounded-lg overflow-hidden h-full">
          <a data-slot="button" href="/works/moodyz:MIZD-549">作品標題</a>
          <a href="/works/date/2026-08-20">2026/08/20</a>
        </div>
        <nav>
          <a data-slot="button" href="/works/date">本日発売</a>
        </nav>
        <nav>
          <a href="?q=&amp;page=0">0</a>
          <a href="?q=&amp;page=1">1</a>
          <a href="?q=&amp;page=6">6</a>
        </nav>
      </body></html>
      ''', pageUri: talentUri);

    expect(page.details.name, '石川澪');
    expect(page.aliases, ['いしかわみお']);
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
        <section class="p-3">
          <h2>タグ・説明文</h2>
          <p>過去作品を厳選収録した作品紹介ではなく、実際の説明文です。</p>
          <a href="/tags/best">ベスト・総集編</a>
          <a href="/tags/vr">ハイクオリティVR</a>
        </section>
        <section class="p-3">
          <h2>収録作品</h2>
          <div class="flex flex-col gap-3">
            <div class="flex flex-col gap-2">
              <div dir="rtl"><span>sodcreate:OLD-001</span></div>
              <a href="/works/sodcreate:OLD-001">収録された旧作品</a>
            </div>
            <div dir="rtl"><span>OLD-002</span></div>
            <a href="/works/OLD-002">収録された別作品</a>
          </div>
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
    expect(details.provenanceFacts.description, contains('実際の説明文'));
    expect(details.provenanceFacts.tags, ['ベスト・総集編', 'ハイクオリティVR']);
    expect(details.provenanceFacts.includedWorks, ['OLD-001', 'OLD-002']);
    expect(details.provenanceFacts.containsPriorWorks, isTrue);
    expect(details.originalImageEvidenceUris, hasLength(1));
    expect(details.originalImageEvidenceUris.single.host, 'pics.dmm.co.jp');
  });

  test('does not treat standalone collection wording as lineage evidence', () {
    final details = parser.parseWorkPage(
      '<html><body><h1>4K コレクション</h1></body></html>',
      pageUri: Uri.parse('https://www.avbase.net/works/test:COLL-001'),
    );

    expect(details.provenanceFacts.packageOfIndependentWorks, isNull);
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

  test('parses the real 永野いち夏 corpus card shape without name rules', () {
    final page = parser.parseActressPage(
      '''
      <html><body>
        <h1>永野いち夏</h1>
        <div class="bg-background border-light rounded-lg">
          <a data-slot="button" href="/works/chijoheaven:CJOB-213">見つめて乳首をカリカリ！さすさす！こねこね！主観乳首責めで何度も射精ブッコぬかれる僕。</a>
          <a href="/works/date/2026-08-21">2026/08/21</a>
        </div>
        <div class="bg-background border-light rounded-lg">
          <a data-slot="button" href="/works/umanami:UMSO-643">折れそうなくらい華奢なスレンダーボディ美少女12人</a>
          <a href="/works/date/2026-05-23">2026/05/23</a>
        </div>
        <div class="bg-background border-light rounded-lg">
          <a data-slot="button" href="/works/chijoheaven:CJOB-196">スキルもテクニックも超SSS級！もう射精してるってばぁ！ド痴女の天才SEX 100本番BEST！8時間！</a>
          <a href="/works/date/2026-01-23">2026/01/23</a>
        </div>
        <nav>
          <a href="?q=&amp;page=1">1</a>
          <a href="?q=&amp;page=6">6</a>
        </nav>
      </body></html>
      ''',
      pageUri: Uri.parse(
        'https://www.avbase.net/talents/${Uri.encodeComponent('永野いち夏')}',
      ),
    );

    expect(page.details.name, '永野いち夏');
    expect(page.pageCount, 6);
    expect(page.works.map((work) => work.code), [
      'CJOB-213',
      'UMSO-643',
      'CJOB-196',
    ]);
  });
}
