import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/library/library_collection_service.dart';
import 'package:avaca/views/detail_view.dart';
import 'package:avaca/views/work_detail_view.dart';
import 'package:avaca/views/works_view.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'normal Collection hides storage filters and work selection/deletion',
    (tester) async {
      final database = _CollectionGuardDatabase();
      final collection = _FakeCollectionService(database);
      await tester.pumpWidget(
        _localizedApp(
          WorksView(db: database, actressId: 7, collectionService: collection),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('work-card-1')), findsOneWidget);
      expect(find.byKey(const Key('works-delete-action')), findsNothing);
      expect(find.byKey(const Key('work-card-selected-1')), findsNothing);
      final cardInkWell = tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(const Key('work-card-1')),
          matching: find.byType(InkWell),
        ),
      );
      expect(cardInkWell.onLongPress, isNull);

      await tester.tap(find.byKey(const Key('works-overflow-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('works-search-menu-item')), findsOneWidget);
      expect(
        find.byKey(const Key('works-filter-stored-menu-item')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('works-filter-not-stored-menu-item')),
        findsNothing,
      );
      expect(find.byKey(const Key('works-filter-all-menu-item')), findsNothing);
    },
  );

  testWidgets('normal Work detail hides the legacy storage editor', (
    tester,
  ) async {
    final database = _CollectionGuardDatabase();
    final collection = _FakeCollectionService(database);
    await tester.pumpWidget(
      _localizedApp(
        WorkDetailView(
          db: database,
          workId: 1,
          currentActressId: 7,
          collectionService: collection,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('work-storage-action')), findsNothing);
    expect(find.byKey(const Key('library-media-section')), findsOneWidget);
  });

  testWidgets('normal actress detail has no legacy delete menu item', (
    tester,
  ) async {
    final database = _CollectionGuardDatabase();
    final collection = _FakeCollectionService(database);
    await tester.pumpWidget(
      _localizedApp(
        DetailView(db: database, actressId: 7, collectionService: collection),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('detail-overflow-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detail-delete-menu-item')), findsNothing);
  });
}

Widget _localizedApp(Widget home) {
  return MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}

class _CollectionGuardDatabase extends AppDatabase {
  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async => {
    'id': actressId,
    'name': 'Collection actress',
    'img_path': '',
    'main_type': '有碼',
    'memo': '',
    'height': '',
    'weight': '',
    'bwh': '',
    'cup': '',
    'birth_date': null,
    'aliases': const <String>[],
  };
}

class _FakeCollectionService extends LibraryCollectionService {
  _FakeCollectionService(AppDatabase db) : super(db: db);

  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async => {
    'id': actressId,
    'name': 'Collection actress',
    'img_path': '',
  };

  @override
  Future<List<Map<String, Object?>>> getWorksForActress(int actressId) async =>
      [
        {
          'id': 1,
          'code': 'ABC-123',
          'title': 'Physical work',
          'release_date': '2026-08-31',
          'duration_minutes': 100,
          'studio': '',
          'publisher': '',
          'series': '',
          'card_image_path': '',
          'detail_image_path': '',
          'portable_id': 'work-1',
          'library_managed': 1,
        },
      ];

  @override
  Future<int> getWorkCountForActress(int actressId) async => 1;

  @override
  Future<Map<String, Object?>?> getWorkById(
    int workId, {
    int? currentActressId,
  }) async => {
    'id': workId,
    'code': 'ABC-123',
    'title': 'Physical work',
    'release_date': '2026-08-31',
    'duration_minutes': 100,
    'studio': '',
    'publisher': '',
    'series': '',
    'detail_image_path': '',
    'portable_id': 'work-1',
    'library_managed': 1,
    'library_media': const [
      {
        'portable_id': 'media-1',
        'file_name': 'ABC-123.mp4',
        'relative_path': 'ABC-123.mp4',
      },
    ],
    'related_performers': const [],
  };
}
