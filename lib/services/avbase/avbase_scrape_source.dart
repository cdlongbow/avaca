import '../../models/scrape_source_id.dart';
import '../scrape/scrape_models.dart';
import '../scrape/scrape_source.dart';
import 'avbase_client.dart';
import 'avbase_models.dart';

final class AvBaseScrapeSource implements ScrapeSource {
  AvBaseScrapeSource(this.client);

  final AvBaseClient client;

  @override
  ScrapeSourceId get id => ScrapeSourceId.avbase;

  @override
  Future<ScrapeWorkDetails?> fetchWorkDetailsByCode(
    String canonicalCode,
  ) async {
    try {
      return _mapDetails(await client.fetchWorkDetailsByCode(canonicalCode));
    } on AvBaseRequestException catch (error) {
      if (error.kind == AvBaseFailureKind.notFound) return null;
      rethrow;
    }
  }

  @override
  void close() => client.close();

  ScrapeWorkDetails _mapDetails(AvBaseWorkDetails details) {
    final catalogEvidence = details.catalogEvidence.isEmpty
        ? [
            ScrapeCatalogWorkEvidence.fromDetails(
              source: id,
              code: details.code,
              title: details.title,
              manufacturer: details.studio,
              label: details.publisher,
              series: details.series,
              provenanceFacts: details.provenanceFacts,
            ),
          ]
        : details.catalogEvidence;
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
      description: details.provenanceFacts.description,
      includedWorks: details.provenanceFacts.includedWorks,
      parentWorks: details.provenanceFacts.parentWorks,
      genres: details.provenanceFacts.genres,
      provenanceFacts: details.provenanceFacts,
      coPerformance: details.provenanceFacts.coPerformance,
      imageUris: const [],
      originalImageEvidenceUris: details.originalImageEvidenceUris,
      catalogEvidence: catalogEvidence,
    );
  }
}
