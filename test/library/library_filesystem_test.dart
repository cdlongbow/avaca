import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:avaca/library/library_filesystem.dart';

void main() {
  late Directory root;
  late Directory source;
  late Directory library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('avaca_library_fs_');
    source = Directory(path.join(root.path, 'source'))..createSync();
    library = Directory(path.join(root.path, 'library'))..createSync();
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('phase-one scanner is read-only and ignores derived links', () async {
    final video = File(path.join(source.path, '[FHD] SSIS00123-RUC.mp4'))
      ..writeAsBytesSync(<int>[1, 2, 3]);
    File(path.join(source.path, 'ignored.lnk')).writeAsStringSync('link');
    File(path.join(source.path, 'ignored.tmp')).writeAsStringSync('tmp');
    final before = video.readAsBytesSync();
    final scanner = LibraryFolderScanner();

    final entries = await scanner.scan(source.path);

    expect(entries, hasLength(1));
    expect(entries.single.parseResult.normalizedCode, 'SSIS-123');
    expect(video.readAsBytesSync(), before);
    expect(
      Directory(path.join(library.path, 'SSIS-123')).existsSync(),
      isFalse,
    );
  });

  test('relative path validation blocks traversal and absolute paths', () {
    final filesystem = LibraryFilesystem();

    expect(
      () => filesystem.validateRelativePath('../escape'),
      throwsA(isA<LibraryFilesystemException>()),
    );
    expect(
      () => filesystem.validateRelativePath('C:/escape'),
      throwsA(isA<LibraryFilesystemException>()),
    );
    expect(
      filesystem.validateRelativePath('Actress/ABC-123'),
      'Actress/ABC-123',
    );
  });

  test('stream copy hash is independently verifiable', () async {
    final filesystem = LibraryFilesystem();
    final sourceFile = File(path.join(source.path, 'source.mp4'))
      ..writeAsStringSync('fixture');
    final destination = path.join(
      library.path,
      'Actress',
      'ABC-123',
      'video.mp4',
    );
    final snapshot = await filesystem.snapshot(sourceFile.path);

    final hash = await filesystem.copyAndHash(
      sourceFile.path,
      destination,
      expectedSnapshot: snapshot,
    );

    expect(hash, await filesystem.hashFile(destination));
    expect(File(destination).readAsStringSync(), 'fixture');
  });
}
