import 'dart:convert';

import 'package:avaca/controllers/settings_controller.dart';
import 'package:avaca/core/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SnackbarSettingsDb extends AppDatabase {
  _SnackbarSettingsDb(this.raw);

  String? raw;
  String? saved;

  @override
  Future<String?> getSetting(String key) async => raw;

  @override
  Future<void> setSetting(String key, String value) async {
    saved = value;
    raw = value;
  }
}

void main() {
  test(
    'old custom theme JSON falls back to the default Snackbar color',
    () async {
      final db = _SnackbarSettingsDb(
        jsonEncode({'surface': const Color(0xFF101010).toARGB32()}),
      );
      final controller = SettingsController(db: db);

      await controller.loadCustomTheme();

      expect(controller.customColors.containsKey('snackbarBackground'), isTrue);
      expect(controller.customColors['snackbarBackground'], Colors.black);
    },
  );

  test(
    'custom Snackbar color is persisted as part of the custom palette',
    () async {
      final db = _SnackbarSettingsDb(null);
      final controller = SettingsController(db: db);
      const color = Color(0xFFABCDEF);
      controller.customColors['snackbarBackground'] = color;

      await controller.saveCustomTheme();

      final decoded = jsonDecode(db.saved!) as Map<String, dynamic>;
      expect(decoded['snackbarBackground'], color.toARGB32());
    },
  );
}
