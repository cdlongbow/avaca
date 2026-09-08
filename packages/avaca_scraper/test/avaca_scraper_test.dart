import 'package:avaca_domain/avaca_domain.dart';
import 'package:avaca_scraper/avaca_scraper.dart';
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
}

final class _Source implements AvacaScrapeSource {
  _Source(this.id, this._fetch);

  @override
  final String id;
  final Future<AvacaWorkSummary?> Function(String code) _fetch;

  @override
  Future<AvacaWorkSummary?> fetchWork(String code) => _fetch(code);
}
