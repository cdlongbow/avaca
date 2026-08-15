import '../../models/scraped_actress_details.dart';
import '../../models/work.dart';
import '../../models/scrape_source_settings.dart';

final class ScrapeActressSearchResult {
  const ScrapeActressSearchResult({
    required this.source,
    required this.name,
    required this.uri,
  });

  final ScrapeSourceId source;
  final String name;
  final Uri uri;
}

final class ScrapeActressPage {
  const ScrapeActressPage({
    required this.source,
    required this.details,
    this.aliases = const [],
    this.works = const [],
    this.pageCount = 1,
  });

  final ScrapeSourceId source;
  final ScrapedActressDetails details;
  final List<String> aliases;
  final List<ScrapeWorkSummary> works;
  final int pageCount;
}

final class ScrapeWorkSummary {
  const ScrapeWorkSummary({
    required this.source,
    required this.code,
    this.rawCode,
    required this.title,
    required this.detailUri,
    this.releaseDate,
  });

  final ScrapeSourceId source;
  final String? code;
  final String? rawCode;
  final String title;
  final Uri detailUri;
  final String? releaseDate;
}

final class ScrapeWorkDetails {
  const ScrapeWorkDetails({
    required this.source,
    required this.code,
    this.rawCode,
    required this.title,
    this.releaseDate,
    this.durationMinutes,
    this.studio,
    this.publisher,
    this.series,
    this.performerCount,
    this.imageUris = const [],
    this.originalImageEvidenceUris = const [],
  });

  final ScrapeSourceId source;
  final String code;
  final String? rawCode;
  final String title;
  final String? releaseDate;
  final int? durationMinutes;
  final String? studio;
  final String? publisher;
  final String? series;
  final int? performerCount;
  final List<Uri> imageUris;
  final List<Uri> originalImageEvidenceUris;

  Work toWork({String? cardImagePath, String? detailImagePath}) {
    return Work(
      code: code,
      title: title,
      releaseDate: releaseDate,
      durationMinutes: durationMinutes,
      studio: studio,
      publisher: publisher,
      series: series,
      cardImagePath: cardImagePath,
      detailImagePath: detailImagePath,
    );
  }
}

enum ScrapeSourceRunState {
  success,
  zeroResults,
  partial,
  unavailable,
  failed,
  cancelled,
  verificationRequired,
  blocked,
  rateLimited,
  timedOut,
}

final class ScrapeSourceRunResult {
  const ScrapeSourceRunResult({
    required this.source,
    required this.state,
    this.discovered = 0,
    this.error,
  });

  final ScrapeSourceId source;
  final ScrapeSourceRunState state;
  final int discovered;
  final Object? error;

  bool get succeeded =>
      state == ScrapeSourceRunState.success ||
      state == ScrapeSourceRunState.zeroResults ||
      state == ScrapeSourceRunState.partial;
}

final class ScrapeSourceRunDiagnostic {
  const ScrapeSourceRunDiagnostic({required this.state, required this.error});

  final ScrapeSourceRunState state;
  final Object error;
}
