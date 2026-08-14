import '../../models/scrape_source_settings.dart';
import 'scrape_models.dart';

abstract interface class ScrapeSource {
  ScrapeSourceId get id;

  Future<List<ScrapeActressSearchResult>> searchActresses(String name);

  Future<ScrapeActressPage> fetchActressPage(ScrapeActressSearchResult actress);

  Future<List<ScrapeWorkSummary>> fetchActressWorks(
    ScrapeActressSearchResult actress, {
    required ScrapeActressPage firstPage,
    bool Function()? isCancelled,
  });

  Future<ScrapeWorkDetails> fetchWorkDetails(ScrapeWorkSummary work);

  bool acceptsImageUri(Uri uri);

  void close();
}

/// Optional source-owned diagnostics for partial pagination or access
/// problems. Sources that do not need this remain compatible with the base
/// interface.
abstract interface class ScrapeSourceDiagnosticsProvider {
  ScrapeSourceRunDiagnostic? get lastRunDiagnostic;

  void resetRunDiagnostic();
}
