import 'package:flutter_test/flutter_test.dart';

import 'package:avaca/library/library_filename_parser.dart';
import 'package:avaca/library/library_import_session.dart';
import 'package:avaca/library/library_models.dart';

void main() {
  LibraryScanEntry entry(String name) {
    final parseResult = const LibraryFilenameParser().parse(name);
    return LibraryScanEntry(
      sourcePath: 'C:/source/$name',
      originalFileName: name,
      sizeBytes: 1,
      modifiedAt: null,
      createdAt: null,
      parseResult: parseResult,
    );
  }

  test(
    'selection session is authoritative and selects recognizable rows only',
    () {
      final session = LibraryImportSession();
      session.setEntries(<LibraryScanEntry>[
        entry('ABC00123.mp4'),
        entry('unknown.mp4'),
      ]);

      session.selectAllRecognizable();

      expect(session.selectedCount, 1);
      expect(session.entries.first.selected, isTrue);
      expect(session.entries.last.selected, isFalse);
      session.clearSelection();
      expect(session.selectedCount, 0);
    },
  );

  test('correction immediately makes a row selectable', () {
    final session = LibraryImportSession();
    session.setEntries(<LibraryScanEntry>[entry('unknown.mp4')]);

    session.applyManualCode(0, 'ABC00123');

    expect(session.entries.single.parseResult.normalizedCode, 'ABC-123');
    expect(session.entries.single.parseResult.isImportable, isTrue);
    session.setSelected(0, true);
    expect(session.selectedEntries, hasLength(1));
  });

  test('invalid rows can be selected and are left for Review to block', () {
    final session = LibraryImportSession();
    session.setEntries(<LibraryScanEntry>[entry('unknown.mp4')]);

    session.setSelected(0, true);

    expect(session.selectedCount, 1);
    expect(session.selectedEntries.single.parseResult.isImportable, isFalse);
  });

  test('source and destination choices only change session state', () {
    final session = LibraryImportSession();
    session.setSourceFolder('C:/source');
    session.setLibraryRoot('C:/library');

    expect(session.sourceFolder, 'C:/source');
    expect(session.libraryRoot, 'C:/library');
    expect(session.entries, isEmpty);
  });
}
