import 'package:avaca/controllers/detail_controller.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _EditCancelDatabase extends AppDatabase {
  _EditCancelDatabase({this.saveSucceeds = true});

  final bool saveSucceeds;
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

  @override
  Future<bool> updateActress({
    required int actressId,
    required String name,
    String imgPath = '',
    String mainType = '',
    String memo = '',
    String height = '',
    String weight = '',
    String bwh = '',
    String cup = '',
    String? birthDate,
  }) async => saveSucceeds;
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
    await controller.toggleEditMode(
      context,
      DetailFormData(
        name: '已儲存名稱',
        imgPath: 'saved-photo.jpg',
        mainType: '有碼',
        selectedAttrs: ['有碼'],
        memo: '',
        height: '',
        weight: '',
        bwh: '',
        cup: '',
        birthDate: null,
      ),
    );

    controller.deletePhoto();
    expect(controller.actressData.imgPath, isEmpty);

    controller.cancelEditMode();

    expect(controller.isEditing, isFalse);
    expect(controller.actressData.imgPath, 'saved-photo.jpg');
  });

  testWidgets('failed save keeps editing and preserves persisted state', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
    final controller = DetailController(
      db: _EditCancelDatabase(saveSucceeds: false),
      actressId: 1,
    );
    await controller.init();
    await controller.toggleEditMode(context, const DetailFormData.empty());
    await controller.toggleEditMode(
      context,
      DetailFormData(
        name: '未儲存名稱',
        imgPath: 'saved-photo.jpg',
        mainType: '無碼',
        selectedAttrs: ['無碼'],
        memo: '',
        height: '',
        weight: '',
        bwh: '',
        cup: '',
        birthDate: null,
      ),
    );
    expect(controller.isEditing, isTrue);
    expect(controller.actressData.name, '已儲存名稱');
    expect(controller.currentAttrs, ['有碼']);
  });
}
