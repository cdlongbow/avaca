import 'dart:io';

import 'package:avaca/core/database.dart';
import 'package:avaca/models/work.dart';
import 'package:avaca/services/data_health_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('loads all health sections for an operational database', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca-data-health-test-',
    );
    final db = AppDatabase.forTesting(
      baseDir: directory.path,
      databaseFactory: databaseFactoryFfi,
    );
    try {
      await db.init();
      await db.addActress(name: '健康度測試女優');
      final actressId =
          (await (await db.database).query('actresses')).single['id'] as int;
      await db.upsertActressWork(
        actressId: actressId,
        work: const Work(code: 'HEALTH-1', title: '健康度測試作品'),
      );
      final snapshot = await DataHealthService(db: db).load();

      expect(snapshot.actressCount, 1);
      expect(snapshot.workCount, 1);
      expect(snapshot.notStoredWorkCount, 1);
      expect(snapshot.warnings, isEmpty);
    } finally {
      await db.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  test('keeps other sections available when one health query fails', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca-data-health-partial-test-',
    );
    final db = AppDatabase.forTesting(
      baseDir: directory.path,
      databaseFactory: databaseFactoryFfi,
    );
    try {
      await db.init();
      await db.addActress(name: '部分失敗測試女優');
      final database = await db.database;
      await database.execute('DROP TABLE pending_file_deletions');

      final snapshot = await DataHealthService(db: db).load();

      expect(snapshot.actressCount, 1);
      expect(snapshot.workCount, 0);
      expect(snapshot.pendingDeletionCount, 0);
      expect(snapshot.warnings, contains('pendingDeletions'));
    } finally {
      await db.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });
}
