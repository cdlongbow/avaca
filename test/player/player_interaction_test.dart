import 'package:avaca/player/player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile single tap does nothing and double tap seeks by zone', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await controller.open(_request);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 300,
          child: PlayerInteractionLayer(
            controller: controller,
            seekSeconds: 5,
            holdSpeed: 2,
          ),
        ),
      ),
    );
    await tester.pump();
    await controller.seekTo(const Duration(seconds: 10));

    await tester.tapAt(const Offset(150, 150));
    await tester.pump();
    expect(controller.state.phase, PlayerPhase.ready);

    final zone = find.byKey(const Key('player-zone-left'));
    expect(tester.getRect(zone).size, isNot(Size.zero));
    final firstTap = await tester.startGesture(tester.getCenter(zone));
    await tester.pump(const Duration(milliseconds: 100));
    await firstTap.up();
    await tester.pump(const Duration(milliseconds: 100));
    final secondTap = await tester.startGesture(tester.getCenter(zone));
    await tester.pump(const Duration(milliseconds: 100));
    await secondTap.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.state.position, const Duration(seconds: 5));
  });

  testWidgets('long press temporarily changes rate and restores it', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await controller.open(_request);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 300,
          child: PlayerInteractionLayer(
            controller: controller,
            seekSeconds: 5,
            holdSpeed: 2,
          ),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(const Offset(150, 150));
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.state.effectiveSpeed, 2.0);
    expect(controller.state.phase, PlayerPhase.ready);
    await gesture.up();
    await tester.pump();
    expect(controller.state.effectiveSpeed, 1.0);
  });

  testWidgets('desktop empty-video click toggles playback', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await controller.open(_request);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 300,
          child: PlayerInteractionLayer(
            controller: controller,
            seekSeconds: 5,
            holdSpeed: 2,
            desktop: true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('player-zone-right')));
    await tester.pumpAndSettle();
    expect(controller.state.phase, PlayerPhase.playing);
  });

  testWidgets('desktop surface does not use mobile hold speed', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await controller.open(_request);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 300,
          child: PlayerInteractionLayer(
            controller: controller,
            seekSeconds: 5,
            holdSpeed: 2,
            desktop: true,
          ),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(const Offset(150, 150));
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.state.effectiveSpeed, 1.0);
    await gesture.up();
  });
}

AvacaPlayerController _controller() => AvacaPlayerController(
  platform: InMemoryPlayerPlatform(duration: const Duration(seconds: 20)),
);

const _request = PlayerLaunchRequest(
  workCode: 'TEST-INTERACTION',
  source: LocalPlayerMediaSource('fixture.mkv'),
);
