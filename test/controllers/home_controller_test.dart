import 'package:avaca/controllers/home_controller.dart';
import 'package:avaca/core/database.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingDatabase extends AppDatabase {
  String? lastFilterType;
  String? lastSortBy;

  @override
  Future<List<Map<String, Object?>>> getAllActresses({
    String searchKeyword = '',
    String filterType = '全部',
    String sortBy = '新增時間 (新到舊)',
  }) async {
    lastFilterType = filterType;
    lastSortBy = sortBy;
    return const [];
  }
}

void main() {
  group('HomeController public query behavior', () {
    test('exposes every supported sort in the intended UI order', () {
      final controller = HomeController(db: _RecordingDatabase());

      expect(controller.getSortOptions(), [
        'created_desc',
        'created_asc',
        'modified_desc',
        'modified_asc',
        'age_asc',
        'age_desc',
      ]);
    });

    test('maps every supported sort key at the database boundary', () async {
      final database = _RecordingDatabase();
      final controller = HomeController(db: database);
      const expectedMappings = {
        'created_desc': '新增時間 (新到舊)',
        'created_asc': '新增時間 (舊到新)',
        'modified_desc': '修改時間 (新到舊)',
        'modified_asc': '修改時間 (舊到新)',
        'age_asc': '年齡 (低到高)',
        'age_desc': '年齡 (高到低)',
      };

      for (final entry in expectedMappings.entries) {
        controller.changeSort(entry.key);
        await controller.getGalleryData();
        expect(database.lastSortBy, entry.value, reason: entry.key);
      }
    });

    test('maps all and a concrete category at the database boundary', () async {
      final database = _RecordingDatabase();
      final controller = HomeController(db: database);

      controller.selectFilter('all');
      await controller.getGalleryData();
      expect(database.lastFilterType, '全部');

      controller.selectFilter('censored');
      await controller.getGalleryData();
      expect(database.lastFilterType, '有碼');
    });
  });
}
