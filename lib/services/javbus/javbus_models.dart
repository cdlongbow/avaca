import '../scrape/scrape_models.dart';
import '../../models/work.dart';

class JavBusWorkDetails {
  const JavBusWorkDetails({
    required this.code,
    required this.title,
    this.rawCode,
    this.releaseDate,
    this.durationMinutes,
    this.studio,
    this.publisher,
    this.series,
    this.performers,
    this.provenanceFacts = const ScrapeWorkProvenanceFacts(),
    this.originalImageEvidenceUris = const [],
    this.catalogEvidence = const [],
  });

  final String code;
  final String? rawCode;
  final String title;
  final String? releaseDate;
  final int? durationMinutes;
  final String? studio;
  final String? publisher;
  final String? series;
  final List<WorkPerformer>? performers;
  final ScrapeWorkProvenanceFacts provenanceFacts;
  final List<Uri> originalImageEvidenceUris;
  final List<ScrapeCatalogWorkEvidence> catalogEvidence;
}
