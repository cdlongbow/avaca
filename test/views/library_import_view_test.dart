import 'dart:io';

import 'package:avaca/core/config.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/library/library_filename_parser.dart';
import 'package:avaca/library/library_filesystem.dart';
import 'package:avaca/library/library_models.dart';
import 'package:avaca/library/library_repository.dart';
import 'package:avaca/views/library_import_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  testWidgets(
    'scan UI shows real names and supports correction before selection',
    (tester) async {
      final root = Directory(
        path.join(
          Directory.systemTemp.path,
          '.avaca-test-library-import-view-${DateTime.now().microsecondsSinceEpoch}',
        ),
      )..createSync(recursive: true);
      final sourceRoot = Directory(path.join(root.path, 'source'))
        ..createSync();
      final libraryRoot = Directory(path.join(root.path, 'library'))
        ..createSync();
      File(
        path.join(sourceRoot.path, '[FHD] SSIS00123-RUC.mp4'),
      ).writeAsBytesSync(List<int>.filled(8, 1));
      File(
        path.join(sourceRoot.path, 'unknown-video.mkv'),
      ).writeAsBytesSync(List<int>.filled(8, 2));
      final choices = <String?>[sourceRoot.path, libraryRoot.path];
      final parser = const LibraryFilenameParser();
      final scanEntries = [
        LibraryScanEntry(
          sourcePath: path.join(sourceRoot.path, '[FHD] SSIS00123-RUC.mp4'),
          originalFileName: '[FHD] SSIS00123-RUC.mp4',
          sizeBytes: 8,
          modifiedAt: null,
          createdAt: null,
          parseResult: parser.parse('[FHD] SSIS00123-RUC.mp4'),
        ),
        LibraryScanEntry(
          sourcePath: path.join(sourceRoot.path, 'unknown-video.mkv'),
          originalFileName: 'unknown-video.mkv',
          sizeBytes: 8,
          modifiedAt: null,
          createdAt: null,
          parseResult: parser.parse('unknown-video.mkv'),
        ),
      ];
      AppDatabase? db;
      try {
        db = AppDatabase();
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'TW'),
            theme: AppTheme.fromPalette(AppPalettes.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LibraryImportView(
              db: db,
              directoryPicker: () async => choices.removeAt(0),
              repository: _ImportRepository(),
              scanner: _ImportScanner(scanEntries),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('選擇刮削資料夾'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('選擇收藏資料夾'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('掃描資料夾'));
        await tester.pumpAndSettle();

        expect(find.text('[FHD] SSIS00123-RUC.mp4'), findsOneWidget);
        expect(find.text('unknown-video.mkv'), findsOneWidget);
        expect(find.textContaining('可處理'), findsOneWidget);
        expect(find.textContaining('需要修正番號'), findsOneWidget);
        expect(find.text('已選取 0 個檔案'), findsOneWidget);

        await tester.tap(find.text('選取所有可辨識檔案'));
        await tester.pump();
        expect(find.text('已選取 1 個檔案'), findsOneWidget);

        final unknownCard = find.ancestor(
          of: find.text('unknown-video.mkv'),
          matching: find.byType(Card),
        );
        await tester.enterText(
          find.descendant(of: unknownCard, matching: find.byType(TextField)),
          'ABC-123',
        );
        await tester.pump();
        expect(find.textContaining('需要修正番號'), findsNothing);

        await tester.tap(find.text('選取所有可辨識檔案'));
        await tester.pump();
        expect(find.text('已選取 2 個檔案'), findsOneWidget);
      } finally {
        await db?.close();
      }
    },
  );
}

class _ImportRepository extends LibraryRepository {
  _ImportRepository() : super(db: AppDatabase());

  @override
  Future<String?> activeLibraryRoot() async => null;
}

class _ImportScanner extends LibraryFolderScanner {
  _ImportScanner(this.entries);

  final List<LibraryScanEntry> entries;

  @override
  Future<List<LibraryScanEntry>> scan(String folderPath) async => entries;
}
