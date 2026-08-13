import '../scrape/scrape_models.dart';
import '../scrape/scrape_source.dart';
import '../../models/scrape_source_settings.dart';
import 'javbus_client.dart';
import 'javbus_models.dart';

final class JavBusScrapeSource implements ScrapeSource {
  JavBusScrapeSource(this.client);

  final JavBusClient client;

  @override
  ScrapeSourceId get id => ScrapeSourceId.javbus;

  @override
  Future<List<ScrapeActressSearchResult>> searchActresses(String name) async {
    final results = await client.searchActresses(name);
    return results
        .map(
          (result) => ScrapeActressSearchResult(
            source: id,
            name: result.name,
            uri: result.uri,
          ),
        )
        .toList(growable: false);
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
    final firstJavBusPage = JavBusActressPage(
      details: firstPage.details,
      works: firstPage.works
          .map(
            (work) => JavBusWorkSummary(
              code: work.code ?? '',
              title: work.title,
              detailUri: work.detailUri,
              releaseDate: work.releaseDate,
            ),
          )
          .toList(growable: false),
      pageCount: firstPage.pageCount,
    );
    final works = await client.fetchAllActressWorks(
      actress.uri,
      firstPage: firstJavBusPage,
      isCancelled: isCancelled,
    );
    return works.map(_summary).toList(growable: false);
  }

  @override
  Future<ScrapeWorkDetails> fetchWorkDetails(ScrapeWorkSummary work) async {
    final details = await client.fetchWorkDetails(work.detailUri);
    return ScrapeWorkDetails(
      source: id,
      code: details.code,
      title: details.title,
      releaseDate: details.releaseDate,
      durationMinutes: details.durationMinutes,
      studio: details.studio,
      publisher: details.publisher,
      series: details.series,
      performerCount: details.actressUris.length,
    );
  }

  @override
  bool acceptsImageUri(Uri uri) {
    final port = uri.hasPort ? uri.port : 443;
    final imagePath = uri.path.toLowerCase();
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        uri.host.toLowerCase() == 'www.javbus.com' &&
        port == 443 &&
        imagePath.startsWith('/pics/actress/') &&
        !imagePath.endsWith('/nowprinting.gif');
  }

  @override
  void close() {
    client.close();
  }

  ScrapeWorkSummary _summary(JavBusWorkSummary work) {
    return ScrapeWorkSummary(
      source: id,
      code: work.code,
      title: work.title,
      detailUri: work.detailUri,
      releaseDate: work.releaseDate,
    );
  }
}
