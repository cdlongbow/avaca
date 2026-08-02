import 'package:avaca/models/work_scrape_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips settings while preserving complex uppercase prefixes', () {
    const options = WorkScrapeOptions(
      syncDetails: false,
      replaceActressImage: true,
      fillMissingOnly: false,
      excludedPrefixes: ['FC2-PPV_123', '1PON'],
    );

    expect(WorkScrapeOptions.decode(options.encode()).excludedPrefixes, [
      'FC2-PPV_123',
      '1PON',
    ]);
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
  });
}
