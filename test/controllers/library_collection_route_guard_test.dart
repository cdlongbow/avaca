import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:avaca/controllers/detail_controller.dart';
import 'package:avaca/controllers/works_controller.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/library/library_collection_service.dart';
import 'package:avaca/library/library_repository.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'detail and works route controllers reject metadata-only actresses',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca_collection_route_guard_',
      );
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(
          baseDir: p.join(root.path, 'db'),
          databaseFactory: databaseFactoryFfi,
        );
        await db.init();
        final database = await db.database;
        final actressId = await database.insert('actresses', {
          'name': 'Metadata-only actress',
        });
        final workId = await database.insert('works', {
          'code': 'META-001',
          'title': 'Metadata-only work',
        });
        await database.insert('actress_works', {
          'actress_id': actressId,
          'work_id': workId,
        });
        final libraryRoot = Directory(p.join(root.path, 'library'))
          ..createSync(recursive: true);
        await LibraryRepository(db: db).setActiveLibraryRoot(libraryRoot.path);

        final collection = LibraryCollectionService(db: db);
        final detail = DetailController(
          db: db,
          actressId: actressId,
          collectionService: collection,
        );
        await detail.init();
        expect(detail.isAvailable, isFalse);
        expect(detail.actressData.name, isEmpty);
        expect(detail.workCount, 0);

        final works = WorksController(
          db: db,
          actressId: actressId,
          collectionService: collection,
        );
        await works.init();
        expect(works.status, WorksLoadStatus.notFound);
        expect(works.works, isEmpty);

        detail.dispose();
        works.dispose();
      } finally {
        await db?.close();
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      }
    },
  );
}
