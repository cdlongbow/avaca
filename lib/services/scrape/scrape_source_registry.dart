import '../../models/scrape_source_settings.dart';

class ScrapeSourceRegistry {
  const ScrapeSourceRegistry._();

  static const List<ScrapeSourceId> aggregatePriority = [
    ScrapeSourceId.minnanoAv,
    ScrapeSourceId.javbus,
    ScrapeSourceId.avbase,
  ];

  static const List<ScrapeSourceId> worksPriority = [
    ScrapeSourceId.javbus,
    ScrapeSourceId.avbase,
  ];

  static List<ScrapeSourceId> resolveWorksSources(
    WorksSourceSelection selection,
  ) {
    return switch (selection) {
      WorksSourceSelection.all => const [
        ScrapeSourceId.javbus,
        ScrapeSourceId.avbase,
      ],
      WorksSourceSelection.javbus => const [ScrapeSourceId.javbus],
      WorksSourceSelection.avbase => const [ScrapeSourceId.avbase],
      // Legacy persisted value: never route Minnano into works scraping.
      WorksSourceSelection.minnanoAv => const [ScrapeSourceId.javbus],
    };
  }
}
