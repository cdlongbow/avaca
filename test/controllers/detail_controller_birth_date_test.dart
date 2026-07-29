import 'package:avaca/controllers/detail_controller.dart';
import 'package:avaca/core/database.dart';
import 'package:flutter_test/flutter_test.dart';

class _NotFoundDatabase extends AppDatabase {
  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async => null;
}

void main() {
  test('not-found initialization keeps a nullable birthday fallback', () async {
    final controller = DetailController(
      db: _NotFoundDatabase(),
      actressId: 404,
    );

    await controller.init();

    expect(controller.actressData, containsPair('birth_date', null));
    expect(controller.actressData, containsPair('name', ''));
    expect(controller.actressData, containsPair('main_type', ''));
    expect(controller.currentAttrs, isEmpty);
    expect(controller.isEditing, isFalse);
  });
}
