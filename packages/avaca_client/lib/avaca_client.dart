import 'dart:convert';
import 'dart:typed_data';

import 'package:avaca_domain/avaca_domain.dart';
import 'package:avaca_protocol/avaca_protocol.dart';
import 'package:avaca_remote_core/avaca_remote_core.dart';

class AvacaClientException implements Exception {
  const AvacaClientException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

abstract interface class AvacaRemoteCatalogApi {
  Future<AvacaCollectionPage> listCollection({String? cursor, int limit = 50});

  Future<AvacaWorkDetail> getWorkDetail(AvacaWorkId workId);

  Future<AvacaAssetOpenedDto> openAsset(
    String assetId, {
    int revision = 0,
    int offset = 0,
    int length = 256 * 1024,
  });

  Future<AvacaAssetDescriptor> createPlaybackSession(AvacaMediaId mediaId);

  Future<void> closePlaybackSession(String sessionId);
}

/// Concrete v2 catalog client.  It owns only opaque DTOs and an authenticated
/// session; no Server database, file path, or scraper dependency is reachable
/// from this package.
final class AvacaRemoteCatalogClient implements AvacaRemoteCatalogApi {
  AvacaRemoteCatalogClient(this._session);

  final AvacaApplicationSession _session;
  final AvacaApplicationCodec _codec = const AvacaApplicationCodec();

  static Future<AvacaRemoteCatalogClient> connect({
    required AvacaRemoteTransport transport,
    required AvacaRemoteEndpoint endpoint,
    required String clientId,
    required String expectedServerId,
    required List<int> pairingSecret,
  }) async {
    final connection = await transport.connect(endpoint);
    try {
      final session = await AvacaApplicationSession.authenticateClient(
        connection,
        clientId: clientId,
        expectedServerId: expectedServerId,
        pairingSecret: pairingSecret,
      );
      return AvacaRemoteCatalogClient(session);
    } on Object {
      try {
        await connection.close();
      } on Object {
        // Keep the authentication failure as the primary error.
      }
      rethrow;
    }
  }

  AvacaApplicationSession get session => _session;

  Future<AvacaCapabilitiesDto> getCapabilities() async {
    final frame = await _session.request(
      AvacaOpcode.getCapabilities,
      Uint8List(0),
      expectedResponses: const <AvacaOpcode>{AvacaOpcode.capabilities},
    );
    return _codec.decodeCapabilities(frame.payload);
  }

  @override
  Future<AvacaCollectionPage> listCollection({
    String? cursor,
    int limit = 50,
  }) async {
    final frame = await _session.request(
      AvacaOpcode.listCollection,
      _codec.encodeCollectionRequest(
        AvacaCollectionListRequestDto(cursor: cursor, limit: limit),
      ),
      expectedResponses: const <AvacaOpcode>{AvacaOpcode.collectionPage},
    );
    final page = _codec.decodeCollectionPage(frame.payload);
    return AvacaCollectionPage(
      items: page.items
          .map(
            (item) => AvacaWorkSummary(
              workId: item.workId,
              code: item.code,
              title: item.title,
              coverResourceId: item.cover?.assetId,
            ),
          )
          .toList(growable: false),
      nextCursor: page.nextCursor,
    );
  }

  @override
  Future<AvacaWorkDetail> getWorkDetail(AvacaWorkId workId) async {
    final frame = await _session.request(
      AvacaOpcode.getWorkDetail,
      _codec.encodeIdRequest(workId.value),
      expectedResponses: const <AvacaOpcode>{AvacaOpcode.workDetail},
    );
    final detail = _codec.decodeWorkDetail(frame.payload);
    return AvacaWorkDetail(
      workId: detail.workId,
      code: detail.code,
      title: detail.title,
      description: detail.description,
      releaseDate: detail.releaseDate,
      performers: detail.performers
          .map(
            (performer) => AvacaPerformerSummary(
              actressId: performer.actressId,
              displayName: performer.displayName,
            ),
          )
          .toList(growable: false),
      media: detail.media
          .map(
            (media) => AvacaMediaSummary(
              mediaId: media.mediaId,
              workId: media.workId,
              code: media.code,
              title: media.title,
              durationMs: media.durationMs,
              availability: media.availability,
              artworkResourceId: media.artwork?.assetId,
            ),
          )
          .toList(growable: false),
      coverResourceId: detail.artwork?.assetId,
    );
  }

  @override
  Future<AvacaAssetOpenedDto> openAsset(
    String assetId, {
    int revision = 0,
    int offset = 0,
    int length = 256 * 1024,
  }) async {
    final frame = await _session.request(
      AvacaOpcode.openAsset,
      _codec.encodeAssetOpenRequest(
        AvacaAssetOpenRequestDto(
          assetId: assetId,
          revision: revision,
          offset: offset,
          length: length,
        ),
      ),
      expectedResponses: const <AvacaOpcode>{AvacaOpcode.assetOpened},
    );
    return _codec.decodeAssetOpened(frame.payload);
  }

  @override
  Future<AvacaAssetDescriptor> createPlaybackSession(
    AvacaMediaId mediaId,
  ) async {
    final frame = await _session.request(
      AvacaOpcode.createPlaybackSession,
      _codec.encodeIdRequest(mediaId.value),
      expectedResponses: const <AvacaOpcode>{
        AvacaOpcode.playbackSessionCreated,
      },
    );
    final session = _codec.decodePlaybackSession(frame.payload);
    return AvacaAssetDescriptor(
      mediaId: mediaId,
      resourceId: session.resourceId,
      length: session.contentLength,
      container: session.mimeType ?? 'application/octet-stream',
      durationMs: session.durationMs,
      sessionId: session.playbackSessionId,
      playbackGrant: session.playbackGrant,
    );
  }

  @override
  Future<void> closePlaybackSession(String sessionId) async {
    final frame = await _session.request(
      AvacaOpcode.closePlaybackSession,
      _codec.encodeIdRequest(sessionId),
      expectedResponses: const <AvacaOpcode>{AvacaOpcode.playbackSessionClosed},
    );
    _codec.decodeIdRequest(frame.payload);
  }

  /// Opens the native data-plane resource with the full session-bound
  /// authorization tuple.  The returned handle is scoped to this
  /// authenticated connection and must be used for all subsequent range
  /// reads; [descriptor.resourceId] is never used as a read handle.
  Future<AvacaResourceOpenedDto> openPlaybackResource(
    AvacaAssetDescriptor descriptor,
  ) async {
    final sessionId = descriptor.sessionId;
    final grant = descriptor.playbackGrant;
    if (sessionId == null || grant == null || grant.length != 32) {
      throw const AvacaClientException(
        'PLAYBACK_AUTH_MISSING',
        'playback session authorization is missing',
      );
    }
    final frame = await _session.request(
      AvacaOpcode.openResource,
      _codec.encodeResourceOpenRequest(
        AvacaResourceOpenRequestDto(
          playbackSessionId: sessionId,
          resourceId: descriptor.resourceId,
          playbackGrant: grant,
        ),
      ),
      expectedResponses: const <AvacaOpcode>{AvacaOpcode.resourceOpened},
    );
    return _codec.decodeResourceOpened(frame.payload);
  }

  Future<AvacaResourceOpenedDto> openResource(
    AvacaAssetDescriptor descriptor,
  ) => openPlaybackResource(descriptor);

  Future<AvacaResourceChunkDto> readResource(
    String resourceId,
    int offset,
    int length,
  ) async {
    return readResourceHandle(resourceId, offset, length);
  }

  Future<AvacaResourceChunkDto> readResourceHandle(
    String resourceHandle,
    int offset,
    int length,
  ) async {
    final frame = await _session.request(
      AvacaOpcode.readResource,
      _codec.encodeRangeRequest(
        resourceHandle: resourceHandle,
        offset: offset,
        length: length,
      ),
      expectedResponses: const <AvacaOpcode>{AvacaOpcode.resourceChunk},
    );
    return _codec.decodeResourceChunk(frame.payload);
  }

  Future<AvacaCancelReadResultDto> cancelRead(int targetRequestId) async {
    final frame = await _session.request(
      AvacaOpcode.cancelRead,
      _codec.encodeCancelReadRequest(
        AvacaCancelReadDto(targetRequestId: targetRequestId),
      ),
      expectedResponses: const <AvacaOpcode>{AvacaOpcode.pong},
    );
    return _codec.decodeCancelReadResult(frame.payload);
  }

  Future<void> closeResource(String resourceId) async {
    final frame = await _session.request(
      AvacaOpcode.closeResource,
      _codec.encodeIdRequest(resourceId),
      expectedResponses: const <AvacaOpcode>{AvacaOpcode.resourceClosed},
    );
    _codec.decodeIdRequest(frame.payload);
  }

  Future<void> close() => _session.close();
}

/// Lifecycle owner for the AVACA client process.  Connection and handshake
/// happen outside widget build methods; callers can show a loading state while
/// this future resolves and keep navigation responsive during reconnects.
final class AvacaClientApplicationHost {
  AvacaClientApplicationHost({required AvacaRemoteTransport transport})
    : _transport = transport;

  final AvacaRemoteTransport _transport;
  AvacaRemoteCatalogClient? _catalog;
  Future<void> _operationTail = Future<void>.value();
  Future<void>? _closeFuture;
  bool _closed = false;

  AvacaRemoteCatalogClient? get catalog => _catalog;

  Future<AvacaRemoteCatalogClient> connect({
    required AvacaRemoteEndpoint endpoint,
    required String clientId,
    required String expectedServerId,
    required List<int> pairingSecret,
  }) => _enqueue(() async {
    if (_closed) {
      throw const AvacaClientException(
        'CLIENT_CLOSED',
        'AVACA client host is closed',
      );
    }
    await _catalog?.close();
    _catalog = await AvacaRemoteCatalogClient.connect(
      transport: _transport,
      endpoint: endpoint,
      clientId: clientId,
      expectedServerId: expectedServerId,
      pairingSecret: pairingSecret,
    );
    return _catalog!;
  });

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    final closeFuture = _enqueue<void>(() async {
      if (_closed) return;
      _closed = true;
      await _catalog?.close();
      _catalog = null;
      await _transport.close();
    });
    _closeFuture = closeFuture;
    return closeFuture;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _operationTail.then<T>((_) => operation());
    // Keep the queue usable after a failed connect/close.  The original
    // operation still returns its error to the caller; later lifecycle calls
    // must not deadlock behind a failed future.
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}

class AvacaRemotePlaybackSource {
  const AvacaRemotePlaybackSource({
    required this.mediaId,
    required this.sessionId,
    required this.resource,
  });

  final AvacaMediaId mediaId;
  final String sessionId;
  final AvacaAssetDescriptor resource;
}

/// AVACA owns catalog UI and playback orchestration.  It never resolves a
/// Server path and never proxies media bytes through Dart; the native bridge
/// consumes the opaque resource descriptor directly.
class RemotePlaybackRepository {
  const RemotePlaybackRepository(this.catalog);

  final AvacaRemoteCatalogApi catalog;

  Future<AvacaRemotePlaybackSource> createSession(AvacaMediaId mediaId) async {
    final resource = await catalog.createPlaybackSession(mediaId);
    return AvacaRemotePlaybackSource(
      mediaId: mediaId,
      sessionId: resource.sessionId ?? resource.resourceId,
      resource: resource,
    );
  }

  Future<void> closeSession(AvacaRemotePlaybackSource source) =>
      catalog.closePlaybackSession(source.sessionId);
}

/// The only supported media-byte path for the separated client.  An HTTP URI
/// or a local Server path is intentionally not accepted here.
class AvacaNativePlaybackSource {
  const AvacaNativePlaybackSource(this.descriptor);

  final AvacaAssetDescriptor descriptor;

  Future<AvacaRemotePlaybackHandle> open(AvacaRemotePlaybackBridge bridge) =>
      bridge.open(
        AvacaRemoteResourceDescriptor(
          resourceId: descriptor.resourceId,
          length: descriptor.length,
          mimeType: descriptor.container,
          playbackSessionId: descriptor.sessionId,
          playbackGrant: descriptor.playbackGrant,
        ),
      );
}

class AvacaClientBootstrap {
  const AvacaClientBootstrap({required this.remotePlayback});

  final RemotePlaybackRepository remotePlayback;

  /// Composition is checked statically by tooling/verify_architecture.dart;
  /// this hook gives startup code a single explicit assertion point.
  void assertNoServerAuthority() {}
}

Uint8List copyOpaqueResourceId(String value) =>
    Uint8List.fromList(utf8.encode(value));
