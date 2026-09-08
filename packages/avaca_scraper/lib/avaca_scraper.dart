import 'package:avaca_domain/avaca_domain.dart';

/// Scraping is a Server concern.  The client only receives normalized catalog
/// records and cannot invoke source adapters directly.
abstract interface class AvacaScraper {
  Future<AvacaWorkSummary> resolveWork(String code);
}

/// A concrete source adapter belongs to the Server composition.  The source
/// returns normalized domain data; it never exposes HTTP response bodies,
/// cookies, or source-specific persistence to the client.
abstract interface class AvacaScrapeSource {
  String get id;

  Future<AvacaWorkSummary?> fetchWork(String code);
}

class AvacaScraperException implements Exception {
  const AvacaScraperException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// Tries configured Server-owned sources in order.  A source failure is
/// isolated so one unavailable provider does not freeze a folder import; the
/// caller receives a stable error only when no source can resolve the code.
final class CompositeAvacaScraper implements AvacaScraper {
  CompositeAvacaScraper(Iterable<AvacaScrapeSource> sources)
    : sources = List<AvacaScrapeSource>.unmodifiable(sources);

  final List<AvacaScrapeSource> sources;

  @override
  Future<AvacaWorkSummary> resolveWork(String code) async {
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) {
      throw const AvacaScraperException(
        'invalid_work_code',
        'work code is empty',
      );
    }
    if (sources.isEmpty) {
      throw const AvacaScraperException(
        'scraper_not_configured',
        'no Server scraper source is configured',
      );
    }
    var hadFailure = false;
    for (final source in sources) {
      try {
        final result = await source.fetchWork(normalizedCode);
        if (result != null) return result;
      } on Object {
        hadFailure = true;
      }
    }
    throw AvacaScraperException(
      hadFailure ? 'scraper_unavailable' : 'work_not_found',
      hadFailure
          ? 'configured Server scraper sources are unavailable'
          : 'work code was not found by configured Server scraper sources',
    );
  }
}

class UnavailableAvacaScraper implements AvacaScraper {
  const UnavailableAvacaScraper();

  @override
  Future<AvacaWorkSummary> resolveWork(String code) =>
      Future<AvacaWorkSummary>.error(
        UnsupportedError('Server scraper is not configured'),
      );
}
