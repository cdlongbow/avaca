import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../models/software_update_models.dart';

abstract class SoftwareUpdateInstaller {
  static SoftwareUpdateInstaller forCurrentPlatform({
    Future<void> Function()? onBeforeWindowsUpdate,
  }) {
    if (Platform.isAndroid) return AndroidSoftwareUpdateInstaller();
    if (Platform.isWindows) {
      return WindowsSoftwareUpdateInstaller(
        onBeforeUpdate: onBeforeWindowsUpdate,
      );
    }
    return const UnsupportedSoftwareUpdateInstaller();
  }

  Future<SoftwareInstallResult> install(DownloadedUpdate update);
}

class AndroidSoftwareUpdateInstaller implements SoftwareUpdateInstaller {
  AndroidSoftwareUpdateInstaller({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.avaca.avaca/software_update');

  final MethodChannel _channel;

  @override
  Future<SoftwareInstallResult> install(DownloadedUpdate update) async {
    final canInstall =
        await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    if (!canInstall) {
      await _channel.invokeMethod<void>('openInstallPermissionSettings');
      return const SoftwareInstallResult(
        started: false,
        requiresUserAction: true,
        message: 'Install permission is required.',
      );
    }

    final started =
        await _channel.invokeMethod<bool>('installApk', <String, Object>{
          'path': update.file.path,
        }) ??
        false;
    return SoftwareInstallResult(
      started: started,
      message: started ? null : 'The Android package installer did not start.',
    );
  }
}

class WindowsSoftwareUpdateInstaller implements SoftwareUpdateInstaller {
  WindowsSoftwareUpdateInstaller({
    this.onBeforeUpdate,
    this.exitAfterHandoff = true,
  });

  final Future<void> Function()? onBeforeUpdate;
  final bool exitAfterHandoff;

  @override
  Future<SoftwareInstallResult> install(DownloadedUpdate update) async {
    if (!Platform.isWindows) {
      return const SoftwareInstallResult(
        started: false,
        message: 'The Windows installer is not available on this platform.',
      );
    }

    final executable = File(Platform.resolvedExecutable);
    final installRoot = executable.parent;
    final updater = File(path.join(installRoot.path, 'update.cmd'));
    if (!await updater.exists()) {
      return const SoftwareInstallResult(
        started: false,
        message: 'This portable folder does not contain update.cmd.',
      );
    }

    await onBeforeUpdate?.call();
    final command =
        '"${updater.path}" -ArchivePath "${update.file.path}" '
        '-InstallRoot "${installRoot.path}" '
        '-Version "${update.release.version}"';
    final process = await Process.start(
      'cmd.exe',
      <String>['/d', '/c', command],
      workingDirectory: Directory.systemTemp.path,
      mode: ProcessStartMode.detached,
    );
    if (process.pid <= 0) {
      return const SoftwareInstallResult(
        started: false,
        message: 'The portable update helper could not be started.',
      );
    }

    if (exitAfterHandoff) exit(0);
    return const SoftwareInstallResult(started: true);
  }
}

class UnsupportedSoftwareUpdateInstaller implements SoftwareUpdateInstaller {
  const UnsupportedSoftwareUpdateInstaller();

  @override
  Future<SoftwareInstallResult> install(DownloadedUpdate update) async {
    return const SoftwareInstallResult(
      started: false,
      message: 'Automatic updates are not supported on this platform.',
    );
  }
}
