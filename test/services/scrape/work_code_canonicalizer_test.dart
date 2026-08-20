import 'package:avaca/services/scrape/work_code_canonicalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes full-width and Unicode dash variants', () {
    expect(canonicalizeWorkCode(' ｓｔａｒＴ－４８９ '), 'START-489');
    expect(canonicalizeWorkCode('START–489'), 'START-489');
    expect(canonicalizeWorkCode(''), isNull);
    expect(canonicalizeWorkCode('---'), isNull);
  });

  test('normalizes separatorless codes through a generic identity grammar', () {
    final cases = <String, String>{
      'SSIS875': 'SSIS-875',
      'SSIS163': 'SSIS-163',
      'SSIS252': 'SSIS-252',
      'SSIS308': 'SSIS-308',
      'SIVR00303': 'SIVR-303',
      'SIVR00394': 'SIVR-394',
      'SIVR00427': 'SIVR-427',
      'SIVR00380': 'SIVR-380',
      'SONE00687': 'SONE-687',
      'RBB00321': 'RBB-321',
      'RBB00318': 'RBB-318',
    };

    for (final entry in cases.entries) {
      expect(canonicalizeWorkCode(entry.key), entry.value);
    }
  });

  test(
    'normalizes arbitrary simple prefixes without prefix-specific rules',
    () {
      final prefixes = ['ABC', 'XYZ', 'TEST', 'LONGPREFIX'];
      final variants = <String Function(String, String)>[
        (prefix, number) => '$prefix-$number',
        (prefix, number) => '${prefix.toLowerCase()}$number',
        (prefix, number) => '$prefix.${number.padLeft(5, '0')}',
        (prefix, number) => '$prefix ${number.padLeft(5, '0')}',
      ];

      for (final prefix in prefixes) {
        for (final variant in variants) {
          final value = variant(prefix, '27');
          expect(canonicalizeWorkCode(value), '$prefix-027');
        }
      }
    },
  );

  test('canonicalization is idempotent for generated simple identities', () {
    for (final prefix in ['ABC', 'XYZ', 'TEST', 'LONGPREFIX']) {
      for (final number in ['1', '27', '303', '00427']) {
        final canonical = canonicalizeWorkCode('$prefix$number');
        expect(canonical, isNotNull);
        expect(canonicalizeWorkCode(canonical), canonical);
      }
    }
  });

  test('deduplicates equivalent aliases for any alphabetic prefix', () {
    expect(canonicalizeWorkCode('1start00023'), 'START-023');
    expect(canonicalizeWorkCode('START-023'), 'START-023');
    expect(canonicalizeWorkCode('1start00408'), 'START-408');
    expect(canonicalizeWorkCode('START-408'), 'START-408');
    expect(canonicalizeWorkCode('M-2'), 'M-002');
    expect(canonicalizeWorkCode('1START00427'), 'START-427');
    expect(canonicalizeWorkCode('1stzy00017'), 'STZY-017');
    expect(canonicalizeWorkCode('STZY-017'), 'STZY-017');
    expect(canonicalizeWorkCode('3DSVR-1947'), 'DSVR-1947');
    expect(canonicalizeWorkCode('DSVR-1947'), 'DSVR-1947');
    expect(canonicalizeWorkCode('START-408,427'), 'START-408,427');
    expect(canonicalizeWorkCode('START-408-V'), 'START-408-V');
    expect(canonicalizeWorkCode('FC2'), 'FC2');
    expect(canonicalizeWorkCode('AB12'), 'AB12');
    expect(canonicalizeWorkCode('FC2-PPV_123-999'), 'FC2-PPV_123-999');
    expect(canonicalizeWorkCode('START-408'), isNot('START-427'));
  });

  test('protects ambiguous numeric-leading cores from destructive merging', () {
    expect(canonicalizeWorkCode('1FC2'), '1FC2');
    expect(canonicalizeWorkCode('1AB12'), '1AB12');
    expect(canonicalizeWorkCode('1FC2'), isNot('FC-002'));
    expect(canonicalizeWorkCode('1AB12'), isNot('AB-012'));
    expect(canonicalizeWorkCode('1ABC123'), 'ABC-123');
  });

  test(
    'extracts one normalized Prefix from the existing work-code identity',
    () {
      expect(canonicalWorkCodePrefix('sone-833'), 'SONE');
      expect(canonicalWorkCodePrefix('START00023'), 'START');
      expect(canonicalWorkCodePrefix('ABF-183'), 'ABF');
      expect(canonicalWorkCodePrefix('SEI-007'), 'SEI');
      expect(canonicalWorkCodePrefix('FC2'), isNull);
      expect(normalizeWorkImagePrefix(' ｓＯｎｅ '), 'SONE');
    },
  );
}
