import '../../models/scrape_source_settings.dart';
import '../scrape/scrape_models.dart';
import '../scrape/scrape_source.dart';
import 'avbase_client.dart';
import 'avbase_models.dart';

final class AvBaseScrapeSource
    implements ScrapeSource, ScrapeSourceDiagnosticsProvider {
  AvBaseScrapeSource(this.client);

  final AvBaseClient client;
  ScrapeSourceRunDiagnostic? _lastRunDiagnostic;

  @override
  ScrapeSourceRunDiagnostic? get lastRunDiagnostic => _lastRunDiagnostic;

  @override
  void resetRunDiagnostic() {
    _lastRunDiagnostic = null;
  }

  @override
  ScrapeSourceId get id => ScrapeSourceId.avbase;

  @override
  Future<List<ScrapeActressSearchResult>> searchActresses(String name) {
    return client.searchActresses(name);
  }

  @override
  Future<ScrapeActressPage> fetchActressPage(
    ScrapeActressSearchResult actress,
  ) async {
    final page = await client.fetchActressPage(actress.uri);
    return ScrapeActressPage(
      source: id,
      details: page.details,
      works: page.works.map(_summary).toList(growable: false),
      pageCount: page.pageCount,
    );
  }

  @override
  Future<List<ScrapeWorkSummary>> fetchActressWorks(
    ScrapeActressSearchResult actress, {
    required ScrapeActressPage firstPage,
    bool Function()? isCancelled,
  }) async {
    final firstAvBasePage = AvBaseActressPage(
      details: firstPage.details,
      works: firstPage.works
          .map(
            (work) => AvBaseWorkSummary(
              code: work.code,
              title: work.title,
              detailUri: work.detailUri,
              releaseDate: work.releaseDate,
            ),
          )
          .toList(growable: false),
      pageCount: firstPage.pageCount,
    );
    final collection = await client.fetchAllActressWorks(
      actress.uri,
      firstPage: firstAvBasePage,
      isCancelled: isCancelled,
    );
    final issues = collection.issues;
    if (issues.isNotEmpty) {
      final firstIssue = issues.first;
      _lastRunDiagnostic = ScrapeSourceRunDiagnostic(
        state: collection.works.isNotEmpty
            ? ScrapeSourceRunState.partial
            : _stateForIssue(firstIssue.kind),
        error: firstIssue,
      );
    }
    return collection.works.map(_summary).toList(growable: false);
  }

  @override
  Future<ScrapeWorkDetails> fetchWorkDetails(ScrapeWorkSummary work) async {
    final details = await client.fetchWorkDetails(work.detailUri);
    return ScrapeWorkDetails(
      source: id,
      code: details.code,
      rawCode: details.code,
      title: details.title,
      releaseDate: details.releaseDate,
      durationMinutes: details.durationMinutes,
      studio: details.studio,
      publisher: details.publisher,
      series: details.series,
      performerCount: details.performerCount,
      performers: details.performers,
      imageUris: const [],
      originalImageEvidenceUris: details.originalImageEvidenceUris,
    );
  }

  @override
  bool acceptsImageUri(Uri uri) => client.acceptsImageUri(uri);

  @override
  void close() => client.close();

  ScrapeWorkSummary _summary(AvBaseWorkSummary work) {
    return ScrapeWorkSummary(
      source: id,
      code: work.code,
      rawCode: work.code,
      title: work.title,
      detailUri: work.detailUri,
      releaseDate: work.releaseDate,
    );
  }

  ScrapeSourceRunState _stateForIssue(AvBaseFailureKind kind) {
    return switch (kind) {
      AvBaseFailureKind.blocked => ScrapeSourceRunState.blocked,
      AvBaseFailureKind.rateLimited => ScrapeSourceRunState.rateLimited,
      AvBaseFailureKind.timeout => ScrapeSourceRunState.timedOut,
      AvBaseFailureKind.cancelled => ScrapeSourceRunState.cancelled,
      AvBaseFailureKind.transport ||
      AvBaseFailureKind.transientTransport ||
      AvBaseFailureKind.notFound ||
      AvBaseFailureKind.parserInvalid => ScrapeSourceRunState.failed,
    };
  }
}
