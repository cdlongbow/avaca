import 'package:avaca/player/player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('screen exposes the production chrome without a route', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          controller: controller,
          request: _request,
          labels: _labels,
          onBack: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byKey(const Key('player-back')), findsOneWidget);
    expect(find.byKey(const Key('player-work-code')), findsOneWidget);
    expect(find.byKey(const Key('player-timeline')), findsOneWidget);
    expect(find.byKey(const Key('player-play-pause')), findsOneWidget);
    expect(find.byKey(const Key('player-speed')), findsOneWidget);
    expect(find.byKey(const Key('player-subtitle')), findsOneWidget);
    expect(find.byKey(const Key('player-fullscreen')), findsOneWidget);
    expect(find.text('TEST-UI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('subtitle menu contains Off and discovered tracks', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          controller: controller,
          request: _request,
          labels: _labels,
          onBack: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.byKey(const Key('player-subtitle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-subtitle-option-off')), findsOneWidget);
    expect(find.byKey(const Key('player-subtitle-option-ass')), findsOneWidget);
    expect(find.byKey(const Key('player-subtitle-option-ssa')), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-subtitle-option-ssa')));
    await tester.pumpAndSettle();
    expect(controller.state.selectedSubtitleTrackId, 'ssa');
  });
}

AvacaPlayerController _controller() => AvacaPlayerController(
  platform: InMemoryPlayerPlatform(
    duration: const Duration(seconds: 20),
    subtitleTracks: const [
      PlayerSubtitleTrack(
        id: 'ass',
        title: 'ASS',
        format: PlayerSubtitleFormat.ass,
      ),
      PlayerSubtitleTrack(
        id: 'ssa',
        language: 'zh',
        format: PlayerSubtitleFormat.ssa,
      ),
    ],
  ),
);

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

const _request = PlayerLaunchRequest(
  workCode: 'TEST-UI',
  source: LocalPlayerMediaSource('fixture.mkv'),
);
