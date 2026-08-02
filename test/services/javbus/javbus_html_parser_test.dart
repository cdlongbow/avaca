import 'package:avaca/services/javbus/javbus_html_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = JavBusHtmlParser();

  test('parses actress details, works and pagination from an actress page', () {
    final page = parser.parseActressPage(
      _actressHtml,
      pageUri: Uri.parse('https://www.javbus.com/star/uly'),
    );

    expect(page.details.name, '涼森れむ');
    expect(
      page.details.avatarUrl.toString(),
      'https://www.javbus.com/pics/actress/uly_a.jpg',
    );
    expect(page.details.birthDate, '1997-12-03');
    expect(page.details.height, '160');
    expect(page.details.cup, 'D');
    expect(page.details.bust, '87');
    expect(page.details.waist, '58');
    expect(page.details.hip, '85');
    expect(page.pageCount, 2);
    expect(page.works.map((work) => work.code), ['ABF-183', 'FC2-123']);
    expect(page.works.first.title, '第一部作品');
    expect(page.works.first.releaseDate, '2024-07-16');
    expect(
      page.works.first.detailUri.toString(),
      'https://www.javbus.com/ABF-183',
    );
  });

  test('parses selected detail fields from a work page', () {
    final work = parser.parseWorkPage(
      _workHtml,
      pageUri: Uri.parse('https://www.javbus.com/ABF-183'),
    );

    expect(work.code, 'ABF-183');
    expect(work.title, '詳細作品標題');
    expect(work.releaseDate, '2024-07-16');
    expect(work.durationMinutes, 120);
    expect(work.studio, 'プレステージ');
    expect(work.publisher, 'ABS');
    expect(work.series, 'PRESTIGE PREMIUM');
  });

  test('parses actress search results and resolves relative links', () {
    final results = parser.parseActressSearchResults(
      _searchHtml,
      pageUri: Uri.parse('https://www.javbus.com/searchstar/remu'),
    );

    expect(results, hasLength(1));
    expect(results.single.name, '涼森れむ');
    expect(results.single.uri.toString(), 'https://www.javbus.com/star/uly');
  });
}

const _actressHtml = '''
<html><body>
  <div class="avatar-box">
    <div class="photo-frame"><img src="/pics/actress/uly_a.jpg"></div>
    <div class="photo-info">
      <span>涼森れむ</span>
      <p>生日: 1997-12-03</p><p>身高: 160cm</p><p>罩杯: D</p>
      <p>胸圍: 87cm</p><p>腰圍: 58cm</p><p>臀圍: 85cm</p>
    </div>
  </div>
  <a class="movie-box" href="/ABF-183">
    <div class="photo-info"><span>第一部作品</span><date>ABF-183</date><date>2024-07-16</date></div>
  </a>
  <a class="movie-box" href="/FC2-123">
    <div class="photo-info"><span>排除作品</span><date>FC2-123</date><date>2024-06-01</date></div>
  </a>
  <ul class="pagination"><li><a href="/star/uly/1">1</a></li><li><a href="/star/uly/2">2</a></li></ul>
</body></html>
''';

const _workHtml = '''
<html><body>
  <h3>ABF-183 詳細作品標題</h3>
  <div class="info">
    <p><span class="header">識別碼:</span> ABF-183</p>
    <p><span class="header">發行日期:</span> 2024-07-16</p>
    <p><span class="header">長度:</span> 120分鐘</p>
    <p><span class="header">製作商:</span> <a>プレステージ</a></p>
    <p><span class="header">發行商:</span> <a>ABS</a></p>
    <p><span class="header">系列:</span> <a>PRESTIGE PREMIUM</a></p>
  </div>
</body></html>
''';

const _searchHtml = '''
<html><body>
  <a class="avatar-box text-center" href="/star/uly">
    <div class="photo-info"><span class="mleft">涼森れむ<button>有碼</button></span></div>
  </a>
</body></html>
''';
