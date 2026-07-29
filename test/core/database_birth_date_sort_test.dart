import 'dart:io';

import 'package:avaca/core/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  group('birth date migration and CRUD', () {
    test('migrates an old actresses table without losing data', () async {
      final fixture = await _DatabaseFixture.createOldSchema();
      addTearDown(fixture.dispose);

      final database = fixture.openAppDatabase();
      await database.init();

      final sqlite = await database.database;
      final columns = await sqlite.rawQuery('PRAGMA table_info(actresses)');
      expect(columns.map((column) => column['name']), contains('birth_date'));
      expect(await database.getActressById(1), containsPair('name', '舊資料'));
      expect(
        await database.getActressById(1),
        containsPair('birth_date', null),
      );
    });

    test('round-trips a nullable ISO birth date through Detail CRUD', () async {
      final fixture = await _DatabaseFixture.create();
      addTearDown(fixture.dispose);
      final database = fixture.openAppDatabase();
      await database.init();

      expect(
        await database.addActress(name: '生日 CRUD', birthDate: '2000-02-29'),
        isTrue,
      );
      final sqlite = await database.database;
      final idRows = await sqlite.rawQuery(
        'SELECT id FROM actresses WHERE name = ?',
        ['生日 CRUD'],
      );
      final id = idRows.single['id'] as int;

      expect(
        await database.getActressById(id),
        containsPair('birth_date', '2000-02-29'),
      );
      expect(
        await database.updateActress(
          actressId: id,
          name: '生日 CRUD',
          birthDate: '1999-12-31',
        ),
        isTrue,
      );
      expect(
        await database.getActressById(id),
        containsPair('birth_date', '1999-12-31'),
      );
      expect(
        await database.updateActress(
          actressId: id,
          name: '生日 CRUD',
          birthDate: null,
        ),
        isTrue,
      );
      expect(
        await database.getActressById(id),
        containsPair('birth_date', null),
      );
    });

    test('normalizes an empty birth date to null', () async {
      final fixture = await _DatabaseFixture.create();
      addTearDown(fixture.dispose);
      final database = fixture.openAppDatabase();
      await database.init();

      expect(await database.addActress(name: '空生日', birthDate: ''), isTrue);
      final sqlite = await database.database;
      final rows = await sqlite.query(
        'actresses',
        columns: ['birth_date'],
        where: 'name = ?',
        whereArgs: ['空生日'],
      );
      expect(rows.single['birth_date'], isNull);
    });

    test('rejects invalid birth dates without inserting rows', () async {
      final fixture = await _DatabaseFixture.create();
      addTearDown(fixture.dispose);
      final database = fixture.openAppDatabase();
      await database.init();

      for (final invalid in const [
        '2000/01/01',
        '2024-02-31',
        '2099-01-01',
        '1899-12-31',
      ]) {
        expect(
          await database.addActress(
            name: 'invalid-$invalid',
            birthDate: invalid,
          ),
          isFalse,
          reason: invalid,
        );
      }

      final sqlite = await database.database;
      final count = await sqlite.rawQuery(
        "SELECT COUNT(*) AS count FROM actresses WHERE name LIKE 'invalid-%'",
      );
      expect(count.single['count'], 0);
    });

    test('invalid update preserves the stored date and age order', () async {
      final fixture = await _DatabaseFixture.create();
      addTearDown(fixture.dispose);
      final database = fixture.openAppDatabase();
      await database.init();
      await database.addActress(name: 'older', birthDate: '1980-01-01');
      await database.addActress(name: 'younger', birthDate: '2000-01-01');
      final sqlite = await database.database;
      final youngerRows = await sqlite.query(
        'actresses',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: ['younger'],
      );
      final youngerId = youngerRows.single['id'] as int;

      for (final invalid in const [
        '2000/01/01',
        '2024-02-31',
        '2099-01-01',
        '1899-12-31',
      ]) {
        expect(
          await database.updateActress(
            actressId: youngerId,
            name: 'younger',
            birthDate: invalid,
          ),
          isFalse,
          reason: invalid,
        );
        expect(
          await database.getActressById(youngerId),
          containsPair('birth_date', '2000-01-01'),
        );
      }

      expect(await _names(database, '年齡 (低到高)'), ['younger', 'older']);
    });
  });

  group('actress ordering', () {
    late _DatabaseFixture fixture;
    late AppDatabase database;

    setUp(() async {
      fixture = await _DatabaseFixture.create();
      database = fixture.openAppDatabase();
      await database.init();
      final sqlite = await database.database;
      await sqlite.rawInsert(
        '''
        INSERT INTO actresses (name, birth_date, modified_at)
        VALUES (?, ?, ?), (?, ?, ?), (?, ?, ?), (?, ?, ?)
        ''',
        [
          'old',
          '1980-01-01',
          '2024-01-01 00:00:00',
          'young-a',
          '2000-01-01',
          '2022-01-01 00:00:00',
          'unknown',
          null,
          '2023-01-01 00:00:00',
          'young-b',
          '2000-01-01',
          '2024-01-01 00:00:00',
        ],
      );
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('sorts age ascending as young to old with null last', () async {
      expect(await _names(database, '年齡 (低到高)'), [
        'young-b',
        'young-a',
        'old',
        'unknown',
      ]);
    });

    test('sorts age descending as old to young with null last', () async {
      expect(await _names(database, '年齡 (高到低)'), [
        'old',
        'young-b',
        'young-a',
        'unknown',
      ]);
    });

    test('sorts created time in both directions', () async {
      expect(await _names(database, '新增時間 (新到舊)'), [
        'young-b',
        'unknown',
        'young-a',
        'old',
      ]);
      expect(await _names(database, '新增時間 (舊到新)'), [
        'old',
        'young-a',
        'unknown',
        'young-b',
      ]);
    });

    test('sorts modified time in both directions with stable ties', () async {
      expect(await _names(database, '修改時間 (新到舊)'), [
        'young-b',
        'old',
        'unknown',
        'young-a',
      ]);
      expect(await _names(database, '修改時間 (舊到新)'), [
        'young-a',
        'unknown',
        'young-b',
        'old',
      ]);
    });
  });
}

Future<List<String>> _names(AppDatabase database, String sortBy) async {
  final rows = await database.getAllActresses(sortBy: sortBy);
  return rows.map((row) => row['name'].toString()).toList();
}

class _DatabaseFixture {
  _DatabaseFixture._(this.directory);

  final Directory directory;
  AppDatabase? _database;

  static Future<_DatabaseFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca_database_test_',
    );
    return _DatabaseFixture._(directory);
  }

  static Future<_DatabaseFixture> createOldSchema() async {
    final fixture = await create();
    final sqlite = await databaseFactoryFfi.openDatabase(
      path.join(fixture.directory.path, AppDatabase.databaseFileName),
    );
    await sqlite.execute('''
      CREATE TABLE actresses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        img_path TEXT,
        modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await sqlite.insert('actresses', {'name': '舊資料'});
    await sqlite.close();
    return fixture;
  }

  AppDatabase openAppDatabase() {
    return _database = AppDatabase.forTesting(
      baseDir: directory.path,
      databaseFactory: databaseFactoryFfi,
    );
  }

  Future<void> dispose() async {
    await _database?.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}
