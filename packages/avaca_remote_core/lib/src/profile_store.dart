import 'dart:convert';

import 'package:flutter/services.dart';

import '../avaca_remote_core.dart';

/// Secure profile persistence boundary shared by the Windows DPAPI and
/// Android Keystore implementations in the native player plugin.  The Dart
/// side only hands over an opaque protected-store operation; it never writes
/// a plaintext profile to a catalog, diagnostic file, or preference store.
abstract interface class AvacaRemoteProfileStore {
  /// The current product stores one paired server profile per local player.
  /// This key is deliberately not derived from the server id, because the
  /// id is only available after decrypting the profile.
  static const activeKey = 'active';

  Future<void> save(AvacaRemoteClientProfile profile);

  Future<AvacaRemoteClientProfile?> load(String profileKey);

  Future<void> delete(String profileKey);
}

final class NativeAvacaRemoteProfileStore implements AvacaRemoteProfileStore {
  NativeAvacaRemoteProfileStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'avaca/remote/profile_store';
  final MethodChannel _channel;

  @override
  Future<void> save(AvacaRemoteClientProfile profile) async {
    final bytes = _encode(profile);
    try {
      await _channel.invokeMethod<void>('write', <String, Object?>{
        // The current UI intentionally owns one active profile.  Persisting
        // under the server id while loading/deleting `active` would make a
        // successful pairing disappear after restart and leave revoke unable
        // to remove the same protected record.
        'key': _safeKey(AvacaRemoteProfileStore.activeKey),
        'value': bytes,
      });
    } on MissingPluginException {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.unsupported,
        'secure remote profile storage is not installed',
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<AvacaRemoteClientProfile?> load(String profileKey) async {
    final result = await _invokeRead(_safeKey(profileKey));
    if (result == null) return null;
    try {
      return _decode(result);
    } finally {
      result.fillRange(0, result.length, 0);
    }
  }

  @override
  Future<void> delete(String profileKey) async {
    try {
      await _channel.invokeMethod<void>('delete', <String, Object?>{
        'key': _safeKey(profileKey),
      });
    } on MissingPluginException {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.unsupported,
        'secure remote profile storage is not installed',
      );
    }
  }

  Future<Uint8List?> _invokeRead(String key) async {
    try {
      final value = await _channel.invokeMethod<Object?>(
        'read',
        <String, Object?>{'key': key},
      );
      if (value == null) return null;
      if (value is Uint8List) return Uint8List.fromList(value);
      if (value is List) return Uint8List.fromList(value.cast<int>());
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.internal,
        'secure remote profile storage returned an invalid value',
      );
    } on MissingPluginException {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.unsupported,
        'secure remote profile storage is not installed',
      );
    }
  }

  Uint8List _encode(AvacaRemoteClientProfile profile) {
    final json = jsonEncode(<String, Object?>{
      'serverId': profile.serverId,
      'clientId': profile.clientId,
      'host': profile.host,
      'port': profile.port,
      'certPin': base64UrlEncode(
        profile.leafCertificateSha256,
      ).replaceAll('=', ''),
      'secret': base64UrlEncode(profile.pairingSecret).replaceAll('=', ''),
      'version': 2,
    });
    return Uint8List.fromList(utf8.encode(json));
  }

  AvacaRemoteClientProfile _decode(List<int> bytes) {
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map)
        throw const FormatException('profile is not an object');
      final map = value.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (map['version'] != 2 ||
          map['serverId'] is! String ||
          map['clientId'] is! String ||
          map['host'] is! String ||
          map['port'] is! int ||
          map['certPin'] is! String ||
          map['secret'] is! String) {
        throw const FormatException('profile fields are invalid');
      }
      return AvacaRemoteClientProfile(
        serverId: map['serverId']! as String,
        clientId: map['clientId']! as String,
        host: map['host']! as String,
        port: map['port']! as int,
        leafCertificateSha256: _decodeBytes(map['certPin']! as String),
        pairingSecret: _decodeBytes(map['secret']! as String),
      );
    } on AvacaRemoteException {
      rethrow;
    } on Object {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.internal,
        'secure remote profile storage contains invalid data',
      );
    }
  }

  Uint8List _decodeBytes(String value) {
    final bytes = Uint8List.fromList(
      base64Url.decode(base64Url.normalize(value)),
    );
    if (bytes.length != 32 ||
        base64UrlEncode(bytes).replaceAll('=', '') != value) {
      throw const FormatException('profile bytes are invalid');
    }
    return bytes;
  }

  String _safeKey(String value) {
    if (value.isEmpty ||
        value.length > 256 ||
        !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(value)) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidInput,
        'remote profile key is invalid',
      );
    }
    return 'profile-v2-$value';
  }
}
