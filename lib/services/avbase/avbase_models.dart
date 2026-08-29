import '../scrape/scrape_models.dart';
import '../../models/work.dart';

final class AvBaseWorkDetails {
  const AvBaseWorkDetails({
    required this.code,
    required this.title,
    this.releaseDate,
    this.durationMinutes,
    this.studio,
    this.publisher,
    this.series,
    this.performerCount,
    this.performers,
    this.provenanceFacts = const ScrapeWorkProvenanceFacts(),
    this.originalImageEvidenceUris = const [],
    this.catalogEvidence = const [],
  });

  final String code;
  final String title;
  final String? releaseDate;
  final int? durationMinutes;
  final String? studio;
  final String? publisher;
  final String? series;
  final int? performerCount;
  final List<WorkPerformer>? performers;
  final ScrapeWorkProvenanceFacts provenanceFacts;
  final List<Uri> originalImageEvidenceUris;
  final List<ScrapeCatalogWorkEvidence> catalogEvidence;
}

enum AvBaseFailureKind {
  blocked,
  rateLimited,
  timeout,
  transport,
  notFound,
  parserInvalid,
  cancelled,
  transientTransport,
}

final class AvBaseRequestException implements Exception {
  const AvBaseRequestException(
    this.uri,
    this.statusCode, {
    this.kind = AvBaseFailureKind.transport,
  });

  final Uri uri;
  final int? statusCode;
  final AvBaseFailureKind kind;

  @override
  String toString() =>
      'AvBase request failed (${statusCode ?? kind.name}): $uri';
}
