import 'package:avaca/player/player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('in-memory platform exposes session and event contract', () async {
    final platform = InMemoryPlayerPlatform(
      duration: const Duration(seconds: 5),
    );
    final session = await platform.createSession('session-1');
    final events = <PlayerPlatformEvent>[];
    final subscription = session.events.listen(events.add);

    await session.open(
      const PlayerLaunchRequest(
        workCode: 'TEST-003',
        source: LocalPlayerMediaSource('fixture.mkv'),
      ),
    );
    await session.seek(const Duration(seconds: 2), generation: 7);
    await session.setSpeed(2.0);
    await session.selectSubtitle(null);
    await session.setFullscreen(true);
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(5));
    expect(
      events.map((event) => event.sequence),
      orderedEquals([1, 2, 3, 4, 5]),
    );
    expect((events[1] as PlayerPlatformStateEvent).seekGeneration, 7);
    expect(
      (events[3] as PlayerPlatformStateEvent).subtitleSelectionChanged,
      isTrue,
    );
    expect((events[4] as PlayerPlatformStateEvent).fullscreen, isTrue);
    expect(session.surface.type, PlayerSurfaceType.none);

    await subscription.cancel();
    await session.close();
  });
}
