import '../../models/scrape_source_id.dart';
import '../scrape/scrape_models.dart';
import '../scrape/scrape_source.dart';
import 'javbus_client.dart';
import 'javbus_models.dart';

final class JavBusScrapeSource implements ScrapeSource {
  JavBusScrapeSource(this.client);

  final JavBusClient client;

  @override
  ScrapeSourceId get id => ScrapeSourceId.javbus;

  @override
  Future<ScrapeWorkDetails?> fetchWorkDetailsByCode(
    String canonicalCode,
  ) async {
    try {
      return _mapDetails(await client.fetchWorkDetailsByCode(canonicalCode));
    } on JavBusRequestException catch (error) {
      if (error.kind == JavBusFailureKind.notFound) return null;
      rethrow;
    }
  }

  @override
  void close() => client.close();

  ScrapeWorkDetails _mapDetails(JavBusWorkDetails details) {
    final catalogEvidence = details.catalogEvidence.isEmpty
        ? [
            ScrapeCatalogWorkEvidence.fromDetails(
              source: id,
              code: details.rawCode ?? details.code,
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
      code: details.rawCode ?? details.code,
      rawCode: details.rawCode ?? details.code,
      title: details.title,
      releaseDate: details.releaseDate,
      durationMinutes: details.durationMinutes,
      studio: details.studio,
      publisher: details.publisher,
      series: details.series,
      performers: details.performers,
      description: details.provenanceFacts.description,
      includedWorks: details.provenanceFacts.includedWorks,
      parentWorks: details.provenanceFacts.parentWorks,
      genres: details.provenanceFacts.genres,
      provenanceFacts: details.provenanceFacts,
      coPerformance: details.provenanceFacts.coPerformance,
      performerCount: details.performers?.length,
      originalImageEvidenceUris: details.originalImageEvidenceUris,
      catalogEvidence: catalogEvidence,
    );
  }
}
