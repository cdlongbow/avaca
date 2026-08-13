import 'package:avaca/services/scrape/work_code_canonicalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes full-width and Unicode dash variants', () {
    expect(canonicalizeWorkCode(' ｓｔａｒＴ－４８９ '), 'START-489');
    expect(canonicalizeWorkCode('START–489'), 'START-489');
    expect(canonicalizeWorkCode(''), isNull);
    expect(canonicalizeWorkCode('---'), isNull);
  });

  test('deduplicates equivalent DMM START aliases without merging works', () {
    expect(canonicalizeWorkCode('1start00408'), 'START-408');
    expect(canonicalizeWorkCode('START-408'), 'START-408');
    expect(canonicalizeWorkCode('1START00427'), 'START-427');
    expect(canonicalizeWorkCode('START-408,427'), 'START-408,427');
    expect(canonicalizeWorkCode('START-408'), isNot('START-427'));
  });
}
