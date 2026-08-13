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
      WorksSourceSelection.all => List.unmodifiable(aggregatePriority),
      WorksSourceSelection.javbus => const [ScrapeSourceId.javbus],
      WorksSourceSelection.minnanoAv => const [ScrapeSourceId.minnanoAv],
    };
  }
}
