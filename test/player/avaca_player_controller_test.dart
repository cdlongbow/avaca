import 'dart:async';

import 'package:avaca/player/player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('controller owns one lazy in-memory session and state', () async {
    final platform = InMemoryPlayerPlatform(
      duration: const Duration(seconds: 10),
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
    );
    final controller = AvacaPlayerController(platform: platform);

    expect(platform.sessions, isEmpty);
    await controller.open(
      const PlayerLaunchRequest(
        workCode: 'TEST-001',
        source: LocalPlayerMediaSource('fixture.mkv'),
        initialPosition: Duration(seconds: 3),
        preferredSubtitleTrackId: 'ass',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(platform.sessions, hasLength(1));
    expect(controller.state.phase, PlayerPhase.ready);
    expect(controller.state.position, const Duration(seconds: 3));
    expect(controller.state.selectedSubtitleTrackId, 'ass');

    await controller.play();
    expect(controller.state.phase, PlayerPhase.playing);
    await controller.pause();
    expect(controller.state.phase, PlayerPhase.paused);

    await controller.seekRelative(const Duration(seconds: 20));
    expect(controller.state.position, const Duration(seconds: 10));
    await controller.seekRelative(const Duration(seconds: -20));
    expect(controller.state.position, Duration.zero);

    await controller.setPersistentSpeed(1.5);
    await controller.beginTemporarySpeed();
    expect(controller.state.persistentSpeed, 1.5);
    expect(controller.state.effectiveSpeed, 2.0);
    expect(platform.sessions.single.speed, 2.0);
    expect(controller.state.phase, PlayerPhase.paused);
    await controller.endTemporarySpeed();
    expect(controller.state.effectiveSpeed, 1.5);

    await controller.selectSubtitle(null);
    expect(controller.state.selectedSubtitleTrackId, isNull);
    await controller.setFullscreen(true);
    expect(controller.state.fullscreen, isTrue);

    await controller.close();
    await controller.close();
    expect(controller.isDisposed, isTrue);
    expect(platform.sessions.single.closed, isTrue);
  });

  test(
    'reopen closes the previous session and creates one replacement',
    () async {
      final platform = InMemoryPlayerPlatform();
      final controller = AvacaPlayerController(platform: platform);
      const request = PlayerLaunchRequest(
        workCode: 'TEST-002',
        source: LocalPlayerMediaSource('fixture.mkv'),
      );

      await controller.open(request);
      final firstId = controller.sessionId;
      await controller.open(request);

      expect(platform.sessions, hasLength(2));
      expect(platform.sessions.first.closed, isTrue);
      expect(controller.sessionId, isNot(firstId));
      expect(platform.sessions.last.closed, isFalse);

      await controller.close();
    },
  );

  test('native error remains visible when a stale state follows it', () async {
    final platform = _ErrorRacePlatform();
    final controller = AvacaPlayerController(platform: platform);

    await controller.open(
      const PlayerLaunchRequest(
        workCode: 'TEST-ERROR-RACE',
        source: LocalPlayerMediaSource('missing.mkv'),
      ),
    );
    platform.session.emitErrorThenLoading();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.phase, PlayerPhase.error);
    expect(controller.state.error, isNotNull);
    expect(controller.state.diagnostics.droppedEvents, 1);

    await controller.close();
  });

  test(
    'native initial subtitle selection is reflected in the menu state',
    () async {
      final platform = _ErrorRacePlatform();
      final controller = AvacaPlayerController(platform: platform);

      await controller.open(
        const PlayerLaunchRequest(
          workCode: 'TEST-SUBTITLE-INITIAL',
          source: LocalPlayerMediaSource('fixture.mkv'),
        ),
      );
      platform.session.emitInitialSubtitleSelection();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.selectedSubtitleTrackId, '1');
      expect(controller.state.subtitleTracks, hasLength(1));

      await controller.close();
    },
  );
}

final class _ErrorRacePlatform implements PlayerPlatform {
  late final _ErrorRaceSession session;

  @override
  Future<PlayerPlatformSession> createSession(String sessionId) async {
    session = _ErrorRaceSession(sessionId);
    return session;
  }
}

final class _ErrorRaceSession implements PlayerPlatformSession {
  _ErrorRaceSession(this.sessionId);

  @override
  final String sessionId;

  final StreamController<PlayerPlatformEvent> _events =
      StreamController<PlayerPlatformEvent>.broadcast();

  @override
  final surface = const PlayerSurfaceDescriptor(type: PlayerSurfaceType.none);

  @override
  Stream<PlayerPlatformEvent> get events => _events.stream;

  @override
  Future<void> open(PlayerLaunchRequest request) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position, {int generation = 0}) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> selectSubtitle(String? trackId) async {}

  @override
  Future<void> setFullscreen(bool fullscreen) async {}

  @override
  Future<PlayerDiagnostics> getDiagnostics() async =>
      PlayerDiagnostics(sessionId: sessionId);

  @override
  Future<void> close() async => _events.close();

  void emitErrorThenLoading() {
    _events.add(
      PlayerPlatformErrorEvent(
        sessionId: sessionId,
        sequence: 1,
        error: const PlayerError(
          type: PlayerErrorType.mediaOpenFailed,
          localizedMessageKey: 'playerErrorMediaOpenFailed',
          diagnosticCode: 'media_open_failed',
        ),
      ),
    );
    _events.add(
      PlayerPlatformStateEvent(
        sessionId: sessionId,
        sequence: 2,
        phase: PlayerPhase.loading,
      ),
    );
  }

  void emitInitialSubtitleSelection() {
    _events.add(
      PlayerPlatformStateEvent(
        sessionId: sessionId,
        sequence: 1,
        phase: PlayerPhase.ready,
        duration: const Duration(seconds: 1),
        tracks: const [
          PlayerSubtitleTrack(
            id: '1',
            language: 'und',
            format: PlayerSubtitleFormat.ass,
          ),
        ],
        selectedSubtitleTrackId: '1',
      ),
    );
  }
}
