import 'package:avaca/controllers/detail_controller.dart';
import 'package:avaca/core/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _EditCancelDatabase extends AppDatabase {
  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async => {
    'id': actressId,
    'name': '已儲存名稱',
    'img_path': 'saved-photo.jpg',
    'main_type': '有碼',
    'memo': '',
    'height': '',
    'weight': '',
    'bwh': '',
    'cup': '',
    'birth_date': null,
  };

  @override
  Future<int> getWorkCountForActress(int actressId) async => 0;
}

void main() {
  testWidgets('cancel edit restores the persisted photo path', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final controller = DetailController(
      db: _EditCancelDatabase(),
      actressId: 1,
    );
    await controller.init();
    await controller.toggleEditMode(context, const {
      'name': '已儲存名稱',
      'img_path': 'saved-photo.jpg',
      'main_type': '有碼',
      'selected_attrs': ['有碼'],
      'memo': '',
      'height': '',
      'weight': '',
      'bwh': '',
      'cup': '',
      'birth_date': null,
    });

    controller.deletePhoto();
    expect(controller.actressData['img_path'], isEmpty);

    controller.cancelEditMode();

    expect(controller.isEditing, isFalse);
    expect(controller.actressData['img_path'], 'saved-photo.jpg');
  });
}
