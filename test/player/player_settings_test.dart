import 'package:avaca/controllers/settings_controller.dart';
import 'package:avaca/core/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('player settings default to the contract values', () async {
    final controller = SettingsController(db: AppDatabase());

    await controller.loadFromPrefs();

    expect(controller.playerSeekSeconds, 5);
    expect(controller.playerHoldSpeed, 2);

    controller.dispose();
  });

  test('player settings clamp and persist user changes', () async {
    final controller = SettingsController(db: AppDatabase());

    await controller.playerSeekSecondsChanged(0);
    await controller.playerHoldSpeedChanged(9);

    expect(controller.playerSeekSeconds, 1);
    expect(controller.playerHoldSpeed, 4);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('player_seek_seconds'), 1);
    expect(prefs.getDouble('player_hold_speed'), 4);

    await controller.playerSeekSecondsChanged(17);
    await controller.playerHoldSpeedChanged(1.75);

    final restored = SettingsController(db: AppDatabase());
    await restored.loadFromPrefs();

    expect(restored.playerSeekSeconds, 17);
    expect(restored.playerHoldSpeed, 1.75);

    controller.dispose();
    restored.dispose();
  });

  test('player hold speed accepts legacy integer preferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'player_seek_seconds': 12,
      'player_hold_speed': 3,
    });
    final controller = SettingsController(db: AppDatabase());

    await controller.loadFromPrefs();

    expect(controller.playerSeekSeconds, 12);
    expect(controller.playerHoldSpeed, 3);

    controller.dispose();
  });
}
