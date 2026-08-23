import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:avaca/core/database.dart';
import 'package:avaca/models/scrape_job.dart';
import 'package:avaca/models/work.dart';
import 'package:avaca/services/scrape_job_repository.dart';

void main() {
  sqfliteFfiInit();

  test('operational schema is idempotent and recovers running jobs', () async {
    final directory = await Directory.systemTemp.createTemp('avaca-job-test-');
    final db = AppDatabase.forTesting(
      baseDir: directory.path,
      databaseFactory: databaseFactoryFfi,
    );
    try {
      await db.init();
      await db.addActress(name: 'Test Actress');
      final actressId =
          (await (await db.database).query(
                'actresses',
                columns: const ['id'],
                where: 'name = ?',
                whereArgs: const ['Test Actress'],
              )).single['id']
              as int;
      final repository = ScrapeJobRepository(db: db);
      final job = await repository.create(
        actressId: actressId,
        actressName: 'Test Actress',
        optionsSnapshot: '{}',
        sourceSettingsSnapshot: '{}',
        rulesVersionSnapshot: 'builtin-1',
        rulesSnapshot: '{}',
      );
      final database = await db.database;
      await database.update(
        'scrape_jobs',
        {'state': ScrapeJobState.running.storageValue},
        where: 'id = ?',
        whereArgs: [job.id],
      );

      await db.close();
      final reopenedDb = AppDatabase.forTesting(
        baseDir: directory.path,
        databaseFactory: databaseFactoryFfi,
      );
      try {
        await reopenedDb.init();
        final reopenedRepository = ScrapeJobRepository(db: reopenedDb);
        await reopenedRepository.recoverInterruptedJobs();

        expect(
          (await reopenedRepository.get(job.id))?.state,
          ScrapeJobState.queued,
        );
      } finally {
        await reopenedDb.close();
      }
    } finally {
      await db.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  test('work provenance is returned with work details', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca-provenance-test-',
    );
    final db = AppDatabase.forTesting(
      baseDir: directory.path,
      databaseFactory: databaseFactoryFfi,
    );
    try {
      await db.init();
      await db.addActress(name: 'Test Actress');
      final actressId =
          (await (await db.database).query(
                'actresses',
                columns: const ['id'],
                where: 'name = ?',
                whereArgs: const ['Test Actress'],
              )).single['id']
              as int;
      final workId = await db.upsertActressWork(
        actressId: actressId,
        work: const Work(code: 'ABC-1', title: 'A title'),
        provenance: const [
          WorkFieldProvenance(workId: 0, field: 'title', source: 'javbus'),
        ],
      );

      final work = await db.getWorkById(workId);
      expect(work?['field_provenance'], isNotEmpty);
    } finally {
      await db.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });
}
