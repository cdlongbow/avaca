import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:avaca_client/avaca_client.dart';
import 'package:avaca_domain/avaca_domain.dart';
import 'package:avaca_library/avaca_library.dart';
import 'package:avaca_protocol/avaca_protocol.dart';
import 'package:avaca_remote_core/avaca_remote_core.dart';

const _serverId = 'e2e-server-v2';
const _clientId = 'e2e-client-v2';

final class _FixtureCatalog implements ServerCatalogRepository {
  const _FixtureCatalog();

  static const workId = AvacaWorkId('work-e2e');
  static const mediaId = AvacaMediaId('media-e2e');
  static const missingMediaId = AvacaMediaId('media-e2e-missing');
  static const coverAssetId = 'asset-e2e-cover';

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
        coverResourceId: coverAssetId,
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
        AvacaMediaSummary(
          mediaId: _FixtureCatalog.missingMediaId,
          workId: workId,
          code: 'E2E-001',
          title: 'AVACA missing media fixture',
          availability: AvacaMediaAvailability.unavailable,
        ),
      ],
      coverResourceId: coverAssetId,
    );
  }
}

final class _FixtureAssetCatalog implements ServerAssetCatalogRepository {
  const _FixtureAssetCatalog({required this.path, required this.length});

  final String path;
  final int length;

  @override
  Future<ServerAssetRecord?> findAsset(String assetId, int revision) async {
    if (assetId != _FixtureCatalog.coverAssetId || revision != 0) {
      return null;
    }
    return ServerAssetRecord(
      assetId: assetId,
      revision: revision,
      absolutePath: path,
      length: length,
      mimeType: 'image/jpeg',
    );
  }
}

Future<void> main(List<String> args) async {
  if (!Platform.isWindows || args.length < 3 || args.length > 6) {
    stderr.writeln(
      'usage: dart tooling/remote_server_player_e2e.dart '
      '<server-sha1-40-hex> <server-leaf-sha256-64-hex> <port> '
      '[native-dll-path] [native-client-exe-path] [asset-client-exe-path]',
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
  final nativeClientExecutablePath = args.length == 5
      ? args[4]
      : '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}'
            'native_playback_client_e2e.exe';
  final assetClientExecutablePath = args.length == 6
      ? args[5]
      : '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}'
            'asset_catalog_client_e2e.exe';
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
  final coverFixture = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'avaca-remote-e2e-${pid.toRadixString(16)}.jpg',
  );
  final coverBytes = Uint8List.fromList(<int>[
    0xff,
    0xd8,
    0xff,
    0xe0,
    0x00,
    0x10,
    0x41,
    0x56,
    0x41,
    0x43,
    0x41,
    0xff,
    0xd9,
  ]);
  await fixture.writeAsBytes(fixtureBytes, flush: true);
  await coverFixture.writeAsBytes(coverBytes, flush: true);

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
    assetCatalog: _FixtureAssetCatalog(
      path: coverFixture.path,
      length: coverBytes.length,
    ),
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
  Process? nativeClientProcess;
  StreamIterator<String>? nativeClientLines;
  Process? assetClientProcess;
  StreamIterator<String>? assetClientLines;

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
    if (detail.media.length != 2) {
      throw StateError('detail response did not return fixture media');
    }
    _pass('browse/detail crossed the authenticated Dart control session');

    assetClientProcess = await Process.start(
      assetClientExecutablePath,
      <String>[_hexEncode(serverPin), port.toString()],
    );
    assetClientLines = StreamIterator<String>(
      assetClientProcess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
    );
    unawaited(
      assetClientProcess.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) => stderr.writeln('ASSET_CHILD: $line')),
    );
    await _expectChildLine(assetClientLines, 'CHILD_ASSET_DETAIL_PASS');
    await _expectChildLine(assetClientLines, 'CHILD_ASSET_RANGE_PASS');
    await _expectChildLine(assetClientLines, 'CHILD_MISSING_MEDIA_REJECTED');
    final assetChildExitCode = await assetClientProcess.exitCode;
    if (assetChildExitCode != 0) {
      throw StateError(
        'asset catalog client process exited with $assetChildExitCode',
      );
    }
    assetClientProcess = null;
    assetClientLines = null;
    _pass(
      'separate Dart client process opened opaque artwork and rejected missing media',
    );

    final descriptor = await catalog.createPlaybackSession(
      _FixtureCatalog.mediaId,
    );
    final controlOpened = await catalog.openPlaybackResource(descriptor);
    final controlChunk = await catalog.session.request(
      AvacaOpcode.readResource,
      const AvacaApplicationCodec().encodeRangeRequest(
        resourceHandle: controlOpened.resourceHandle,
        offset: 0,
        length: 4096,
      ),
      expectedResponses: const <AvacaOpcode>{AvacaOpcode.resourceChunk},
    );
    final decodedControlChunk = const AvacaApplicationCodec()
        .decodeResourceChunk(controlChunk.payload);
    if (decodedControlChunk.bytes.length != 4096) {
      throw StateError('control playback range did not return the fixture');
    }
    await catalog.closeResource(controlOpened.resourceHandle);
    _pass('Dart control data-plane opened and read the same resource');
    nativeClientProcess =
        await Process.start(nativeClientExecutablePath, <String>[
          _hexEncode(serverPin),
          port.toString(),
          descriptor.sessionId!,
          descriptor.resourceId,
          descriptor.length.toString(),
          _hexEncode(descriptor.playbackGrant!),
          nativeLibraryPath,
        ]);
    nativeClientLines = StreamIterator<String>(
      nativeClientProcess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
    );
    unawaited(
      nativeClientProcess.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) => stderr.writeln('NATIVE_CHILD: $line')),
    );
    await _expectChildLine(nativeClientLines, 'CHILD_INITIAL_RANGES_PASS');
    await _expectChildLine(nativeClientLines, 'CHILD_READY');
    _pass(
      'separate native client process authenticated and opened the range resource',
    );
    _pass('native QUIC range reads and absolute seek returned exact bytes');

    await catalog.close();
    catalog = null;
    await _sendChildCommand(nativeClientProcess, 'READ_AFTER_CONTROL_CLOSE');
    await _expectChildLine(nativeClientLines, 'CHILD_AFTER_CONTROL_CLOSE_PASS');
    _pass('native lease remained valid after Dart control disconnect');

    await _sendChildCommand(nativeClientProcess, 'CLOSE');
    await _expectChildLine(nativeClientLines, 'CHILD_CLOSED');
    final childExitCode = await nativeClientProcess.exitCode;
    if (childExitCode != 0) {
      throw StateError('native client process exited with $childExitCode');
    }
    nativeClientProcess = null;
    nativeClientLines = null;

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
    final child = nativeClientProcess;
    if (child != null) {
      child.kill();
      await child.exitCode;
    }
    final assetChild = assetClientProcess;
    if (assetChild != null) {
      assetChild.kill();
      await assetChild.exitCode;
    }
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
    try {
      await coverFixture.delete();
    } on FileSystemException {
      // The fixture is only a temporary test artifact.
    }
  }
  stdout.writeln(
    'PASS: Windows Server -> native AVACA range E2E; no HTTP/SMB/local-path '
    'fallback was used',
  );
  await stdout.flush();
  // MsQuic can retain native callback workers after every Dart handle has
  // closed.  This is a standalone evidence executable, so terminate only
  // after the async finally block above has released all test resources.
  exit(0);
}

Future<void> _expectChildLine(
  StreamIterator<String> lines,
  String expected,
) async {
  while (await lines.moveNext()) {
    final line = lines.current;
    if (line == expected) return;
    stderr.writeln('NATIVE_CHILD_STDOUT: $line');
  }
  throw StateError('native client child ended before $expected');
}

Future<void> _sendChildCommand(Process process, String command) async {
  process.stdin.writeln(command);
  await process.stdin.flush();
}

String _hexEncode(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

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
