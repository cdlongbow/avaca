import 'client_profile.dart';

/// VM/test-side declaration for the Flutter secure profile store.  Pure Dart
/// protocol tests must not import `dart:ui` or Flutter platform channels.
abstract interface class AvacaRemoteProfileStore {
  static const activeKey = 'active';

  Future<void> save(AvacaRemoteClientProfile profile);

  Future<AvacaRemoteClientProfile?> load(String profileKey);

  Future<void> delete(String profileKey);
}

final class NativeAvacaRemoteProfileStore implements AvacaRemoteProfileStore {
  const NativeAvacaRemoteProfileStore();

  @override
  Future<void> save(AvacaRemoteClientProfile profile) async {
    throw UnsupportedError('Flutter secure profile storage is unavailable.');
  }

  @override
  Future<AvacaRemoteClientProfile?> load(String profileKey) async {
    throw UnsupportedError('Flutter secure profile storage is unavailable.');
  }

  @override
  Future<void> delete(String profileKey) async {
    throw UnsupportedError('Flutter secure profile storage is unavailable.');
  }
}
