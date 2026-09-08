import 'dart:typed_data';

import 'package:avaca_domain/avaca_domain.dart';
import 'package:avaca_protocol/avaca_protocol.dart';
import 'package:test/test.dart';

void main() {
  const codec = AvacaApplicationCodec();

  test('round-trips catalog and playback DTOs without paths', () {
    final page = AvacaCollectionPageDto(
      items: [
        const AvacaWorkCardDto(
          workId: AvacaWorkId('work-opaque'),
          code: 'ABC-001',
          title: 'Fixture',
          cover: AvacaAssetRefDto(assetId: 'asset-opaque', revision: 2),
        ),
      ],
      nextCursor: 'cursor-1',
    );
    final decoded = codec.decodeCollectionPage(codec.encodeCollectionPage(page));
    expect(decoded.items.single.workId.value, 'work-opaque');
    expect(decoded.items.single.cover?.revision, 2);
    expect(decoded.nextCursor, 'cursor-1');

    final session = AvacaPlaybackSessionDto(
      playbackSessionId: 'session-opaque',
      resourceId: 'resource-opaque',
      playbackGrant: Uint8List(32),
      contentLength: 4096,
      mimeType: 'video/x-matroska',
      durationMs: 1234,
      expiresAtMs: 99,
    );
    final sessionDecoded =
        codec.decodePlaybackSession(codec.encodePlaybackSession(session));
    expect(sessionDecoded.resourceId, 'resource-opaque');
    expect(sessionDecoded.playbackGrant, orderedEquals(Uint8List(32)));
  });

  test('rejects malformed and over-sized application payloads', () {
    expect(
      () => codec.decodeCollectionRequest(
        Uint8List.fromList(<int>[0x7b, 0x22, 0x6c, 0x69, 0x6d]),
      ),
      throwsA(isA<AvacaProtocolException>()),
    );
    expect(
      () => codec.encodeResourceChunk(
        AvacaResourceChunkDto(
          offset: 0,
          bytes: Uint8List(4 * 1024 * 1024 + 1),
          eof: false,
        ),
      ),
      throwsA(isA<AvacaProtocolException>()),
    );
  });

  test('range requests carry only opaque resource ids', () {
    final wire = codec.encodeRangeRequest(
      resourceId: 'resource-opaque',
      offset: 32,
      length: 128,
    );
    expect(String.fromCharCodes(wire), isNot(contains('C:\\')));
    final decoded = codec.decodeRangeRequest(wire);
    expect(decoded.resourceId, 'resource-opaque');
    expect(decoded.offset, 32);
    expect(decoded.length, 128);
  });
}
