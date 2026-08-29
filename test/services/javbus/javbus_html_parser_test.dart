import 'package:avaca/services/javbus/javbus_html_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = JavBusHtmlParser();

  test('parses exact work metadata, performers, and image evidence', () {
    final details = parser.parseWorkPage('''
      <html><body>
        <h3>ABF-183 測試作品</h3>
        <div class="info">
          <p><span class="header">識別碼:</span> ABF-183</p>
          <p><span class="header">發行日期:</span> 2026-08-20</p>
          <p><span class="header">長度:</span> 100分鐘</p>
          <p><span class="header">製作商:</span> プレステージ</p>
          <p><span class="header">出演者:</span>
            <a href="/star/example">涼森れむ</a>
          </p>
          <p><span class="header">系列:</span> 測試系列</p>
        </div>
        <div class="info"><p><span class="header">ジャンル:</span></p></div>
        <img src="https://pics.dmm.co.jp/digital/video/abf00183/abf00183pl.jpg">
      </body></html>
    ''', pageUri: Uri.parse('https://www.javbus.com/ABF-183'));

    expect(details.code, 'ABF-183');
    expect(details.title, '測試作品');
    expect(details.durationMinutes, 100);
    expect(details.studio, 'プレステージ');
    expect(details.series, '測試系列');
    expect(details.performers?.single.name, '涼森れむ');
    expect(details.originalImageEvidenceUris.single.host, 'pics.dmm.co.jp');
  });

  test('keeps scoped edition spelling in the exact parser', () {
    final details = parser.parseWorkPage(
      '<html><body><h3>STARS-087-VT 特別版</h3></body></html>',
      pageUri: Uri.parse('https://www.javbus.com/STARS-087-VT'),
    );

    expect(details.code, 'STARS-087-VT');
    expect(details.rawCode, 'STARS-087-VT');
  });
}
