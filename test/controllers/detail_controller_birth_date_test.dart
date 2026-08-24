import 'package:avaca/controllers/detail_controller.dart';
import 'package:avaca/core/database.dart';
import 'package:flutter_test/flutter_test.dart';

class _NotFoundDatabase extends AppDatabase {
  @override
  Future<int> getWorkCountForActress(int actressId) async => 0;

  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async => null;
}

class _RefreshDatabase extends AppDatabase {
  int revision = 0;

  @override
  Future<int> getWorkCountForActress(int actressId) async => revision + 1;

  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async {
    return {
      'id': actressId,
      'name': revision == 0 ? '初始名稱' : '更新名稱',
      'main_type': revision == 0 ? '無碼' : '有碼,FC2',
      'aliases': revision == 0 ? const ['舊別名'] : const ['新別名'],
      'birth_date': null,
    };
  }
}

void main() {
  test('not-found initialization keeps a nullable birthday fallback', () async {
    final controller = DetailController(
      db: _NotFoundDatabase(),
      actressId: 404,
    );

    await controller.init();

    expect(controller.actressData.birthDate, isNull);
    expect(controller.actressData.name, isEmpty);
    expect(controller.actressData.mainType, isEmpty);
    expect(controller.currentAttrs, isEmpty);
    expect(controller.isEditing, isFalse);
  });

  test('refresh reloads actress details after returning from works', () async {
    final database = _RefreshDatabase();
    final controller = DetailController(db: database, actressId: 7);

    await controller.init();
    expect(controller.actressData.name, '初始名稱');
    expect(controller.workCount, 1);

    database.revision = 1;
    await controller.refresh();

    expect(controller.actressData.name, '更新名稱');
    expect(controller.currentAttrs, ['有碼', 'FC2']);
    expect(controller.actressAliases, ['新別名']);
    expect(controller.workCount, 2);
  });
}
