import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:avaca_domain/avaca_domain.dart';
import 'package:avaca_library/avaca_library.dart';
import 'package:avaca_protocol/avaca_protocol.dart';
import 'package:avaca_remote_core/avaca_remote_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Server SQLite catalog uses its own schema and supports paging',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca-server-db-',
      );
      final repository = await ServerSqliteCatalogRepository.open(
        databasePath: '${directory.path}${Platform.pathSeparator}server.sqlite',
      );
      try {
        await repository.upsertWork(
          const AvacaWorkSummary(
            workId: AvacaWorkId('work-db-1'),
            code: 'DB-001',
            title: 'Server-owned',
          ),
        );
        await repository.upsertWork(
          const AvacaWorkSummary(
            workId: AvacaWorkId('work-db-2'),
            code: 'DB-002',
            title: 'Server-owned 2',
          ),
        );
        final mediaFile1 = File(
          '${directory.path}${Platform.pathSeparator}server-media-1.mkv',
        );
        final mediaFile2 = File(
          '${directory.path}${Platform.pathSeparator}server-media-2.mkv',
        );
        await mediaFile1.writeAsBytes(const <int>[1, 2, 3, 4]);
        await mediaFile2.writeAsBytes(const <int>[5, 6, 7, 8]);
        await repository.upsertMedia(
          ServerMediaRecord(
            mediaId: const AvacaMediaId('media-db-1'),
            workId: const AvacaWorkId('work-db-1'),
            absolutePath: mediaFile1.path,
            length: 4,
            durationMs: 1234,
          ),
        );
        await repository.upsertMedia(
          ServerMediaRecord(
            mediaId: const AvacaMediaId('media-db-2'),
            workId: const AvacaWorkId('work-db-2'),
            absolutePath: mediaFile2.path,
            length: 4,
          ),
        );
        final firstPage = await repository.listCollection(limit: 1);
        expect(firstPage.items, hasLength(1));
        expect(firstPage.nextCursor, isNotNull);
        final secondPage = await repository.listCollection(
          cursor: firstPage.nextCursor,
          limit: 1,
        );
        expect(secondPage.items, hasLength(1));
        expect(secondPage.nextCursor, isNull);
        final detail = await repository.getWorkDetail(
          const AvacaWorkId('work-db-1'),
        );
        expect(detail.title, 'Server-owned');
        expect(detail.media, hasLength(1));
        expect(detail.media.single.mediaId.value, 'media-db-1');
        expect(
          detail.media.single.availability,
          AvacaMediaAvailability.available,
        );
      } finally {
        await repository.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('catalog and playback vertical slice keeps paths server-side', () async {
    final directory = await Directory.systemTemp.createTemp('avaca-server-');
    final media = File('${directory.path}${Platform.pathSeparator}fixture.mkv');
    await media.writeAsBytes(
      Uint8List.fromList(List<int>.generate(64, (i) => i)),
    );
    final grants = PlaybackGrantRegistry();
    final sessions = PlaybackSessionService(grants: grants);
    final resources = ServerMediaResourceService(grants: grants);
    final handler = AvacaServerApplicationHandler(
      serverId: const AvacaServerId('server-1'),
      catalog: ServerCatalogService(_Catalog()),
      playbackSessions: sessions,
      resources: resources,
      resolvePlayback: (mediaId) async => ServerPlaybackSelection(
        mediaId: mediaId,
        resourceId: 'resource-1',
        absolutePath: media.path,
        length: 64,
      ),
    );
    const codec = AvacaApplicationCodec();

    try {
      final page = await handler.handle(
        const AvacaFrame(
          opcode: AvacaOpcode.listCollection,
          requestId: 1,
          payload: <int>[],
        ),
      );
      // The empty payload is not a valid JSON request; verify the typed error
      // instead of allowing a filesystem call to happen on malformed input.
      fail('expected malformed request, got ${page.opcode}');
    } on ServerProtocolException catch (error) {
      expect(error.code, 'internal');
    }

    final listRequest = AvacaFrame(
      opcode: AvacaOpcode.listCollection,
      requestId: 2,
      payload: codec.encodeCollectionRequest(
        const AvacaCollectionListRequestDto(limit: 1),
      ),
    );
    final pageResponse = await handler.handle(listRequest);
    expect(pageResponse.opcode, AvacaOpcode.collectionPage);
    final pageDto = codec.decodeCollectionPage(pageResponse.payload);
    expect(pageDto.items.single.workId.value, 'work-1');

    final sessionResponse = await handler.handle(
      AvacaFrame(
        opcode: AvacaOpcode.createPlaybackSession,
        requestId: 3,
        payload: codec.encodeIdRequest('media-1'),
      ),
    );
    final playback = codec.decodePlaybackSession(sessionResponse.payload);
    expect(playback.playbackGrant, hasLength(32));
    expect(
      String.fromCharCodes(sessionResponse.payload),
      isNot(contains(media.path)),
    );

    final opened = await handler.handle(
      AvacaFrame(
        opcode: AvacaOpcode.openResource,
        requestId: 4,
        payload: codec.encodeResourceOpenRequest(
          AvacaResourceOpenRequestDto(
            playbackSessionId: playback.playbackSessionId,
            resourceId: playback.resourceId,
            playbackGrant: playback.playbackGrant,
          ),
        ),
      ),
    );
    final openedDto = codec.decodeResourceOpened(opened.payload);
    expect(openedDto.contentLength, 64);

    final chunk = await handler.handle(
      AvacaFrame(
        opcode: AvacaOpcode.readResource,
        requestId: 5,
        payload: codec.encodeRangeRequest(
          resourceHandle: openedDto.resourceHandle,
          offset: 8,
          length: 16,
        ),
      ),
    );
    final bytes = codec.decodeResourceChunk(chunk.payload);
    expect(bytes.offset, 8);
    expect(bytes.bytes, orderedEquals(List<int>.generate(16, (i) => i + 8)));

    await handler.handle(
      AvacaFrame(
        opcode: AvacaOpcode.closeResource,
        requestId: 6,
        payload: codec.encodeIdRequest(openedDto.resourceHandle),
      ),
    );
    await handler.close();
    await resources.closeAll();
    await directory.delete(recursive: true);
  });

  test(
    'playback resources are isolated per session and close releases files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca-server-session-',
      );
      final media = File(
        '${directory.path}${Platform.pathSeparator}fixture.mkv',
      );
      await media.writeAsBytes(
        Uint8List.fromList(List<int>.generate(32, (i) => i)),
      );
      final grants = PlaybackGrantRegistry();
      final sessions = PlaybackSessionService(grants: grants);
      final resources = ServerMediaResourceService(grants: grants);
      final handler = AvacaServerApplicationHandler(
        serverId: const AvacaServerId('server-1'),
        catalog: ServerCatalogService(_Catalog()),
        playbackSessions: sessions,
        resources: resources,
        resolvePlayback: (mediaId) async => ServerPlaybackSelection(
          mediaId: mediaId,
          resourceId: 'stable-media-selection',
          absolutePath: media.path,
          length: 32,
        ),
      );
      const codec = AvacaApplicationCodec();
      try {
        final first = codec.decodePlaybackSession(
          (await handler.handle(
            AvacaFrame(
              opcode: AvacaOpcode.createPlaybackSession,
              requestId: 1,
              payload: codec.encodeIdRequest('media-1'),
            ),
          )).payload,
        );
        final second = codec.decodePlaybackSession(
          (await handler.handle(
            AvacaFrame(
              opcode: AvacaOpcode.createPlaybackSession,
              requestId: 2,
              payload: codec.encodeIdRequest('media-1'),
            ),
          )).payload,
        );
        expect(first.resourceId, isNot(second.resourceId));
        expect(grants.activeCount, 2);

        await handler.handle(
          AvacaFrame(
            opcode: AvacaOpcode.openResource,
            requestId: 3,
            payload: codec.encodeResourceOpenRequest(
              AvacaResourceOpenRequestDto(
                playbackSessionId: first.playbackSessionId,
                resourceId: first.resourceId,
                playbackGrant: first.playbackGrant,
              ),
            ),
          ),
        );
        final secondOpened = codec.decodeResourceOpened(
          (await handler.handle(
            AvacaFrame(
              opcode: AvacaOpcode.openResource,
              requestId: 4,
              payload: codec.encodeResourceOpenRequest(
                AvacaResourceOpenRequestDto(
                  playbackSessionId: second.playbackSessionId,
                  resourceId: second.resourceId,
                  playbackGrant: second.playbackGrant,
                ),
              ),
            ),
          )).payload,
        );
        expect(grants.activeCount, 2);

        await handler.handle(
          AvacaFrame(
            opcode: AvacaOpcode.closePlaybackSession,
            requestId: 5,
            payload: codec.encodeIdRequest(first.playbackSessionId),
          ),
        );
        expect(grants.activeCount, 1);
        final secondChunk = codec.decodeResourceChunk(
          (await handler.handle(
            AvacaFrame(
              opcode: AvacaOpcode.readResource,
              requestId: 6,
              payload: codec.encodeRangeRequest(
                resourceHandle: secondOpened.resourceHandle,
                offset: 4,
                length: 8,
              ),
            ),
          )).payload,
        );
        expect(
          secondChunk.bytes,
          orderedEquals(List<int>.generate(8, (i) => i + 4)),
        );
      } finally {
        await handler.close();
        await resources.closeAll();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'cancelRead interrupts a blocked range request without fake EOF',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca-server-cancel-',
      );
      final media = File(
        '${directory.path}${Platform.pathSeparator}fixture.mkv',
      );
      await media.writeAsBytes(const <int>[1, 2, 3, 4]);
      final grants = PlaybackGrantRegistry();
      final sessions = PlaybackSessionService(grants: grants);
      final resources = _BlockingResourceService(grants: grants);
      final handler = AvacaServerApplicationHandler(
        serverId: const AvacaServerId('server-1'),
        catalog: ServerCatalogService(_Catalog()),
        playbackSessions: sessions,
        resources: resources,
        resolvePlayback: (mediaId) async => ServerPlaybackSelection(
          mediaId: mediaId,
          resourceId: 'resource-cancel',
          absolutePath: media.path,
          length: 4,
        ),
      );
      const codec = AvacaApplicationCodec();
      try {
        final created = codec.decodePlaybackSession(
          (await handler.handle(
            AvacaFrame(
              opcode: AvacaOpcode.createPlaybackSession,
              requestId: 1,
              payload: codec.encodeIdRequest('media-1'),
            ),
          )).payload,
        );
        final opened = codec.decodeResourceOpened(
          (await handler.handle(
            AvacaFrame(
              opcode: AvacaOpcode.openResource,
              requestId: 2,
              payload: codec.encodeResourceOpenRequest(
                AvacaResourceOpenRequestDto(
                  playbackSessionId: created.playbackSessionId,
                  resourceId: created.resourceId,
                  playbackGrant: created.playbackGrant,
                ),
              ),
            ),
          )).payload,
        );
        final readFuture = handler.handle(
          AvacaFrame(
            opcode: AvacaOpcode.readResource,
            requestId: 10,
            payload: codec.encodeRangeRequest(
              resourceHandle: opened.resourceHandle,
              offset: 0,
              length: 4,
            ),
          ),
        );
        final readExpectation = expectLater(
          readFuture,
          throwsA(
            isA<ServerProtocolException>().having(
              (error) => error.code,
              'code',
              'cancelled',
            ),
          ),
        );
        await resources.readStarted.future;

        final cancelResponse = await handler.handle(
          AvacaFrame(
            opcode: AvacaOpcode.cancelRead,
            requestId: 11,
            payload: codec.encodeCancelReadRequest(
              const AvacaCancelReadDto(targetRequestId: 10),
            ),
          ),
        );
        final cancelled = codec.decodeCancelReadResult(cancelResponse.payload);
        expect(cancelled.targetRequestId, 10);
        expect(cancelled.cancelled, isTrue);
        await readExpectation;
      } finally {
        if (!resources.release.isCompleted) resources.release.complete();
        await handler.close();
        await resources.closeAll();
        await directory.delete(recursive: true);
      }
    },
  );

  test('handler close revokes unclosed sessions and duplicate opens', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca-server-close-',
    );
    final media = File('${directory.path}${Platform.pathSeparator}fixture.mkv');
    await media.writeAsBytes(
      Uint8List.fromList(List<int>.generate(8, (i) => i)),
    );
    final grants = PlaybackGrantRegistry();
    final sessions = PlaybackSessionService(grants: grants);
    final resources = ServerMediaResourceService(grants: grants);
    final handler = AvacaServerApplicationHandler(
      serverId: const AvacaServerId('server-1'),
      catalog: ServerCatalogService(_Catalog()),
      playbackSessions: sessions,
      resources: resources,
      resolvePlayback: (mediaId) async => ServerPlaybackSelection(
        mediaId: mediaId,
        resourceId: 'stable-media-selection',
        absolutePath: media.path,
        length: 8,
      ),
    );
    const codec = AvacaApplicationCodec();
    try {
      final created = codec.decodePlaybackSession(
        (await handler.handle(
          AvacaFrame(
            opcode: AvacaOpcode.createPlaybackSession,
            requestId: 1,
            payload: codec.encodeIdRequest('media-1'),
          ),
        )).payload,
      );
      await handler.handle(
        AvacaFrame(
          opcode: AvacaOpcode.openResource,
          requestId: 2,
          payload: codec.encodeResourceOpenRequest(
            AvacaResourceOpenRequestDto(
              playbackSessionId: created.playbackSessionId,
              resourceId: created.resourceId,
              playbackGrant: created.playbackGrant,
            ),
          ),
        ),
      );
      await handler.handle(
        AvacaFrame(
          opcode: AvacaOpcode.openResource,
          requestId: 3,
          payload: codec.encodeResourceOpenRequest(
            AvacaResourceOpenRequestDto(
              playbackSessionId: created.playbackSessionId,
              resourceId: created.resourceId,
              playbackGrant: created.playbackGrant,
            ),
          ),
        ),
      );
      expect(grants.activeCount, 1);
      await handler.close();
      // This handler represents the native data-plane connection.  Closing it
      // releases its native lease; a Dart control connection would only call
      // detachControl and keep a session alive while another native lease is
      // active.
      expect(grants.activeCount, 0);
      expect(sessions.tokenForResource(created.resourceId), isNull);
      sessions.closeAll();
      expect(grants.activeCount, 0);
    } finally {
      await handler.close();
      await resources.closeAll();
      await directory.delete(recursive: true);
    }
  });

  test(
    'control disconnect keeps a native lease alive and enforces client ownership',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca-server-dual-session-',
      );
      final media = File(
        '${directory.path}${Platform.pathSeparator}fixture.mkv',
      );
      await media.writeAsBytes(
        Uint8List.fromList(List<int>.generate(16, (i) => i)),
      );
      final grants = PlaybackGrantRegistry();
      final sessions = PlaybackSessionService(grants: grants);
      final resources = ServerMediaResourceService(grants: grants);
      AvacaServerApplicationHandler handler(String clientId) =>
          AvacaServerApplicationHandler(
            serverId: const AvacaServerId('server-1'),
            clientId: clientId,
            catalog: ServerCatalogService(_Catalog()),
            playbackSessions: sessions,
            resources: resources,
            resolvePlayback: (mediaId) async => ServerPlaybackSelection(
              mediaId: mediaId,
              resourceId: 'stable-media-selection',
              absolutePath: media.path,
              length: 16,
            ),
          );
      final control = handler('client-1');
      final native = handler('client-1');
      final wrongClient = handler('client-2');
      const codec = AvacaApplicationCodec();

      try {
        final created = codec.decodePlaybackSession(
          (await control.handle(
            AvacaFrame(
              opcode: AvacaOpcode.createPlaybackSession,
              requestId: 1,
              payload: codec.encodeIdRequest('media-1'),
            ),
          )).payload,
        );
        final openPayload = codec.encodeResourceOpenRequest(
          AvacaResourceOpenRequestDto(
            playbackSessionId: created.playbackSessionId,
            resourceId: created.resourceId,
            playbackGrant: created.playbackGrant,
          ),
        );

        final opened = codec.decodeResourceOpened(
          (await native.handle(
            AvacaFrame(
              opcode: AvacaOpcode.openResource,
              requestId: 2,
              payload: openPayload,
            ),
          )).payload,
        );
        expect(grants.activeCount, 1);

        await control.close();
        expect(sessions.activeCount, 1);
        final chunk = codec.decodeResourceChunk(
          (await native.handle(
            AvacaFrame(
              opcode: AvacaOpcode.readResource,
              requestId: 3,
              payload: codec.encodeRangeRequest(
                resourceHandle: opened.resourceHandle,
                offset: 4,
                length: 4,
              ),
            ),
          )).payload,
        );
        expect(chunk.bytes, orderedEquals(const <int>[4, 5, 6, 7]));

        await expectLater(
          wrongClient.handle(
            AvacaFrame(
              opcode: AvacaOpcode.openResource,
              requestId: 4,
              payload: openPayload,
            ),
          ),
          throwsA(
            isA<ServerProtocolException>().having(
              (error) => error.code,
              'code',
              'PLAYBACK_AUTH_INVALID',
            ),
          ),
        );

        await native.close();
        expect(sessions.activeCount, 0);
        expect(grants.activeCount, 0);
      } finally {
        await control.close();
        await native.close();
        await wrongClient.close();
        await resources.closeAll();
        await directory.delete(recursive: true);
      }
    },
  );

  test('playback authorization expiry uses the injected clock', () {
    var now = DateTime.utc(2026, 9, 9, 1);
    final grants = PlaybackGrantRegistry(clock: () => now);
    final sessions = PlaybackSessionService(grants: grants, clock: () => now);
    final created = sessions.create(
      mediaId: const AvacaMediaId('media-1'),
      resourceId: 'media-selection',
      absolutePath: 'C:/server/fixture.mkv',
      length: 1,
      lifetime: const Duration(minutes: 1),
    );
    expect(
      sessions
          .authorize(
            clientId: created.clientId,
            playbackSessionId: created.sessionId,
            resourceId: created.grant.resourceId,
            playbackGrant: created.grant.grant,
          )
          .length,
      1,
    );
    now = now.add(const Duration(minutes: 1, seconds: 1));
    expect(
      () => sessions.authorize(
        clientId: created.clientId,
        playbackSessionId: created.sessionId,
        resourceId: created.grant.resourceId,
        playbackGrant: created.grant.grant,
      ),
      throwsA(
        isA<ServerLibraryException>().having(
          (error) => error.code,
          'code',
          'PLAYBACK_AUTH_INVALID',
        ),
      ),
    );
    expect(grants.activeCount, 0);
  });

  test(
    'multiple native leases keep one session alive until the last release',
    () {
      var now = DateTime.utc(2026, 9, 9, 1);
      final grants = PlaybackGrantRegistry(clock: () => now);
      final sessions = PlaybackSessionService(grants: grants, clock: () => now);
      final created = sessions.create(
        mediaId: const AvacaMediaId('media-1'),
        resourceId: 'media-selection',
        absolutePath: 'C:/server/fixture.mkv',
        length: 1,
        clientId: 'client-1',
        lifetime: const Duration(minutes: 1),
      );

      final firstLease = sessions.attachNative(
        clientId: 'client-1',
        playbackSessionId: created.sessionId,
        resourceId: created.grant.resourceId,
        playbackGrant: created.grant.grant,
      );
      final secondLease = sessions.attachNative(
        clientId: 'client-1',
        playbackSessionId: created.sessionId,
        resourceId: created.grant.resourceId,
        playbackGrant: created.grant.grant,
      );
      sessions.detachControl(
        clientId: 'client-1',
        sessionId: created.sessionId,
        controlLeaseId: created.controlLeaseId,
      );
      expect(sessions.activeCount, 1);

      sessions.releaseNative(clientId: 'client-1', leaseId: firstLease);
      expect(sessions.activeCount, 1);
      expect(
        sessions
            .authorize(
              clientId: 'client-1',
              playbackSessionId: created.sessionId,
              resourceId: created.grant.resourceId,
              playbackGrant: created.grant.grant,
            )
            .length,
        1,
      );

      sessions.releaseNative(clientId: 'client-1', leaseId: secondLease);
      expect(sessions.activeCount, 0);
      expect(grants.activeCount, 0);
      now = now.add(const Duration(seconds: 1));
    },
  );

  test(
    'server host serializes start and close without leaving a listener',
    () async {
      final transport = _DelayedServerTransport();
      final grants = PlaybackGrantRegistry();
      final sessions = PlaybackSessionService(grants: grants);
      final resources = ServerMediaResourceService(grants: grants);
      final host = AvacaServerApplicationHost(
        serverId: 'server-lifecycle',
        pairingSecret: Uint8List(32),
        catalog: ServerCatalogService(_Catalog()),
        playbackSessions: sessions,
        resources: resources,
        resolvePlayback: (_) async => null,
      );

      final start = host.start(transport);
      // Closing while listen is still awaiting must queue behind start and then
      // close the listener.  This is the same race produced by a fast window
      // dispose/restart and must never leave a native listener orphaned.
      final close = host.close();
      await Future.wait<void>([start, close]);
      expect(transport.listenCalls, 1);
      expect(transport.listener?.closeCalls, 1);
      await host.close();
    },
  );

  test(
    'asset endpoint returns bounded bytes without leaking the cache path',
    () async {
      final directory = await Directory.systemTemp.createTemp('avaca-asset-');
      final assetFile = File(
        '${directory.path}${Platform.pathSeparator}cover.jpg',
      );
      await assetFile.writeAsBytes(const <int>[10, 11, 12, 13]);
      final grants = PlaybackGrantRegistry();
      final sessions = PlaybackSessionService(grants: grants);
      final resources = ServerMediaResourceService(grants: grants);
      final handler = AvacaServerApplicationHandler(
        serverId: const AvacaServerId('server-asset'),
        catalog: ServerCatalogService(_Catalog()),
        playbackSessions: sessions,
        resources: resources,
        resolvePlayback: (_) async => null,
        assetCatalog: _AssetCatalog(
          ServerAssetRecord(
            assetId: 'asset-cover',
            revision: 2,
            absolutePath: assetFile.path,
            length: 4,
            mimeType: 'image/jpeg',
          ),
        ),
      );
      try {
        const codec = AvacaApplicationCodec();
        final response = await handler.handle(
          AvacaFrame(
            opcode: AvacaOpcode.openAsset,
            requestId: 1,
            payload: codec.encodeAssetOpenRequest(
              const AvacaAssetOpenRequestDto(
                assetId: 'asset-cover',
                revision: 2,
                offset: 1,
                length: 2,
              ),
            ),
          ),
        );
        expect(response.opcode, AvacaOpcode.assetOpened);
        final opened = codec.decodeAssetOpened(response.payload);
        expect(opened.bytes, orderedEquals(const <int>[11, 12]));
        expect(
          String.fromCharCodes(response.payload),
          isNot(contains(assetFile.path)),
        );
        expect(String.fromCharCodes(response.payload), isNot(contains('\\')));
      } finally {
        await handler.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'asset endpoint fails closed for unknown, stale, missing, and mismatched assets',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca-asset-negative-',
      );
      final assetFile = File(
        '${directory.path}${Platform.pathSeparator}cover.jpg',
      );
      await assetFile.writeAsBytes(const <int>[10, 11, 12, 13]);
      final grants = PlaybackGrantRegistry();
      final sessions = PlaybackSessionService(grants: grants);
      final resources = ServerMediaResourceService(grants: grants);
      final asset = ServerAssetRecord(
        assetId: 'asset-cover',
        revision: 2,
        absolutePath: assetFile.path,
        length: 4,
        mimeType: 'image/jpeg',
      );
      final handler = AvacaServerApplicationHandler(
        serverId: const AvacaServerId('server-asset-negative'),
        catalog: ServerCatalogService(_Catalog()),
        playbackSessions: sessions,
        resources: resources,
        resolvePlayback: (_) async => null,
        assetCatalog: _AssetCatalog(asset),
      );
      const codec = AvacaApplicationCodec();

      Future<void> expectUnavailable(AvacaAssetOpenRequestDto request) async {
        await expectLater(
          handler.handle(
            AvacaFrame(
              opcode: AvacaOpcode.openAsset,
              requestId: 20,
              payload: codec.encodeAssetOpenRequest(request),
            ),
          ),
          throwsA(
            isA<ServerProtocolException>().having(
              (error) => error.code,
              'code',
              anyOf('asset_unavailable', 'asset_range_invalid'),
            ),
          ),
        );
      }

      try {
        await expectUnavailable(
          const AvacaAssetOpenRequestDto(
            assetId: 'unknown',
            revision: 2,
            offset: 0,
            length: 1,
          ),
        );
        await expectUnavailable(
          const AvacaAssetOpenRequestDto(
            assetId: 'asset-cover',
            revision: 1,
            offset: 0,
            length: 1,
          ),
        );
        await expectUnavailable(
          const AvacaAssetOpenRequestDto(
            assetId: 'asset-cover',
            revision: 2,
            offset: 5,
            length: 1,
          ),
        );
        await expectUnavailable(
          const AvacaAssetOpenRequestDto(
            assetId: 'asset-cover',
            revision: 2,
            offset: 1 << 62,
            length: 1,
          ),
        );

        await assetFile.writeAsBytes(const <int>[10, 11, 12]);
        await expectUnavailable(
          const AvacaAssetOpenRequestDto(
            assetId: 'asset-cover',
            revision: 2,
            offset: 0,
            length: 1,
          ),
        );

        await assetFile.writeAsBytes(const <int>[10, 11, 12, 13]);
        final missing = File(
          '${directory.path}${Platform.pathSeparator}missing.jpg',
        );
        final missingHandler = AvacaServerApplicationHandler(
          serverId: const AvacaServerId('server-asset-missing'),
          catalog: ServerCatalogService(_Catalog()),
          playbackSessions: PlaybackSessionService(
            grants: PlaybackGrantRegistry(),
          ),
          resources: ServerMediaResourceService(
            grants: PlaybackGrantRegistry(),
          ),
          resolvePlayback: (_) async => null,
          assetCatalog: _AssetCatalog(
            ServerAssetRecord(
              assetId: 'asset-missing',
              revision: 2,
              absolutePath: missing.path,
              length: 1,
              mimeType: 'image/jpeg',
            ),
          ),
        );
        try {
          await expectLater(
            missingHandler.handle(
              AvacaFrame(
                opcode: AvacaOpcode.openAsset,
                requestId: 21,
                payload: codec.encodeAssetOpenRequest(
                  const AvacaAssetOpenRequestDto(
                    assetId: 'asset-missing',
                    revision: 2,
                    offset: 0,
                    length: 1,
                  ),
                ),
              ),
            ),
            throwsA(
              isA<ServerProtocolException>().having(
                (error) => error.code,
                'code',
                'asset_unavailable',
              ),
            ),
          );
        } finally {
          await missingHandler.close();
        }
      } finally {
        await handler.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

final class _Catalog implements ServerCatalogRepository {
  @override
  Future<AvacaCollectionPage> listCollection({
    String? cursor,
    int limit = 50,
  }) async => const AvacaCollectionPage(
    items: <AvacaWorkSummary>[
      AvacaWorkSummary(
        workId: AvacaWorkId('work-1'),
        code: 'ABC-001',
        title: 'Fixture',
      ),
    ],
    nextCursor: null,
  );

  @override
  Future<AvacaWorkDetail> getWorkDetail(AvacaWorkId workId) async =>
      AvacaWorkDetail(workId: workId, code: 'ABC-001', title: 'Fixture');
}

final class _AssetCatalog implements ServerAssetCatalogRepository {
  _AssetCatalog(this.asset);

  final ServerAssetRecord asset;

  @override
  Future<ServerAssetRecord?> findAsset(String assetId, int revision) async =>
      asset.assetId == assetId && asset.revision == revision ? asset : null;
}

final class _BlockingResourceService extends ServerMediaResourceService {
  _BlockingResourceService({required super.grants});

  final Completer<void> readStarted = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<Uint8List> readAt(
    ServerMediaResourceHandle handle,
    int offset,
    int length,
  ) async {
    if (!readStarted.isCompleted) readStarted.complete();
    await release.future;
    return Uint8List.fromList(const <int>[1, 2, 3, 4]);
  }
}

final class _DelayedServerTransport implements AvacaRemoteTransport {
  int listenCalls = 0;
  _DelayedListener? listener;

  @override
  AvacaRemoteRole get role => AvacaRemoteRole.server;

  @override
  Future<AvacaRemoteConnection> connect(AvacaRemoteEndpoint endpoint) {
    throw UnsupportedError('lifecycle test does not connect');
  }

  @override
  Future<AvacaRemoteListener> listen(
    AvacaRemoteConnectionHandler onConnection,
  ) async {
    listenCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final created = _DelayedListener();
    listener = created;
    return created;
  }

  @override
  Future<void> close() async {}
}

final class _DelayedListener implements AvacaRemoteListener {
  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls++;
  }
}
