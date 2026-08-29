import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'remote_errors.dart';

abstract interface class RemoteSecretStore {
  Future<void> write(String key, List<int> secret);
  Future<List<int>?> read(String key);
  Future<void> delete(String key);
  Future<void> close();
}

abstract interface class RemoteSecretProtector {
  List<int> protect(List<int> cleartext);
  List<int> unprotect(List<int> protectedBlob);
}

class UnavailableRemoteSecretStore implements RemoteSecretStore {
  const UnavailableRemoteSecretStore();

  @override
  Future<void> write(String key, List<int> secret) async {
    throw const RemoteSecureStorageUnavailableException();
  }

  @override
  Future<List<int>?> read(String key) async {
    throw const RemoteSecureStorageUnavailableException();
  }

  @override
  Future<void> delete(String key) async {
    throw const RemoteSecureStorageUnavailableException();
  }

  @override
  Future<void> close() async {}
}

/// A small file adapter which stores only a DPAPI protected blob on Windows.
/// It deliberately refuses every non-Windows platform; there is no plaintext
/// fallback.
class WindowsDpapiSecretStore implements RemoteSecretStore {
  WindowsDpapiSecretStore(Directory root)
    : _root = root,
      _protector = const WindowsDpapiProtector();

  final Directory _root;
  final RemoteSecretProtector _protector;

  @override
  Future<void> write(String key, List<int> secret) async {
    _checkPlatform();
    final path = _pathFor(key);
    await _root.create(recursive: true);
    final protectedBlob = _protector.protect(Uint8List.fromList(secret));
    final temp = File('${path.path}.tmp');
    await temp.writeAsBytes(protectedBlob, flush: true);
    try {
      if (await path.exists()) {
        await path.delete();
      }
      await temp.rename(path.path);
    } on Object {
      if (await temp.exists()) {
        await temp.delete();
      }
      rethrow;
    }
  }

  @override
  Future<List<int>?> read(String key) async {
    _checkPlatform();
    final path = _pathFor(key);
    if (!await path.exists()) {
      return null;
    }
    try {
      final protectedBlob = await path.readAsBytes();
      if (protectedBlob.isEmpty) {
        throw const RemoteException(
          RemoteFailureCode.secretStorageCorrupt,
          'protected secret blob is empty',
        );
      }
      return Uint8List.fromList(_protector.unprotect(protectedBlob));
    } on RemoteException {
      rethrow;
    } on Object {
      throw const RemoteException(
        RemoteFailureCode.secretStorageCorrupt,
        'protected secret blob cannot be opened',
      );
    }
  }

  @override
  Future<void> delete(String key) async {
    _checkPlatform();
    final path = _pathFor(key);
    if (await path.exists()) {
      await path.delete();
    }
  }

  @override
  Future<void> close() async {}

  void _checkPlatform() {
    if (!Platform.isWindows) {
      throw const RemoteSecureStorageUnavailableException();
    }
  }

  File _pathFor(String key) {
    if (key.isEmpty || !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(key)) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'secret key is not a safe storage key',
      );
    }
    return File('${_root.path}${Platform.pathSeparator}$key.bin');
  }
}

final class _DpapiBlob extends Struct {
  @Uint32()
  external int length;

  external Pointer<Uint8> data;
}

typedef _CryptProtectDataNative =
    Int32 Function(
      Pointer<_DpapiBlob> dataIn,
      Pointer<Utf16> description,
      Pointer<_DpapiBlob> optionalEntropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      Uint32 flags,
      Pointer<_DpapiBlob> dataOut,
    );
typedef _CryptProtectDataDart =
    int Function(
      Pointer<_DpapiBlob> dataIn,
      Pointer<Utf16> description,
      Pointer<_DpapiBlob> optionalEntropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      int flags,
      Pointer<_DpapiBlob> dataOut,
    );

typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> memory);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> memory);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

typedef _CryptUnprotectDataNative =
    Int32 Function(
      Pointer<_DpapiBlob> dataIn,
      Pointer<Pointer<Utf16>> description,
      Pointer<_DpapiBlob> optionalEntropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      Uint32 flags,
      Pointer<_DpapiBlob> dataOut,
    );
typedef _CryptUnprotectDataDart =
    int Function(
      Pointer<_DpapiBlob> dataIn,
      Pointer<Pointer<Utf16>> description,
      Pointer<_DpapiBlob> optionalEntropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      int flags,
      Pointer<_DpapiBlob> dataOut,
    );

class WindowsDpapiProtector implements RemoteSecretProtector {
  const WindowsDpapiProtector();

  @override
  List<int> protect(List<int> cleartext) {
    _ensureWindows();
    if (cleartext.isEmpty) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'secret cannot be empty',
      );
    }
    final crypt32 = DynamicLibrary.open('crypt32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final protect = crypt32
        .lookupFunction<_CryptProtectDataNative, _CryptProtectDataDart>(
          'CryptProtectData',
        );
    final localFree = kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>(
      'LocalFree',
    );
    final getLastError = kernel32
        .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');
    final input = calloc<_DpapiBlob>();
    final output = calloc<_DpapiBlob>();
    final inputBytes = calloc<Uint8>(cleartext.length);
    input.ref.data = inputBytes;
    input.ref.length = cleartext.length;
    inputBytes.asTypedList(cleartext.length).setAll(0, cleartext);
    try {
      final result = protect(
        input,
        Pointer<Utf16>.fromAddress(0),
        Pointer<_DpapiBlob>.fromAddress(0),
        Pointer<Void>.fromAddress(0),
        Pointer<Void>.fromAddress(0),
        0,
        output,
      );
      if (result == 0 ||
          output.ref.data.address == 0 ||
          output.ref.length <= 0) {
        throw RemoteException(
          RemoteFailureCode.secretStorageUnavailable,
          'DPAPI protect operation failed with system code ${getLastError()}',
        );
      }
      return Uint8List.fromList(output.ref.data.asTypedList(output.ref.length));
    } finally {
      inputBytes
          .asTypedList(cleartext.length)
          .fillRange(0, cleartext.length, 0);
      calloc.free(inputBytes);
      calloc.free(input);
      if (output.ref.data.address != 0) {
        localFree(output.ref.data.cast<Void>());
      }
      calloc.free(output);
    }
  }

  @override
  List<int> unprotect(List<int> protectedBlob) {
    _ensureWindows();
    if (protectedBlob.isEmpty) {
      throw const RemoteException(
        RemoteFailureCode.secretStorageCorrupt,
        'protected secret blob is empty',
      );
    }
    final crypt32 = DynamicLibrary.open('crypt32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final unprotect = crypt32
        .lookupFunction<_CryptUnprotectDataNative, _CryptUnprotectDataDart>(
          'CryptUnprotectData',
        );
    final localFree = kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>(
      'LocalFree',
    );
    final input = calloc<_DpapiBlob>();
    final output = calloc<_DpapiBlob>();
    final inputBytes = calloc<Uint8>(protectedBlob.length);
    input.ref.data = inputBytes;
    input.ref.length = protectedBlob.length;
    inputBytes.asTypedList(protectedBlob.length).setAll(0, protectedBlob);
    try {
      final result = unprotect(
        input,
        Pointer<Pointer<Utf16>>.fromAddress(0),
        Pointer<_DpapiBlob>.fromAddress(0),
        Pointer<Void>.fromAddress(0),
        Pointer<Void>.fromAddress(0),
        0,
        output,
      );
      if (result == 0 ||
          output.ref.data.address == 0 ||
          output.ref.length <= 0) {
        throw const RemoteException(
          RemoteFailureCode.secretStorageCorrupt,
          'DPAPI refused the protected secret blob',
        );
      }
      return Uint8List.fromList(output.ref.data.asTypedList(output.ref.length));
    } finally {
      inputBytes
          .asTypedList(protectedBlob.length)
          .fillRange(0, protectedBlob.length, 0);
      calloc.free(inputBytes);
      calloc.free(input);
      if (output.ref.data.address != 0) {
        localFree(output.ref.data.cast<Void>());
      }
      calloc.free(output);
    }
  }

  static void _ensureWindows() {
    if (!Platform.isWindows) {
      throw const RemoteSecureStorageUnavailableException();
    }
  }
}
