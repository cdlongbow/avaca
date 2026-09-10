import 'package:avaca_domain/avaca_domain.dart';
import 'package:avaca_scraper/avaca_scraper.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'composite scraper isolates a failed source and resolves next source',
    () async {
      final scraper = CompositeAvacaScraper([
        _Source(
          'offline',
          (code) => Future<AvacaWorkSummary>.error(StateError('offline')),
        ),
        _Source(
          'fixture',
          (code) async => AvacaWorkSummary(
            workId: AvacaWorkId('work.$code'),
            code: code,
            title: 'Resolved $code',
          ),
        ),
      ]);

      final result = await scraper.resolveWork(' abp-001 ');

      expect(result.code, 'ABP-001');
      expect(result.title, 'Resolved ABP-001');
    },
  );

  test('composite scraper returns stable not-found code', () async {
    final scraper = CompositeAvacaScraper([
      _Source('empty', (_) async => null),
    ]);

    await expectLater(
      scraper.resolveWork('ABP-404'),
      throwsA(
        isA<AvacaScraperException>().having(
          (error) => error.code,
          'code',
          'work_not_found',
        ),
      ),
    );
  });

  test('default Server scraper resolves real fetched metadata', () async {
    final client = MockClient((request) async {
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'av-wiki.net');
      return http.Response(
        '<html><body><main><article><h1>ABP-001 Sample title</h1>'
        '<p>ABP-001</p></article></main></body></html>',
        200,
        headers: const {'content-type': 'text/html'},
      );
    });
    final scraper = DefaultAvacaScraper(client: client);

    final result = await scraper.resolveWork(' abp-001 ');

    expect(result.workId, const AvacaWorkId('work.abp-001'));
    expect(result.code, 'ABP-001');
    expect(result.title, 'Sample title');
    await scraper.close();
  });

  test('rich Server scraper caches an allow-listed artwork candidate', () async {
    final cache = await Directory.systemTemp.createTemp('avaca-artwork-');
    try {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('cover.jpg')) {
          return http.Response.bytes(
            const <int>[0xff, 0xd8, 0xff, 0xd9],
            200,
            headers: const {'content-type': 'image/jpeg'},
          );
        }
        return http.Response(
          '<html><head><meta property="og:image" content="https://av-wiki.net/cover.jpg"></head>'
          '<body><h1>ABP-001 Rich title</h1></body></html>',
          200,
          headers: const {'content-type': 'text/html'},
        );
      });
      final scraper = DefaultAvacaScraper(
        client: client,
        artworkCacheDirectory: cache.path,
      );

      final result = await scraper.resolveWorkDetails('ABP-001');

      expect(result.artwork?.cachedPath, isNotNull);
      expect(
        await File(result.artwork!.cachedPath!).readAsBytes(),
        orderedEquals(const <int>[0xff, 0xd8, 0xff, 0xd9]),
      );
      await scraper.close();
    } finally {
      await cache.delete(recursive: true);
    }
  });
}

final class _Source implements AvacaScrapeSource {
  _Source(this.id, this._fetch);

  @override
  final String id;
  final Future<AvacaWorkSummary?> Function(String code) _fetch;

  @override
  Future<AvacaWorkSummary?> fetchWork(String code) => _fetch(code);
}
