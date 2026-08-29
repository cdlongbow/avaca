import 'package:avaca/player/player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote source exposes raw request data but redacts diagnostics', () {
    final source = RemotePlayerMediaSource(
      uri: Uri.parse('https://user:pass@example.test/video.mkv?token=secret'),
      headers: const {
        'Authorization': 'Bearer secret-token',
        'Cookie': 'session=secret-cookie',
        'X-Trace': 'visible',
      },
      contentLength: 42,
      mimeType: 'video/x-matroska',
    );

    expect(source.toJson()['uri'], contains('token=secret'));
    final safe = source.toJson(redactSecrets: true);
    expect(safe['uri'], 'https://example.test/video.mkv');
    expect(safe['headers'], {
      'Authorization': '<redacted>',
      'Cookie': '<redacted>',
      'X-Trace': 'visible',
    });
    expect(source.toString(), isNot(contains('secret')));
    expect(source.sanitizedUri.userInfo, isEmpty);
  });

  test('local paths are not included in diagnostic text', () {
    const source = LocalPlayerMediaSource(r'C:\private\movie.mkv');

    expect(source.toJson()['path'], r'C:\private\movie.mkv');
    expect(source.toString(), isNot(contains('private')));
  });

  test('subtitle display priority is title, language, then id', () {
    const titled = PlayerSubtitleTrack(
      id: '0',
      title: '繁體字幕',
      language: 'zh',
      format: PlayerSubtitleFormat.ass,
    );
    const languageOnly = PlayerSubtitleTrack(
      id: '1',
      language: 'ja',
      format: PlayerSubtitleFormat.ssa,
    );
    const unnamed = PlayerSubtitleTrack(
      id: '2',
      format: PlayerSubtitleFormat.other,
    );
    const unknownLanguage = PlayerSubtitleTrack(
      id: '3',
      language: 'und',
      format: PlayerSubtitleFormat.ass,
    );

    expect(titled.displayLabel, '繁體字幕');
    expect(languageOnly.displayLabel, 'ja');
    expect(unnamed.displayLabel, 'Subtitle 2');
    expect(unknownLanguage.displayLabel, 'Subtitle 3');
  });
}
