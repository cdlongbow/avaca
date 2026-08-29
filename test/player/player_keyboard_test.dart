import 'package:avaca/player/player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop shortcuts seek and toggle without RawKeyboard', (
    tester,
  ) async {
    final controller = AvacaPlayerController(
      platform: InMemoryPlayerPlatform(duration: const Duration(seconds: 20)),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: PlayerScreen(
          controller: controller,
          request: const PlayerLaunchRequest(
            workCode: 'TEST-KEYBOARD',
            source: LocalPlayerMediaSource('fixture.mkv'),
            initialPosition: Duration(seconds: 10),
          ),
          labels: _labels,
          onBack: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(controller.state.phase, PlayerPhase.playing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.state.position, const Duration(seconds: 5));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.state.position, const Duration(seconds: 10));
  });
}

const _labels = PlayerUiLabels(
  back: 'Back',
  play: 'Play',
  pause: 'Pause',
  speed: 'Speed',
  subtitle: 'Subtitles',
  fullscreen: 'Fullscreen',
  exitFullscreen: 'Exit fullscreen',
  subtitleOff: 'Off',
  holdSpeed: 'Hold speed',
  position: 'Position',
  error: 'Unable to play this video',
);
