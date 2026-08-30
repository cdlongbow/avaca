import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:avaca/library/library_media_locator.dart';

void main() {
  late Directory root;
  late Directory library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('avaca_locator_');
    library = Directory(p.join(root.path, 'library'))..createSync();
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('resolves Work-relative media beneath an authorized root', () async {
    final media = File(p.join(library.path, 'Actress', 'ABC-123', 'part.mp4'))
      ..createSync(recursive: true)
      ..writeAsStringSync('fixture');
    final locator = LibraryMediaLocator();

    final resolved = await locator.resolveMedia(
      libraryRoot: library.path,
      workRelativePath: 'Actress/ABC-123',
      mediaRelativePath: 'part.mp4',
      mediaPortableId: 'media-1',
    );

    expect(resolved.absolutePath, media.absolute.path);
    expect(resolved.mediaPortableId, 'media-1');
  });

  test('rejects traversal, absolute and drive-qualified paths', () async {
    final locator = LibraryMediaLocator();
    for (final value in <String>[
      '../escape.mp4',
      '/escape.mp4',
      'C:/escape.mp4',
    ]) {
      await expectLater(
        locator.resolveMedia(
          libraryRoot: library.path,
          workRelativePath: 'Actress/ABC-123',
          mediaRelativePath: value,
        ),
        throwsA(isA<LibraryLocatorFailure>()),
      );
    }
  });

  test('relative identity survives moving the absolute LibraryRoot', () async {
    final rootB = Directory(p.join(root.path, 'library-moved'))..createSync();
    final media = File(p.join(rootB.path, 'Actress', 'ABC-123', 'part.mp4'))
      ..createSync(recursive: true)
      ..writeAsStringSync('fixture');
    final locator = LibraryMediaLocator();

    final resolved = await locator.resolveMedia(
      libraryRoot: rootB.path,
      workRelativePath: 'Actress/ABC-123',
      mediaRelativePath: 'part.mp4',
      mediaPortableId: 'stable-media-id',
    );

    expect(resolved.workRelativePath, 'Actress/ABC-123');
    expect(resolved.mediaRelativePath, 'part.mp4');
    expect(resolved.mediaPortableId, 'stable-media-id');
    expect(resolved.absolutePath, media.absolute.path);
  });
}
