import 'package:avaca/models/scrape_exclusion_policy.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips exclusion settings and provenance rules', () {
    const options = WorkScrapeOptions(
      syncDetails: false,
      replaceActressImage: true,
      fillMissingOnly: false,
      excludedPrefixes: ['FC2-PPV_123', '1PON'],
      scrapeAliases: true,
      autoExcludeDerivedWorks: false,
      managedFamilyModes: {'OFJE': ManagedFamilyMode.reviewPrior},
      exactAllows: [ScrapeExactAllowRule(code: 'OFJE-605')],
      exactDenies: [ScrapeExactDenyRule(code: 'FC2-001')],
    );

    final decoded = WorkScrapeOptions.decode(options.encode());
    expect(decoded.excludedPrefixes, ['FC2-PPV_123', '1PON']);
    expect(decoded.scrapeAliases, isTrue);
    expect(decoded.managedFamilyModes['OFJE'], ManagedFamilyMode.reviewPrior);
    expect(decoded.exactAllows.single.normalizedCode, 'OFJE-605');
    expect(decoded.autoExcludeDerivedWorks, isFalse);
    expect(decoded.exactDenies.single.normalizedCode, 'FC2-001');
  });

  test('normalizes persisted prefixes without limiting their characters', () {
    final options = WorkScrapeOptions.decode(
      '{"excludedPrefixes":[" fc2-ppv_123 ","1pon","FC2-PPV_123"]}',
    );

    expect(options.excludedPrefixes, ['FC2-PPV_123', '1PON']);
  });

  test('uses safe defaults for malformed settings', () {
    final options = WorkScrapeOptions.decode('not-json');

    expect(options.syncDetails, isTrue);
    expect(options.replaceActressImage, isFalse);
    expect(options.fillMissingOnly, isTrue);
    expect(options.excludedPrefixes, isEmpty);
    expect(options.managedFamilyModes, isEmpty);
    expect(options.exactAllows, isEmpty);
  });

  test('ignores the removed actress-count setting', () {
    final options = WorkScrapeOptions.decode(
      '{"maxActressCount":2,"excludedPrefixes":["ABC"]}',
    );

    expect(options.excludedPrefixes, ['ABC']);
    expect(options.encode(), isNot(contains('maxActressCount')));
  });
}
