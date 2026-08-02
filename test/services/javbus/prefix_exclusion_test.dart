import 'package:avaca/services/javbus/prefix_exclusion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes display values but accepts complex nonempty prefixes', () {
    final exclusions = PrefixExclusion([
      ' ab12 ',
      'AB12',
      '123-xy',
      ' fc2_ppv- ',
      '',
      '   ',
    ]);

    expect(exclusions.values, ['AB12', '123-XY', 'FC2_PPV-']);
  });

  test('matches startsWith without regard to either side casing', () {
    final exclusions = PrefixExclusion(['ab12', 'Fc2-123']);

    expect(exclusions.matches('AB12-999'), isTrue);
    expect(exclusions.matches('fc2-123_456'), isTrue);
    expect(exclusions.matches('AB13-999'), isFalse);
  });
}
