import 'dart:io';

import 'package:flutter/services.dart';

/// Requests only the Android media permission needed by the path-based
/// Library scanner. The selected folder remains user-scoped; this channel
/// does not grant broad filesystem management access.
class LibraryAndroidStorageAccess {
  const LibraryAndroidStorageAccess();

  static const MethodChannel _channel = MethodChannel(
    'com.avaca.avaca/library_storage',
  );

  Future<bool> ensureMediaReadAccess() async {
    if (!Platform.isAndroid) return true;
    final granted = await _channel.invokeMethod<bool>('requestMediaReadAccess');
    return granted ?? false;
  }
}
