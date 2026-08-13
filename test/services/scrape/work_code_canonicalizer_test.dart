import 'package:avaca/services/scrape/work_code_canonicalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes full-width and Unicode dash variants', () {
    expect(canonicalizeWorkCode(' ｓｔａｒＴ－４８９ '), 'START-489');
    expect(canonicalizeWorkCode('START–489'), 'START-489');
    expect(canonicalizeWorkCode(''), isNull);
    expect(canonicalizeWorkCode('---'), isNull);
  });

  test('deduplicates equivalent aliases for any alphabetic prefix', () {
    expect(canonicalizeWorkCode('1start00023'), 'START-023');
    expect(canonicalizeWorkCode('START-023'), 'START-023');
    expect(canonicalizeWorkCode('1start00408'), 'START-408');
    expect(canonicalizeWorkCode('START-408'), 'START-408');
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
}
