import 'package:avaca/controllers/add_controller.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAddDatabase extends AppDatabase {
  final List<String> names = [];

  @override
  String get imgDir => '';

  @override
  Future<bool> addActress({
    required String name,
    String? imgPath,
    String mainType = '',
    String tags = '',
    String memo = '',
    String? birthDate,
  }) async {
    names.add(name);
    return false;
  }
}

void main() {
  testWidgets('saveActress preserves the existing name trimming behavior', (
    tester,
  ) async {
    late BuildContext context;
    final db = _RecordingAddDatabase();
    final controller = AddController(db: db);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const Scaffold();
          },
        ),
      ),
    );

    const cases = {
      'Name': 'Name',
      ' Name': 'Name',
      'Name ': 'Name',
      '  Name  ': 'Name',
      'A  B': 'A  B',
      '  涼森れむ  ': '涼森れむ',
    };

    for (final entry in cases.entries) {
      await controller.saveActress(context, entry.key);
      expect(db.names.last, entry.value);
    }

    final callsBeforeEmptyNames = db.names.length;
    await controller.saveActress(context, '');
    await controller.saveActress(context, '   ');

    expect(db.names, hasLength(callsBeforeEmptyNames));
  });
}
