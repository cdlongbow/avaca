import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:avaca_client/avaca_client.dart';
import 'package:avaca_domain/avaca_domain.dart';
import 'package:avaca_library/avaca_library.dart';
import 'package:avaca_remote_core/avaca_remote_core.dart';
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

final class _FixtureCatalog implements ServerCatalogRepository {
  const _FixtureCatalog();

  static const workId = AvacaWorkId('work-e2e');
  static const mediaId = AvacaMediaId('media-e2e');

  @override
  Future<AvacaCollectionPage> listCollection({
    String? cursor,
    int limit = 50,
  }) async => const AvacaCollectionPage(
    items: <AvacaWorkSummary>[
      AvacaWorkSummary(
        workId: workId,
        code: 'E2E-001',
        title: 'AVACA remote E2E fixture',
      ),
    ],
    nextCursor: null,
  );

  @override
  Future<AvacaWorkDetail> getWorkDetail(AvacaWorkId workId) async {
    if (workId != _FixtureCatalog.workId) {
      throw StateError('unexpected work id: $workId');
    }
    return AvacaWorkDetail(
      workId: _FixtureCatalog.workId,
      code: 'E2E-001',
      title: 'AVACA remote E2E fixture',
      media: <AvacaMediaSummary>[
        AvacaMediaSummary(
          mediaId: _FixtureCatalog.mediaId,
          workId: workId,
          code: 'E2E-001',
          title: 'AVACA remote E2E fixture',
          availability: AvacaMediaAvailability.available,
        ),
      ],
    );
  }
}

Future<void> main(List<String> args) async {
  if (!Platform.isWindows || args.length < 3 || args.length > 4) {
    stderr.writeln(
      'usage: dart tooling/remote_server_player_e2e.dart '
      '<server-sha1-40-hex> <server-leaf-sha256-64-hex> <port> '
      '[native-dll-path]',
    );
    exitCode = 2;
    return;
  }

  final serverSha1 = _parseHex(args[0], 20, 'server SHA-1');
  final serverPin = _parseHex(args[1], 32, 'server leaf SHA-256');
  final port = int.parse(args[2]);
  final nativeLibraryPath = args.length == 4
      ? args[3]
      : '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}'
            'avaca_remote_quic.dll';
  final nativeApi = _NativePlaybackApi(DynamicLibrary.open(nativeLibraryPath));
  final sharedSecret = Uint8List.fromList(
    List<int>.generate(32, (index) => (0x40 + index) & 0xff),
  );
  final fixture = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'avaca-remote-e2e-${pid.toRadixString(16)}.bin',
  );
  final fixtureBytes = Uint8List.fromList(
    List<int>.generate(131072, (index) => (index * 17 + 3) & 0xff),
  );
  await fixture.writeAsBytes(fixtureBytes, flush: true);

  final grants = PlaybackGrantRegistry();
  final resources = ServerMediaResourceService(grants: grants);
  final playbackSessions = PlaybackSessionService(grants: grants);
  final host = AvacaServerApplicationHost(
    serverId: _serverId,
    pairingSecret: sharedSecret,
    pairingSecretResolver: (clientId) async =>
        clientId == _clientId ? sharedSecret : null,
    catalog: ServerCatalogService(const _FixtureCatalog()),
    playbackSessions: playbackSessions,
    resources: resources,
    resolvePlayback: (mediaId) async => mediaId == _FixtureCatalog.mediaId
        ? ServerPlaybackSelection(
            mediaId: mediaId,
            resourceId: 'fixture-resource',
            absolutePath: fixture.path,
            length: fixtureBytes.length,
          )
        : null,
  );
  AvacaMsQuicTransport? serverTransport;
  AvacaMsQuicTransport? clientTransport;
  AvacaMsQuicTransport? reconnectTransport;
  AvacaRemoteCatalogClient? catalog;
  AvacaRemoteCatalogClient? reconnectCatalog;
  var nativeHandle = 0;

  try {
    serverTransport = AvacaMsQuicTransport.server(
      certificateSha1Thumbprint: serverSha1,
      listenPort: port,
    );
    await host.start(serverTransport);
    _pass('Windows Server host listened on authenticated MsQuic');

    clientTransport = AvacaMsQuicTransport.client(
      certificateSha256Pin: serverPin,
    );
    catalog = await AvacaRemoteCatalogClient.connect(
      transport: clientTransport,
      endpoint: AvacaRemoteEndpoint(host: '127.0.0.1', port: port),
      clientId: _clientId,
      expectedServerId: _serverId,
      pairingSecret: sharedSecret,
    );
    final capabilities = await catalog.getCapabilities();
    if (capabilities.serverId.value != _serverId) {
      throw StateError('unexpected Server ID in capabilities');
    }
    final collection = await catalog.listCollection();
    if (collection.items.length != 1) {
      throw StateError('catalog list did not return the fixture');
    }
    final detail = await catalog.getWorkDetail(_FixtureCatalog.workId);
    if (detail.media.length != 1) {
      throw StateError('detail response did not return the fixture media');
    }
    _pass('browse/detail crossed the authenticated Dart control session');

    final descriptor = await catalog.createPlaybackSession(
      _FixtureCatalog.mediaId,
    );
    nativeHandle = _openNative(
      nativeApi,
      host: '127.0.0.1',
      port: port,
      serverPin: serverPin,
      pairingSecret: sharedSecret,
      descriptor: descriptor,
    );
    _pass(
      'second same-clientId native session authenticated and opened range resource',
    );

    _assertRange(nativeApi, nativeHandle, fixtureBytes, 0, 4096);
    _assertRange(nativeApi, nativeHandle, fixtureBytes, 65537, 8192);
    _assertRange(
      nativeApi,
      nativeHandle,
      fixtureBytes,
      fixtureBytes.length - 73,
      73,
    );
    _pass('native QUIC range reads and absolute seek returned exact bytes');

    await catalog.close();
    catalog = null;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _assertRange(nativeApi, nativeHandle, fixtureBytes, 32768, 4096);
    _pass('native lease remained valid after Dart control disconnect');

    _closeNative(nativeApi, nativeHandle);
    nativeHandle = 0;
    await Future<void>.delayed(const Duration(milliseconds: 250));

    reconnectTransport = AvacaMsQuicTransport.client(
      certificateSha256Pin: serverPin,
    );
    reconnectCatalog = await AvacaRemoteCatalogClient.connect(
      transport: reconnectTransport,
      endpoint: AvacaRemoteEndpoint(host: '127.0.0.1', port: port),
      clientId: _clientId,
      expectedServerId: _serverId,
      pairingSecret: sharedSecret,
    );
    final reconnectPage = await reconnectCatalog.listCollection();
    if (reconnectPage.items.single.workId != _FixtureCatalog.workId) {
      throw StateError('reconnect returned a different catalog');
    }
    _pass('same clientId reconnected after the native lease was released');
  } finally {
    if (nativeHandle != 0) _closeNative(nativeApi, nativeHandle);
    await _closeQuietly(reconnectCatalog);
    await _closeQuietly(catalog);
    await _closeQuietly(host);
    await _closeQuietly(reconnectTransport);
    await _closeQuietly(clientTransport);
    await _closeQuietly(serverTransport);
    sharedSecret.fillRange(0, sharedSecret.length, 0);
    try {
      await fixture.delete();
    } on FileSystemException {
      // The fixture is only a temporary test artifact.
    }
  }
  stdout.writeln(
    'PASS: Windows Server -> native AVACA range E2E; no HTTP/SMB/local-path '
    'fallback was used',
  );
}

int _openNative(
  _NativePlaybackApi api, {
  required String host,
  required int port,
  required List<int> serverPin,
  required List<int> pairingSecret,
  required AvacaAssetDescriptor descriptor,
}) {
  final serverId = _serverId.toNativeUtf8();
  final clientId = _clientId.toNativeUtf8();
  final endpoint = host.toNativeUtf8();
  final sessionId = descriptor.sessionId!.toNativeUtf8();
  final resourceId = calloc<Uint8>(descriptor.resourceId.length);
  final pin = calloc<Uint8>(serverPin.length);
  final secret = calloc<Uint8>(pairingSecret.length);
  final grant = calloc<Uint8>(descriptor.playbackGrant!.length);
  final profile = calloc<_NativePlaybackProfile>();
  final nativeDescriptor = calloc<_NativePlaybackDescriptor>();
  final output = calloc<Uint64>();
  try {
    resourceId
        .asTypedList(descriptor.resourceId.length)
        .setAll(0, descriptor.resourceId.codeUnits);
    pin.asTypedList(serverPin.length).setAll(0, serverPin);
    secret.asTypedList(pairingSecret.length).setAll(0, pairingSecret);
    grant
        .asTypedList(descriptor.playbackGrant!.length)
        .setAll(0, descriptor.playbackGrant!);
    profile.ref
      ..serverId = serverId
      ..serverIdLength = _serverId.length
      ..clientId = clientId
      ..clientIdLength = _clientId.length
      ..host = endpoint
      ..hostLength = host.length
      ..port = port
      ..certificateSha256Pin = pin
      ..certificateSha256PinLength = serverPin.length
      ..pairingSecret = secret
      ..pairingSecretLength = pairingSecret.length;
    nativeDescriptor.ref
      ..resourceId = resourceId
      ..resourceIdLength = descriptor.resourceId.length
      ..resourceLength = descriptor.length
      ..playbackSessionId = sessionId
      ..playbackSessionIdLength = descriptor.sessionId!.length
      ..playbackGrant = grant
      ..playbackGrantLength = descriptor.playbackGrant!.length;
    final status = api.open(profile, nativeDescriptor, output);
    if (status != 0 || output.value == 0) {
      throw StateError('native playback open failed with status $status');
    }
    return output.value;
  } finally {
    calloc.free(serverId);
    calloc.free(clientId);
    calloc.free(endpoint);
    calloc.free(sessionId);
    calloc.free(resourceId);
    pin.asTypedList(serverPin.length).fillRange(0, serverPin.length, 0);
    calloc.free(pin);
    secret
        .asTypedList(pairingSecret.length)
        .fillRange(0, pairingSecret.length, 0);
    calloc.free(secret);
    grant
        .asTypedList(descriptor.playbackGrant!.length)
        .fillRange(0, descriptor.playbackGrant!.length, 0);
    calloc.free(grant);
    calloc.free(profile);
    calloc.free(nativeDescriptor);
    calloc.free(output);
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
        'native range read failed at $offset with status $status '
        'and length ${outputLength.value}',
      );
    }
    final actual = buffer.asTypedList(length);
    for (var index = 0; index < length; index++) {
      if (actual[index] != expected[offset + index]) {
        throw StateError('native range bytes differ at ${offset + index}');
      }
    }
  } finally {
    calloc.free(buffer);
    calloc.free(outputLength);
  }
}

void _closeNative(_NativePlaybackApi api, int handle) {
  final status = api.close(handle);
  if (status != 0) throw StateError('native playback close failed: $status');
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

Future<void> _closeQuietly(Object? value) async {
  try {
    if (value is AvacaRemoteCatalogClient) {
      await value.close();
    } else if (value is AvacaServerApplicationHost) {
      await value.close();
    } else if (value is AvacaMsQuicTransport) {
      await value.close();
    }
  } on Object catch (error) {
    stderr.writeln('cleanup warning: $error');
  }
}

void _pass(String message) => stdout.writeln('PASS: $message');
