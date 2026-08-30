import 'package:avaca/core/config.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/views/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home exposes video import and no manual actress entry', (
    tester,
  ) async {
    String? pushedRoute;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        theme: AppTheme.fromPalette(AppPalettes.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        onGenerateRoute: (settings) {
          pushedRoute = settings.name;
          return MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('import')),
          );
        },
        home: HomeView(db: _HomeDatabase()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('匯入影片'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);

    await tester.tap(find.byTooltip('匯入影片'));
    await tester.pumpAndSettle();
    expect(pushedRoute, '/library-import');
  });
}

class _HomeDatabase extends AppDatabase {
  @override
  Future<List<Map<String, Object?>>> getAllActresses({
    String searchKeyword = '',
    String filterType = '全部',
    String sortBy = '新增時間 (新到舊)',
  }) async => const [];
}
