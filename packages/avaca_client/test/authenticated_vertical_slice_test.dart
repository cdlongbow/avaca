import 'dart:async';
import 'dart:typed_data';

import 'package:avaca_client/avaca_client.dart';
import 'package:avaca_domain/avaca_domain.dart';
import 'package:avaca_protocol/avaca_protocol.dart';
import 'package:avaca_remote_core/avaca_remote_core.dart';
import 'package:test/test.dart';

void main() {
  test('authenticated browse/detail/play/seek/stop vertical slice', () async {
    final mediaBytes = Uint8List.fromList(
      List<int>.generate(64, (index) => (index * 3) & 0xff),
    );
    final pair = _MemoryConnectionPair();
    final secret = Uint8List.fromList(
      List<int>.generate(32, (index) => (index * 11) & 0xff),
    );
    final serverFuture = AvacaApplicationSession.authenticateServer(
      pair.server,
      serverId: 'server-vertical',
      expectedClientId: 'client-vertical',
      pairingSecret: secret,
    );
    final clientFuture = AvacaApplicationSession.authenticateClient(
      pair.client,
      clientId: 'client-vertical',
      expectedServerId: 'server-vertical',
      pairingSecret: secret,
    );
    final serverSession = await serverFuture;
    final clientSession = await clientFuture;
    final serve = serverSession.serve(
      (request) => _handleServerRequest(request, mediaBytes),
    );
    final client = AvacaRemoteCatalogClient(clientSession);

    try {
      final capabilities = await client.getCapabilities();
      expect(capabilities.serverId.value, 'server-vertical');

      final page = await client.listCollection(limit: 1);
      expect(page.items.single.code, 'VERT-001');

      final detail = await client.getWorkDetail(page.items.single.workId);
      expect(detail.title, 'Authenticated fixture');
      expect(detail.media, hasLength(1));
      expect(detail.media.single.mediaId.value, 'media-vertical');

      final playback = await client.createPlaybackSession(
        const AvacaMediaId('media-vertical'),
      );
      final sessionId = playback.sessionId;
      final resourceId = playback.resourceId;
      expect(sessionId, isNotNull);
      expect(resourceId, 'resource-vertical');
      final opened = await client.openResource(playback);
      expect(opened.contentLength, mediaBytes.length);

      // A native player seek is represented by the same bounded range
      // contract: the client asks for bytes at the new absolute offset.
      final seeked = await client.readResource(opened.resourceHandle, 24, 16);
      expect(seeked.offset, 24);
      expect(seeked.bytes, orderedEquals(mediaBytes.sublist(24, 40)));

      // Stop closes the resource and then the short-lived playback session.
      await client.closeResource(opened.resourceHandle);
      await client.closePlaybackSession(sessionId!);
    } finally {
      await client.close();
      await serverSession.close();
      await serve;
    }
  });

  test('client host coalesces concurrent close calls', () async {
    final transport = _CloseTrackingTransport();
    final host = AvacaClientApplicationHost(transport: transport);
    await Future.wait<void>([host.close(), host.close(), host.close()]);
    expect(transport.closeCalls, 1);
  });
}

Future<AvacaFrame> _handleServerRequest(
  AvacaFrame request,
  Uint8List mediaBytes,
) async {
  const codec = AvacaApplicationCodec();
  switch (request.opcode) {
    case AvacaOpcode.getCapabilities:
      return _response(
        request,
        AvacaOpcode.capabilities,
        codec.encodeCapabilities(
          const AvacaCapabilitiesDto(
            serverId: AvacaServerId('server-vertical'),
            features: <String>{'catalog', 'details', 'playback-range'},
            maxCollectionPageSize: 100,
            maxReadBytes: 4 * 1024 * 1024,
          ),
        ),
      );
    case AvacaOpcode.listCollection:
      codec.decodeCollectionRequest(request.payload);
      return _response(
        request,
        AvacaOpcode.collectionPage,
        codec.encodeCollectionPage(
          const AvacaCollectionPageDto(
            items: <AvacaWorkCardDto>[
              AvacaWorkCardDto(
                workId: AvacaWorkId('work-vertical'),
                code: 'VERT-001',
                title: 'Authenticated fixture',
              ),
            ],
          ),
        ),
      );
    case AvacaOpcode.getWorkDetail:
      final workId = codec.decodeIdRequest(request.payload);
      return _response(
        request,
        AvacaOpcode.workDetail,
        codec.encodeWorkDetail(
          AvacaWorkDetailDto(
            workId: AvacaWorkId(workId),
            code: 'VERT-001',
            title: 'Authenticated fixture',
            performers: const <AvacaPerformerDto>[],
            media: const <AvacaMediaCardDto>[
              AvacaMediaCardDto(
                mediaId: AvacaMediaId('media-vertical'),
                workId: AvacaWorkId('work-vertical'),
                code: 'VERT-001',
                title: 'Authenticated fixture',
                availability: AvacaMediaAvailability.available,
              ),
            ],
          ),
        ),
      );
    case AvacaOpcode.createPlaybackSession:
      codec.decodeIdRequest(request.payload);
      return _response(
        request,
        AvacaOpcode.playbackSessionCreated,
        codec.encodePlaybackSession(
          AvacaPlaybackSessionDto(
            playbackSessionId: 'session-vertical',
            resourceId: 'resource-vertical',
            playbackGrant: Uint8List(32),
            contentLength: mediaBytes.length,
            mimeType: 'video/x-matroska',
          ),
        ),
      );
    case AvacaOpcode.openResource:
      final open = codec.decodeResourceOpenRequest(request.payload);
      if (open.resourceId != 'resource-vertical' ||
          open.playbackSessionId != 'session-vertical' ||
          open.playbackGrant.any((byte) => byte != 0)) {
        throw StateError('unexpected resource id');
      }
      return _response(
        request,
        AvacaOpcode.resourceOpened,
        codec.encodeResourceOpened(
          AvacaResourceOpenedDto(
            resourceHandle: 'handle-vertical',
            contentLength: mediaBytes.length,
            mimeType: 'video/x-matroska',
          ),
        ),
      );
    case AvacaOpcode.readResource:
      final range = codec.decodeRangeRequest(request.payload);
      final bytes = mediaBytes.sublist(
        range.offset,
        range.offset + range.length,
      );
      return _response(
        request,
        AvacaOpcode.resourceChunk,
        codec.encodeResourceChunk(
          AvacaResourceChunkDto(
            offset: range.offset,
            bytes: bytes,
            eof: range.offset + bytes.length >= mediaBytes.length,
          ),
        ),
      );
    case AvacaOpcode.closeResource:
      return _response(request, AvacaOpcode.resourceClosed, request.payload);
    case AvacaOpcode.closePlaybackSession:
      return _response(
        request,
        AvacaOpcode.playbackSessionClosed,
        request.payload,
      );
    default:
      throw StateError('unsupported fixture opcode ${request.opcode}');
  }
}

AvacaFrame _response(
  AvacaFrame request,
  AvacaOpcode opcode,
  List<int> payload,
) => AvacaFrame(opcode: opcode, requestId: request.requestId, payload: payload);

final class _MemoryConnectionPair {
  _MemoryConnectionPair() {
    client._peer = server;
    server._peer = client;
  }

  final _MemoryConnection client = _MemoryConnection();
  final _MemoryConnection server = _MemoryConnection();
}

final class _MemoryConnection implements AvacaRemoteConnection {
  final StreamController<Uint8List> _incoming = StreamController<Uint8List>();
  _MemoryConnection? _peer;
  bool _open = true;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  bool get isOpen => _open;

  @override
  Future<Uint8List> get channelBinding async =>
      Uint8List.fromList(List<int>.filled(32, 0x5a));

  @override
  Future<void> write(Uint8List bytes) async {
    final peer = _peer;
    if (!_open || peer == null || !peer._open) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'memory connection is closed',
      );
    }
    peer._incoming.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    await _incoming.close();
    final peer = _peer;
    if (peer != null && peer._open) {
      peer._open = false;
      await peer._incoming.close();
    }
  }
}

final class _CloseTrackingTransport implements AvacaRemoteTransport {
  int closeCalls = 0;

  @override
  AvacaRemoteRole get role => AvacaRemoteRole.client;

  @override
  Future<AvacaRemoteConnection> connect(AvacaRemoteEndpoint endpoint) {
    throw UnsupportedError('close test does not connect');
  }

  @override
  Future<AvacaRemoteListener> listen(
    AvacaRemoteConnectionHandler onConnection,
  ) {
    throw UnsupportedError('close test does not listen');
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }
}
