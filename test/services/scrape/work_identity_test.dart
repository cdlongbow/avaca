import 'package:avaca/services/scrape/work_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('title identity only removes explicit 特典版 markers', () {
    final ordinary = scrapeTitleIdentity('  普通作品  名稱 ');
    final special = scrapeTitleIdentity('【特典版】 普通作品 名稱');
    final asciiSpecial = scrapeTitleIdentity('[特典版] 普通作品 名稱');

    expect(ordinary.key, '普通作品 名稱');
    expect(ordinary.isSpecialEdition, isFalse);
    expect(special.key, ordinary.key);
    expect(special.isSpecialEdition, isTrue);
    expect(asciiSpecial.key, ordinary.key);
    expect(scrapeTitleIdentity('普通作品 (別名)').key, '普通作品 (別名)');
    expect(scrapeTitleIdentity('作品 A－B').key, isNot('作品 A-B'));
  });

  test('work code surface normalization does not infer aliases', () {
    expect(normalizeScrapeWorkCodeSurface(' start－489 '), 'START-489');
    expect(normalizeScrapeWorkCodeSurface('H_346REBD00975'), isNot('REBD-975'));
    expect(
      normalizeScrapeWorkCodeSurface('1STZY00017'),
      isNot(normalizeScrapeWorkCodeSurface('STZY-017')),
    );
    expect(normalizeScrapeWorkCodeSurface('   '), isNull);
  });

  test('Rebecca classification is publisher based and exact', () {
    expect(isRebeccaPublisher(' Rebecca '), isTrue);
    expect(isRebeccaPublisher('REBECCA'), isTrue);
    expect(isRebeccaPublisher('REBD'), isFalse);
    expect(isRebeccaPublisher('H_346REBD00975'), isFalse);
    expect(isRebeccaPublisher('Rebecca Studio'), isFalse);
  });
}
