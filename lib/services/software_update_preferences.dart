import 'package:shared_preferences/shared_preferences.dart';

class SoftwareUpdatePreferences {
  static const autoCheckUpdatesKey = 'auto_check_updates';
  static const lastSeenAppVersionKey = 'last_seen_app_version';

  Future<bool> autoCheckUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(autoCheckUpdatesKey) ?? true;
  }

  Future<void> setAutoCheckUpdates(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(autoCheckUpdatesKey, value);
  }

  Future<String?> lastSeenAppVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(lastSeenAppVersionKey);
  }

  Future<void> markAppVersionSeen(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastSeenAppVersionKey, version);
  }
}
