import '../../models/scraped_actress_details.dart';
import '../../models/work.dart';
import '../../models/scrape_source_settings.dart';

final class WorkFieldSourceEvidence {
  const WorkFieldSourceEvidence({required this.source, this.sourceUri});

  final String source;
  final Uri? sourceUri;
}

/// Typed identity evidence supplied by a metadata source.
///
/// These values are identifiers and provenance, not image URLs.  A source may
/// provide a canonical maker code together with platform-specific aliases so
/// that the aggregate scrape can reconcile records without applying a global
/// number/prefix normalizer.
final class ScrapeExternalWorkIdentity {
  const ScrapeExternalWorkIdentity({
    this.canonicalCode,
    this.makerCode,
    this.manufacturer,
    this.label,
    this.series,
    this.platformIds = const {},
    this.aliases = const [],
  });

  final String? canonicalCode;
  final String? makerCode;
  final String? manufacturer;
  final String? label;
  final String? series;
  final Map<String, String> platformIds;
  final List<String> aliases;

  bool get isEmpty =>
      (canonicalCode == null || canonicalCode!.trim().isEmpty) &&
      (makerCode == null || makerCode!.trim().isEmpty) &&
      platformIds.isEmpty &&
      aliases.isEmpty;

  Iterable<String> get declaredCodes sync* {
    for (final value in <String?>[canonicalCode, makerCode]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) yield trimmed;
    }
    yield* aliases
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    yield* platformIds.values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
  }
}

enum ScrapeCoPerformance {
  unknown,
  possibleSharedProduction,
  sharedProduction,
  independentSegments,
}

/// Optional facts exposed by a source adapter for provenance classification.
/// Empty lists and null booleans mean that the source did not provide the
/// corresponding fact; they are never treated as negative evidence.
final class ScrapeWorkProvenanceFacts {
  const ScrapeWorkProvenanceFacts({
    this.includedWorks = const [],
    this.parentWorks = const [],
    this.genres = const [],
    this.tags = const [],
    this.description,
    this.containsPriorWorks,
    this.extractedFromPriorWork,
    this.splitFromPriorWork,
    this.packageOfIndependentWorks,
    this.packageOfPriorWorks,
    this.reusedIndependentSegments,
    this.oldMaterialWithNewBonus,
    this.reissue,
    this.remaster,
    this.reedited,
    this.explicitOriginalProduction,
    this.coPerformance = ScrapeCoPerformance.unknown,
  });

  final List<String> includedWorks;
  final List<String> parentWorks;
  final List<String> genres;
  final List<String> tags;
  final String? description;
  final bool? containsPriorWorks;
  final bool? extractedFromPriorWork;
  final bool? splitFromPriorWork;
  final bool? packageOfIndependentWorks;
  final bool? packageOfPriorWorks;
  final bool? reusedIndependentSegments;
  final bool? oldMaterialWithNewBonus;
  final bool? reissue;
  final bool? remaster;
  final bool? reedited;
  final bool? explicitOriginalProduction;
  final ScrapeCoPerformance coPerformance;
}

typedef WorkProvenanceEvidence = ScrapeWorkProvenanceFacts;
typedef ScrapeWorkProvenance = ScrapeWorkProvenanceFacts;

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
    this.externalIdentity,
  });

  final ScrapeSourceId source;
  final String? code;
  final String? rawCode;
  final String title;
  final Uri detailUri;
  final String? releaseDate;
  final ScrapeExternalWorkIdentity? externalIdentity;
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
    this.performers,
    this.description,
    this.includedWorks = const [],
    this.parentWorks = const [],
    this.genres = const [],
    this.coPerformance = ScrapeCoPerformance.unknown,
    this.provenanceFacts = const ScrapeWorkProvenanceFacts(),
    this.imageUris = const [],
    this.originalImageEvidenceUris = const [],
    this.fieldSources = const {},
    this.sourceUri,
    this.externalIdentity,
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
  final List<WorkPerformer>? performers;
  final String? description;
  final List<String> includedWorks;
  final List<String> parentWorks;
  final List<String> genres;
  final ScrapeCoPerformance coPerformance;
  final ScrapeWorkProvenanceFacts provenanceFacts;
  final List<Uri> imageUris;
  final List<Uri> originalImageEvidenceUris;
  final Map<String, WorkFieldSourceEvidence> fieldSources;
  final Uri? sourceUri;
  final ScrapeExternalWorkIdentity? externalIdentity;

  ScrapeWorkDetails copyWith({Uri? sourceUri}) => ScrapeWorkDetails(
    source: source,
    code: code,
    rawCode: rawCode,
    title: title,
    releaseDate: releaseDate,
    durationMinutes: durationMinutes,
    studio: studio,
    publisher: publisher,
    series: series,
    performerCount: performerCount,
    performers: performers,
    description: description,
    includedWorks: includedWorks,
    parentWorks: parentWorks,
    genres: genres,
    coPerformance: coPerformance,
    provenanceFacts: provenanceFacts,
    imageUris: imageUris,
    originalImageEvidenceUris: originalImageEvidenceUris,
    fieldSources: fieldSources,
    sourceUri: sourceUri ?? this.sourceUri,
    externalIdentity: externalIdentity,
  );

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
