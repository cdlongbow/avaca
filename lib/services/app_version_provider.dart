import 'dart:ffi';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../models/software_update_models.dart';

abstract class AppVersionProvider {
  Future<AppVersionInfo> load();
}

class PackageInfoAppVersionProvider implements AppVersionProvider {
  PackageInfoAppVersionProvider();

  Future<AppVersionInfo>? _cached;

  @override
  Future<AppVersionInfo> load() {
    return _cached ??= _load();
  }

  Future<AppVersionInfo> _load() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return AppVersionInfo(
      version: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      platform: _platform,
      architecture: _architecture,
    );
  }

  SoftwareUpdatePlatform get _platform {
    if (Platform.isAndroid) return SoftwareUpdatePlatform.android;
    if (Platform.isWindows) return SoftwareUpdatePlatform.windows;
    return SoftwareUpdatePlatform.unsupported;
  }

  String get _architecture {
    return switch (Abi.current()) {
      Abi.androidArm64 => 'arm64-v8a',
      Abi.androidX64 => 'x86_64',
      Abi.windowsX64 => 'x64',
      Abi.windowsArm64 => 'arm64',
      _ => Abi.current().toString(),
    };
  }
}
