import 'package:avaca/services/avwiki/avwiki_html_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = AvWikiHtmlParser();

  test('parses exact work metadata and performers', () {
    final details = parser.parseWorkPage('''
      <html><body><main><article>
        <h1>MIZD-549 <span class="entry-subtitle">作品標題</span></h1>
        <dl class="dltable">
          <dt>メーカー品番</dt><dd>MIZD-549</dd>
          <dt>メーカー</dt><dd>MOODYZ</dd>
          <dt>レーベル</dt><dd>MOODYZ Best</dd>
          <dt>シリーズ</dt><dd>テストシリーズ</dd>
          <dt>配信開始日</dt><dd>2026-08-20</dd>
          <dt>AV女優名</dt><dd>石川澪、別名</dd>
          <dt>ジャンル</dt><dd>VR</dd>
        </dl>
        <p>この作品の紹介文です。十分な長さの説明を保存します。</p>
        <a rel="tag">高画質</a>
      </article></main></body></html>
    ''', pageUri: Uri.parse('https://av-wiki.net/mizd-549/'));

    expect(details.code, 'MIZD-549');
    expect(details.title, '作品標題');
    expect(details.releaseDate, '2026-08-20');
    expect(details.studio, 'MOODYZ');
    expect(details.publisher, 'MOODYZ Best');
    expect(details.series, 'テストシリーズ');
    expect(details.performers?.map((item) => item.name), ['石川澪', '別名']);
    expect(details.genres, ['VR', '高画質']);
    expect(details.description, contains('作品の紹介文'));
  });

  test('finds an exact work URI from an archive result', () {
    final uri = parser.findWorkUriByCode(
      '''
      <article class="archive-list">
        <ul class="post-meta">
          <li>MIZD-549</li>
          <li><a href="/maker/moodyz/">MOODYZ</a></li>
        </ul>
        <h2 class="archive-header-title"><a href="/archive-title/">作品</a></h2>
        <div class="read-more"><a href="/mizd-549/">詳情</a></div>
      </article>
    ''',
      pageUri: Uri.parse('https://av-wiki.net/?s=MIZD-549'),
      code: 'MIZD-549',
    );

    expect(uri, Uri.parse('https://av-wiki.net/mizd-549/'));
  });
}
