import '../scrape/scrape_models.dart';
import '../../models/work.dart';

final class AvWikiWorkDetails {
  const AvWikiWorkDetails({
    required this.code,
    this.rawCode,
    required this.title,
    this.releaseDate,
    this.studio,
    this.publisher,
    this.series,
    this.performerCount,
    this.performers,
    this.description,
    this.genres = const [],
    this.provenanceFacts = const ScrapeWorkProvenanceFacts(),
    this.externalIdentity,
    this.catalogEvidence = const [],
  });

  final String code;
  final String? rawCode;
  final String title;
  final String? releaseDate;
  final String? studio;
  final String? publisher;
  final String? series;
  final int? performerCount;
  final List<WorkPerformer>? performers;
  final String? description;
  final List<String> genres;
  final ScrapeWorkProvenanceFacts provenanceFacts;
  final ScrapeExternalWorkIdentity? externalIdentity;
  final List<ScrapeCatalogWorkEvidence> catalogEvidence;
}

enum AvWikiFailureKind {
  blocked,
  rateLimited,
  timeout,
  transport,
  notFound,
  parserInvalid,
  cancelled,
  transientTransport,
}

final class AvWikiRequestException implements Exception {
  const AvWikiRequestException(
    this.uri,
    this.statusCode, {
    this.kind = AvWikiFailureKind.transport,
  });

  final Uri uri;
  final int? statusCode;
  final AvWikiFailureKind kind;

  @override
  String toString() =>
      'AV-Wiki request failed (${statusCode ?? kind.name}): $uri';
}
