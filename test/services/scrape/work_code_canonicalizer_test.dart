import 'package:avaca/services/scrape/work_code_canonicalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes full-width and Unicode dash variants', () {
    expect(canonicalizeWorkCode(' ｓｔａｒＴ－４８９ '), 'START-489');
    expect(canonicalizeWorkCode('START–489'), 'START-489');
    expect(canonicalizeWorkCode(''), isNull);
    expect(canonicalizeWorkCode('---'), isNull);
  });
}
