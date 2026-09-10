import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const _serverId = 'e2e-server-v2';
const _clientId = 'e2e-client-v2';

final class _NativePlaybackProfile extends Struct {
  external Pointer<Utf8> serverId;

  @Uint32()
  external int serverIdLength;

  external Pointer<Utf8> clientId;

  @Uint32()
  external int clientIdLength;

  external Pointer<Utf8> host;

  @Uint32()
  external int hostLength;

  @Uint16()
  external int port;

  external Pointer<Uint8> certificateSha256Pin;

  @Uint32()
  external int certificateSha256PinLength;

  external Pointer<Uint8> pairingSecret;

  @Uint32()
  external int pairingSecretLength;
}

final class _NativePlaybackDescriptor extends Struct {
  external Pointer<Uint8> resourceId;

  @Uint32()
  external int resourceIdLength;

  @Uint64()
  external int resourceLength;

  external Pointer<Utf8> playbackSessionId;

  @Uint32()
  external int playbackSessionIdLength;

  external Pointer<Uint8> playbackGrant;

  @Uint32()
  external int playbackGrantLength;
}

typedef _PlaybackOpenNative =
    Int32 Function(
      Pointer<_NativePlaybackProfile>,
      Pointer<_NativePlaybackDescriptor>,
      Pointer<Uint64>,
    );
typedef _PlaybackOpenDart =
    int Function(
      Pointer<_NativePlaybackProfile>,
      Pointer<_NativePlaybackDescriptor>,
      Pointer<Uint64>,
    );

typedef _PlaybackReadNative =
    Int32 Function(Uint64, Uint64, Pointer<Uint8>, Uint32, Pointer<Uint32>);
typedef _PlaybackReadDart =
    int Function(int, int, Pointer<Uint8>, int, Pointer<Uint32>);

typedef _PlaybackCloseNative = Int32 Function(Uint64);
typedef _PlaybackCloseDart = int Function(int);

final class _NativePlaybackApi {
  _NativePlaybackApi(DynamicLibrary library)
    : open = library.lookupFunction<_PlaybackOpenNative, _PlaybackOpenDart>(
        'avaca_remote_playback_open_native',
      ),
      read = library.lookupFunction<_PlaybackReadNative, _PlaybackReadDart>(
        'avaca_remote_playback_read_at',
      ),
      close = library.lookupFunction<_PlaybackCloseNative, _PlaybackCloseDart>(
        'avaca_remote_playback_close',
      );

  final _PlaybackOpenDart open;
  final _PlaybackReadDart read;
  final _PlaybackCloseDart close;
}

Future<void> main(List<String> args) async {
  if (!Platform.isWindows || args.length != 7) {
    stderr.writeln(
      'usage: dart tooling/native_playback_client_e2e.dart '
      '<server-leaf-sha256-64-hex> <port> <session-id> <resource-id> '
      '<resource-length> <playback-grant-hex> <native-dll-path>',
    );
    exitCode = 2;
    return;
  }

  final serverPin = _parseHex(args[0], 32, 'server leaf SHA-256');
  final port = int.parse(args[1]);
  final sessionId = args[2];
  final resourceId = args[3];
  final resourceLength = int.parse(args[4]);
  final grant = _parseHex(args[5], 32, 'playback grant');
  final api = _NativePlaybackApi(DynamicLibrary.open(args[6]));
  final fixtureBytes = Uint8List.fromList(
    List<int>.generate(131072, (index) => (index * 17 + 3) & 0xff),
  );
  if (resourceLength != fixtureBytes.length) {
    throw StateError('unexpected fixture length');
  }

  var handle = 0;
  try {
    handle = _openNative(
      api,
      port: port,
      serverPin: serverPin,
      sessionId: sessionId,
      resourceId: resourceId,
      resourceLength: resourceLength,
      playbackGrant: grant,
    );
    _assertRange(api, handle, fixtureBytes, 0, 4096);
    _assertRange(api, handle, fixtureBytes, 65537, 8192);
    _assertRange(api, handle, fixtureBytes, fixtureBytes.length - 73, 73);
    stdout.writeln('CHILD_INITIAL_RANGES_PASS');
    stdout.writeln('CHILD_READY');
    await stdout.flush();

    final commands = stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final command in commands) {
      if (command == 'READ_AFTER_CONTROL_CLOSE') {
        _assertRange(api, handle, fixtureBytes, 32768, 4096);
        stdout.writeln('CHILD_AFTER_CONTROL_CLOSE_PASS');
        await stdout.flush();
      } else if (command == 'CLOSE') {
        _closeNative(api, handle);
        handle = 0;
        stdout.writeln('CHILD_CLOSED');
        await stdout.flush();
        return;
      }
    }
    throw StateError('native playback child stdin closed before CLOSE');
  } finally {
    if (handle != 0) {
      _closeNative(api, handle);
    }
    grant.fillRange(0, grant.length, 0);
    serverPin.fillRange(0, serverPin.length, 0);
  }
}

int _openNative(
  _NativePlaybackApi api, {
  required int port,
  required List<int> serverPin,
  required String sessionId,
  required String resourceId,
  required int resourceLength,
  required List<int> playbackGrant,
}) {
  final serverId = _serverId.toNativeUtf8();
  final clientId = _clientId.toNativeUtf8();
  final endpoint = '127.0.0.1'.toNativeUtf8();
  final nativeSessionId = sessionId.toNativeUtf8();
  final nativeResourceId = calloc<Uint8>(resourceId.length);
  final pin = calloc<Uint8>(serverPin.length);
  final secret = calloc<Uint8>(32);
  final grant = calloc<Uint8>(playbackGrant.length);
  final profile = calloc<_NativePlaybackProfile>();
  final descriptor = calloc<_NativePlaybackDescriptor>();
  final output = calloc<Uint64>();
  final pairingSecret = List<int>.generate(
    32,
    (index) => (0x40 + index) & 0xff,
  );
  try {
    nativeResourceId
        .asTypedList(resourceId.length)
        .setAll(0, resourceId.codeUnits);
    pin.asTypedList(serverPin.length).setAll(0, serverPin);
    secret.asTypedList(pairingSecret.length).setAll(0, pairingSecret);
    grant.asTypedList(playbackGrant.length).setAll(0, playbackGrant);
    profile.ref
      ..serverId = serverId
      ..serverIdLength = _serverId.length
      ..clientId = clientId
      ..clientIdLength = _clientId.length
      ..host = endpoint
      ..hostLength = '127.0.0.1'.length
      ..port = port
      ..certificateSha256Pin = pin
      ..certificateSha256PinLength = serverPin.length
      ..pairingSecret = secret
      ..pairingSecretLength = pairingSecret.length;
    descriptor.ref
      ..resourceId = nativeResourceId
      ..resourceIdLength = resourceId.length
      ..resourceLength = resourceLength
      ..playbackSessionId = nativeSessionId
      ..playbackSessionIdLength = sessionId.length
      ..playbackGrant = grant
      ..playbackGrantLength = playbackGrant.length;
    final status = api.open(profile, descriptor, output);
    if (status != 0 || output.value == 0) {
      throw StateError('native playback child open failed with status $status');
    }
    return output.value;
  } finally {
    calloc.free(serverId);
    calloc.free(clientId);
    calloc.free(endpoint);
    calloc.free(nativeSessionId);
    calloc.free(nativeResourceId);
    pin.asTypedList(serverPin.length).fillRange(0, serverPin.length, 0);
    calloc.free(pin);
    secret
        .asTypedList(pairingSecret.length)
        .fillRange(0, pairingSecret.length, 0);
    calloc.free(secret);
    grant
        .asTypedList(playbackGrant.length)
        .fillRange(0, playbackGrant.length, 0);
    calloc.free(grant);
    calloc.free(profile);
    calloc.free(descriptor);
    calloc.free(output);
    pairingSecret.fillRange(0, pairingSecret.length, 0);
  }
}

void _assertRange(
  _NativePlaybackApi api,
  int handle,
  Uint8List expected,
  int offset,
  int length,
) {
  final buffer = calloc<Uint8>(length);
  final outputLength = calloc<Uint32>();
  try {
    final status = api.read(handle, offset, buffer, length, outputLength);
    if (status != 0 || outputLength.value != length) {
      throw StateError(
        'native child range read failed at $offset with status $status '
        'and length ${outputLength.value}',
      );
    }
    final actual = buffer.asTypedList(length);
    for (var index = 0; index < length; index++) {
      if (actual[index] != expected[offset + index]) {
        throw StateError(
          'native child range bytes differ at ${offset + index}',
        );
      }
    }
  } finally {
    calloc.free(buffer);
    calloc.free(outputLength);
  }
}

void _closeNative(_NativePlaybackApi api, int handle) {
  final status = api.close(handle);
  if (status != 0) {
    throw StateError('native child playback close failed: $status');
  }
}

List<int> _parseHex(String value, int expectedBytes, String label) {
  if (value.length != expectedBytes * 2 ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
    throw FormatException('$label must contain $expectedBytes bytes of hex');
  }
  return List<int>.generate(
    expectedBytes,
    (index) => int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
  );
}
