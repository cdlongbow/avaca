import '../../models/scrape_source_id.dart';
import 'scrape_models.dart';

abstract interface class ScrapeSource {
  ScrapeSourceId get id;

  Future<ScrapeWorkDetails?> fetchWorkDetailsByCode(String canonicalCode);

  void close();
}
