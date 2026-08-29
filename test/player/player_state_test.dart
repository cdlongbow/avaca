import 'package:avaca/player/player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('temporary speed is an effective override', () {
    const state = PlayerState(persistentSpeed: 1.5, temporarySpeed: 2.0);

    expect(state.effectiveSpeed, 2.0);
    expect(state.copyWith(temporarySpeed: null).effectiveSpeed, 1.5);
  });

  test('state copyWith can clear nullable fields', () {
    const error = PlayerError(
      type: PlayerErrorType.seekFailure,
      localizedMessageKey: 'playerErrorSeekFailed',
      diagnosticCode: 'seek/failure',
      recoverable: true,
    );
    const state = PlayerState(error: error, selectedSubtitleTrackId: 'ass');

    final cleared = state.copyWith(error: null, selectedSubtitleTrackId: null);

    expect(cleared.error, isNull);
    expect(cleared.selectedSubtitleTrackId, isNull);
    expect(error.sanitizedDiagnosticCode, 'seek_failure');
    expect(error.toString(), isNot(contains('seek/failure')));
  });

  test('diagnostics copyWith can clear session data', () {
    const diagnostics = PlayerDiagnostics(
      sessionId: 'session-1',
      lastEvent: 'ready',
    );

    final cleared = diagnostics.copyWith(sessionId: null, lastEvent: null);

    expect(cleared.sessionId, isNull);
    expect(cleared.lastEvent, isNull);
  });
}
