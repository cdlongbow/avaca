import '../../models/scrape_source_settings.dart';

class ScrapeSourceRegistry {
  const ScrapeSourceRegistry._();

  static const List<ScrapeSourceId> aggregatePriority = [
    ScrapeSourceId.minnanoAv,
    ScrapeSourceId.javbus,
  ];

  static List<ScrapeSourceId> resolveWorksSources(
    WorksSourceSelection selection,
  ) {
    return switch (selection) {
      WorksSourceSelection.all => const [ScrapeSourceId.javbus],
      WorksSourceSelection.javbus => const [ScrapeSourceId.javbus],
      WorksSourceSelection.minnanoAv => const [ScrapeSourceId.javbus],
    };
  }
}
