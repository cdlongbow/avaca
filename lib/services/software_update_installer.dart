import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../models/software_update_models.dart';
import 'update_startup_marker.dart';

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
    final updater = File(path.join(installRoot.path, 'avaca_update.exe'));
    final extractedDirectory = update.extractedDirectory;
    if (!await updater.exists() || extractedDirectory == null) {
      return const SoftwareInstallResult(
        started: false,
        message: 'This portable folder does not contain avaca_update.exe.',
      );
    }

    final handoffStage = Directory(
      path.join(
        installRoot.parent.path,
        '.avaca-update-${DateTime.now().microsecondsSinceEpoch}-$pid',
      ),
    );
    final helperDirectory = Directory(
      path.join(
        Directory.systemTemp.path,
        'avaca-update-helper-${DateTime.now().microsecondsSinceEpoch}-$pid',
      ),
    );
    final helperCopy = File(
      path.join(helperDirectory.path, 'avaca_update.exe'),
    );
    final startupMarker = File(
      path.join(installRoot.path, windowsUpdateStartupMarker),
    );

    try {
      await _copyDirectoryContents(extractedDirectory, handoffStage);
      await helperDirectory.create(recursive: true);
      await updater.copy(helperCopy.path);
      if (await startupMarker.exists()) {
        await startupMarker.delete();
      }
      await onBeforeUpdate?.call();

      final process = await Process.start(
        helperCopy.path,
        <String>[
          '--install-root',
          installRoot.path,
          '--stage-root',
          handoffStage.path,
          '--parent-pid',
          '$pid',
          '--startup-marker',
          startupMarker.path,
        ],
        workingDirectory: helperDirectory.path,
        mode: ProcessStartMode.detached,
      );
      if (process.pid <= 0) {
        throw const ProcessException(
          'avaca_update.exe',
          <String>[],
          'The portable update helper could not be started.',
        );
      }

      if (await update.stagingDirectory.exists()) {
        await update.stagingDirectory.delete(recursive: true);
      }
    } catch (_) {
      if (await handoffStage.exists()) {
        await handoffStage.delete(recursive: true);
      }
      if (await helperDirectory.exists()) {
        await helperDirectory.delete(recursive: true);
      }
      rethrow;
    }

    if (exitAfterHandoff) exit(0);
    return const SoftwareInstallResult(started: true);
  }

  Future<void> _copyDirectoryContents(
    Directory source,
    Directory destination,
  ) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final targetPath = path.join(
        destination.path,
        path.basename(entity.path),
      );
      if (entity is Directory) {
        await _copyDirectoryContents(entity, Directory(targetPath));
      } else if (entity is File) {
        await entity.copy(targetPath);
      } else {
        throw const FileSystemException(
          'The update package contains an unsupported file entry.',
        );
      }
    }
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
