import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/services/avbase/avbase_html_parser.dart';
import 'package:avaca/services/avbase/avbase_models.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
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
          <h2>紹介文</h2>
          <p>真実の紹介文。旧作一覧ではなく、この作品そのものの説明です。</p>
        </section>
        <section class="p-3">
          <h2>タグ・説明文</h2>
          <p>タグ側の補足説明です。</p>
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
    expect(details.provenanceFacts.description, contains('真実の紹介文'));
    expect(details.provenanceFacts.description, isNot(contains('タグ側の補足説明')));
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

  test('supports controlled non-section AvBase heading containers', () {
    final details = parser.parseWorkPage(
      '''
      <html><body>
        <h1>FALLBACK-001 作品</h1>
        <div class="card"><h2>紹介文</h2><p>制御された紹介文の本文です。</p></div>
        <div data-slot="card"><h2>タグ・説明文</h2><a href="/tags/vr">VR専用</a></div>
        <div class="card"><h2>収録作品</h2><a href="/works/OLD-001">旧作品</a></div>
      </body></html>
      ''',
      pageUri: Uri.parse('https://www.avbase.net/works/test:FALLBACK-001'),
    );

    expect(details.provenanceFacts.description, '制御された紹介文の本文です。');
    expect(details.provenanceFacts.tags, ['VR専用']);
    expect(details.provenanceFacts.includedWorks, ['OLD-001']);
  });

  test('distinguishes proven and weak AvBase co-performance wording', () {
    final hint = parser.parseWorkPage(
      '<html><body><h1>HINT-001 豪華共演ストーリー</h1></body></html>',
      pageUri: Uri.parse('https://www.avbase.net/works/test:HINT-001'),
    );
    final proven = parser.parseWorkPage(
      '<html><body><h1>PROVEN-001 全員同時出演・全編撮り下ろし新作</h1></body></html>',
      pageUri: Uri.parse('https://www.avbase.net/works/test:PROVEN-001'),
    );

    expect(
      hint.provenanceFacts.coPerformance,
      ScrapeCoPerformance.possibleSharedProduction,
    );
    expect(
      proven.provenanceFacts.coPerformance,
      ScrapeCoPerformance.sharedProduction,
    );
  });

  test('keeps AvBase lineage, split, and independent-segment facts narrow', () {
    AvBaseWorkDetails parse(String title) => parser.parseWorkPage(
      '<html><body><h1>MATRIX-001 $title</h1></body></html>',
      pageUri: Uri.parse('https://www.avbase.net/works/test:MATRIX-001'),
    );

    for (final title in const ['BEST11人', 'BEST COLLECTION', '全12作', '総集編']) {
      final facts = parse(title).provenanceFacts;
      expect(facts.containsPriorWorks, isNull, reason: title);
    }
    for (final title in const ['過去作品を収録', '既存作品を再収録', '旧作4本を収録']) {
      expect(
        parse(title).provenanceFacts.containsPriorWorks,
        isTrue,
        reason: title,
      );
    }
    for (final title in const [
      '完全撮り下ろし特典映像',
      '特典映像は全編撮り下ろし',
      '完全新撮ボーナス映像',
      '全編撮り下ろし特典',
      '全編撮り下ろしの特典映像',
      '完全新撮による特典映像',
      '全編新撮で収録した特典映像',
      '完全撮り下ろしのボーナス映像',
      '特典として全編撮り下ろし',
      'ボーナス映像は完全新撮',
    ]) {
      expect(
        parse(title).provenanceFacts.explicitOriginalProduction,
        isNull,
        reason: title,
      );
    }
    for (final title in const [
      '全編新撮の大型共演',
      '完全新撮作品',
      '完全撮り下ろし作品',
      '全編撮り下ろし新作',
    ]) {
      expect(
        parse(title).provenanceFacts.explicitOriginalProduction,
        isTrue,
        reason: title,
      );
    }
    for (final title in const [
      '旧作を完全収録',
      '過去作を完全収録',
      '既存作品を完全収録',
      '旧作品を厳選完全収録',
      '過去作品を厳選して収録',
    ]) {
      expect(
        parse(title).provenanceFacts.containsPriorWorks,
        isTrue,
        reason: title,
      );
    }

    for (final title in const ['個別', '各', '各作品', 'それぞれ', '分割', 'split']) {
      final facts = parse(title).provenanceFacts;
      expect(facts.coPerformance, ScrapeCoPerformance.unknown, reason: title);
      expect(facts.splitFromPriorWork, isNull, reason: title);
    }
    for (final title in const [
      '分割版',
      '分割販売',
      '元作品から分割',
      '個別版',
      '単独版',
      'split edition',
      'split from prior work',
    ]) {
      expect(
        parse(title).provenanceFacts.splitFromPriorWork,
        isTrue,
        reason: title,
      );
    }
    for (final title in const [
      '各女優それぞれ別作品を収録',
      '出演者ごとの独立作品',
      'それぞれ別作品から収録',
      '各作品を個別収録',
      '独立した3作品をまとめて収録',
    ]) {
      expect(
        parse(title).provenanceFacts.coPerformance,
        ScrapeCoPerformance.independentSegments,
        reason: title,
      );
    }
  });

  test('only promotes explicit AvBase shared-production propositions', () {
    AvBaseWorkDetails parse(String title) => parser.parseWorkPage(
      '<html><body><h1>MATRIX-SHARED $title</h1></body></html>',
      pageUri: Uri.parse('https://www.avbase.net/works/test:MATRIX-SHARED'),
    );

    for (final title in const ['一堂に会して', '全員参加', '同じ現場で', '全員が同一企画に参加']) {
      expect(
        parse(title).provenanceFacts.coPerformance,
        isNot(ScrapeCoPerformance.sharedProduction),
        reason: title,
      );
    }
    for (final title in const [
      '全員同時出演',
      '同一シーンで共演',
      '同一撮影企画',
      '同一収録で全員共演',
      '全編撮り下ろし大共演',
      '完全新撮の大型共演',
    ]) {
      expect(
        parse(title).provenanceFacts.coPerformance,
        ScrapeCoPerformance.sharedProduction,
        reason: title,
      );
    }
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
