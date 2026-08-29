import '../../models/scrape_source_id.dart';
import '../scrape/scrape_models.dart';
import '../scrape/scrape_source.dart';
import 'avwiki_client.dart';
import 'avwiki_models.dart';

final class AvWikiScrapeSource implements ScrapeSource {
  AvWikiScrapeSource(this.client);

  final AvWikiClient client;

  @override
  ScrapeSourceId get id => ScrapeSourceId.avwiki;

  @override
  Future<ScrapeWorkDetails?> fetchWorkDetailsByCode(
    String canonicalCode,
  ) async {
    try {
      return _mapDetails(await client.fetchWorkDetailsByCode(canonicalCode));
    } on AvWikiRequestException catch (error) {
      if (error.kind == AvWikiFailureKind.notFound) return null;
      rethrow;
    }
  }

  @override
  void close() => client.close();

  ScrapeWorkDetails _mapDetails(AvWikiWorkDetails details) {
    final catalogEvidence = details.catalogEvidence.isEmpty
        ? [
            ScrapeCatalogWorkEvidence.fromDetails(
              source: id,
              code: details.code,
              title: details.title,
              manufacturer: details.studio,
              label: details.publisher,
              series: details.series,
              description: details.description,
              provenanceFacts: details.provenanceFacts,
            ),
          ]
        : details.catalogEvidence;
    return ScrapeWorkDetails(
      source: id,
      code: details.code,
      rawCode: details.rawCode ?? details.code,
      title: details.title,
      releaseDate: details.releaseDate,
      studio: details.studio,
      publisher: details.publisher,
      series: details.series,
      performerCount: details.performerCount,
      performers: details.performers,
      description: details.description,
      genres: details.genres,
      provenanceFacts: details.provenanceFacts,
      coPerformance: details.provenanceFacts.coPerformance,
      externalIdentity: details.externalIdentity,
      imageUris: const [],
      originalImageEvidenceUris: const [],
      catalogEvidence: catalogEvidence,
    );
  }
}
