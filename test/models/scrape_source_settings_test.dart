import 'package:avaca/models/scrape_source_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to Minnano details and JavBus works source', () {
    const settings = ScrapeSourceSettings();

    expect(settings.actressDetailsSource, ScrapeSourceId.minnanoAv);
    expect(settings.worksSource, WorksSourceSelection.javbus);
    expect(settings.aliasSource, ScrapeSourceId.avbase);
  });

  test('round trips selections and tolerates malformed values', () {
    const settings = ScrapeSourceSettings(
      actressDetailsSource: ScrapeSourceId.javbus,
      worksSource: WorksSourceSelection.minnanoAv,
      aliasSource: ScrapeSourceId.avbase,
    );

    expect(
      ScrapeSourceSettings.decode(settings.encode()).actressDetailsSource,
      ScrapeSourceId.javbus,
    );
    expect(
      ScrapeSourceSettings.decode(settings.encode()).worksSource,
      WorksSourceSelection.minnanoAv,
    );
    expect(
      ScrapeSourceSettings.decode(settings.encode()).aliasSource,
      ScrapeSourceId.avbase,
    );
    expect(
      ScrapeSourceSettings.decode('{"worksSource":"unknown"}').worksSource,
      WorksSourceSelection.javbus,
    );
    expect(
      ScrapeSourceSettings.decode('not-json').actressDetailsSource,
      ScrapeSourceId.minnanoAv,
    );
  });
}
