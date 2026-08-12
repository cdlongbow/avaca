import 'dart:io';

import 'package:path/path.dart' as path;

const windowsUpdateStartupMarker = 'update-startup-success.marker';

/// Lets the external Windows helper distinguish a healthy relaunch from an
/// executable that started and immediately failed during initialization.
Future<void> markWindowsStartupSuccess() async {
  if (!Platform.isWindows) return;
  try {
    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    final marker = File(
      path.join(executableDirectory, windowsUpdateStartupMarker),
    );
    await marker.writeAsString(DateTime.now().toUtc().toIso8601String());
  } catch (_) {
    // A read-only portable folder must not prevent AVACA from starting.
  }
}
