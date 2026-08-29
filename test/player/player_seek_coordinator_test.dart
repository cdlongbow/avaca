import 'package:avaca/player/player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seek generations are latest-wins', () {
    final coordinator = PlayerSeekCoordinator();

    final first = coordinator.next();
    final second = coordinator.next();

    expect(first, 1);
    expect(second, 2);
    expect(coordinator.accepts(first), isFalse);
    expect(coordinator.accepts(second), isTrue);
  });
}
