import '../core/database.dart';
import '../models/scrape_source_id.dart';
import '../services/avbase/avbase_client.dart';
import '../services/avbase/avbase_scrape_source.dart';
import '../services/avbase/avbase_transport.dart';
import '../services/avwiki/avwiki_client.dart';
import '../services/avwiki/avwiki_scrape_source.dart';
import '../services/avwiki/avwiki_transport.dart';
import '../services/javbus/javbus_client.dart';
import '../services/javbus/javbus_scrape_source.dart';
import '../services/javbus/javbus_verification.dart';
import '../services/scrape/scrape_source.dart';

/// Creates only the exact-code metadata adapters used by folder imports.
/// There is intentionally no actress search, catalog pagination, or source
/// preference state in this factory.
class LibrarySourceFactory {
  LibrarySourceFactory({required this.db});

  final AppDatabase db;

  Future<Map<ScrapeSourceId, ScrapeSource>> createSources({
    JavBusVerificationHandler? verificationHandler,
  }) async {
    String? cookies;
    try {
      cookies = await db.getSetting('javbus_cookies');
    } catch (_) {
      cookies = null;
    }
    final javBusTransport = HttpJavBusTransport(
      initialCookieHeader: cookies,
      verificationHandler: verificationHandler,
    );
    return {
      ScrapeSourceId.javbus: JavBusScrapeSource(
        JavBusClient(transport: javBusTransport),
      ),
      ScrapeSourceId.avbase: AvBaseScrapeSource(
        AvBaseClient(transport: HttpAvBaseTransport()),
      ),
      ScrapeSourceId.avwiki: AvWikiScrapeSource(
        AvWikiClient(transport: HttpAvWikiTransport()),
      ),
    };
  }
}
