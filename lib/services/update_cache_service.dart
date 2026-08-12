import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'software_update_preferences.dart';

/// Clears only disposable update/image caches after a new binary starts.
///
/// AppDatabase's database and managed images deliberately do not live in this
/// service. They are user data and must survive an application update.
class UpdateCacheService {
  UpdateCacheService({
    SoftwareUpdatePreferences? preferences,
    Future<Directory> Function()? temporaryDirectoryProvider,
  }) : _preferences = preferences ?? SoftwareUpdatePreferences(),
       _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory;

  final SoftwareUpdatePreferences _preferences;
  final Future<Directory> Function() _temporaryDirectoryProvider;

  Future<void> clearAfterVersionChange(String currentVersion) async {
    final previous = await _preferences.lastSeenAppVersion();
    if (previous == currentVersion) {
      await _preferences.markAppVersionSeen(currentVersion);
      return;
    }

    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await _clearUpdateStagingDirectories();
    await _preferences.markAppVersionSeen(currentVersion);
  }

  Future<void> _clearUpdateStagingDirectories() async {
    Directory tempDirectory;
    try {
      tempDirectory = await _temporaryDirectoryProvider();
    } catch (_) {
      tempDirectory = Directory.systemTemp;
    }
    if (!await tempDirectory.exists()) return;

    await for (final entity in tempDirectory.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = path.basename(entity.path);
      if (!name.startsWith('avaca-update-')) continue;
      await entity.delete(recursive: true);
    }
  }
}
