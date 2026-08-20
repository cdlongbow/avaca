import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/services/scrape/scrape_source_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AvBase settings round-trip and all work source resolution', () {
    const settings = ScrapeSourceSettings(
      actressDetailsSource: ScrapeSourceId.avbase,
      worksSource: WorksSourceSelection.all,
    );

    expect(
      ScrapeSourceSettings.decode(settings.encode()).actressDetailsSource,
      ScrapeSourceId.avbase,
    );
    expect(
      ScrapeSourceSettings.decode(settings.encode()).worksSource,
      WorksSourceSelection.all,
    );
    expect(ScrapeSourceRegistry.resolveWorksSources(WorksSourceSelection.all), [
      ScrapeSourceId.javbus,
      ScrapeSourceId.avbase,
    ]);
  });

  test(
    'legacy Minnano works selection never routes Minnano to works scrape',
    () {
      expect(
        ScrapeSourceRegistry.resolveWorksSources(
          WorksSourceSelection.minnanoAv,
        ),
        [ScrapeSourceId.javbus],
      );
    },
  );
}
