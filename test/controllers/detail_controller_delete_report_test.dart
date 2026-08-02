import 'dart:io';

import 'package:avaca/controllers/detail_controller.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('successful deletion shows a compact cleanup summary', (
    tester,
  ) async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'avaca_detail_delete_report_test_',
    );
    final database = AppDatabase.forTesting(
      baseDir: path.join(
        temporaryDirectory.path,
        'application-documents',
        'avaca_data',
      ),
      databaseFactory: databaseFactoryFfi,
    );
    addTearDown(() async {
      await database.close();
      if (temporaryDirectory.existsSync()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    await database.init();
    await database.addActress(name: 'report dialog actress');
    final sqlite = await database.database;
    final actressId =
        (await sqlite.query(
              'actresses',
              columns: ['id'],
              where: 'name = ?',
              whereArgs: ['report dialog actress'],
            )).single['id']
            as int;
    final controller = DetailController(db: database, actressId: actressId);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                controller.executeDelete(context);
              },
              child: const Text('delete'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text('已刪除 0 個圖片檔，共釋放 0.00 MB'),
      findsOneWidget,
    );
  });
}
