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
    final decoded = codec.decodeCollectionPage(
      codec.encodeCollectionPage(page),
    );
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
    final sessionDecoded = codec.decodePlaybackSession(
      codec.encodePlaybackSession(session),
    );
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

  test('base64 binary ranges fit the framed JSON boundary', () {
    final bytes = Uint8List.fromList(
      List<int>.generate(4096, (index) => index & 0xff),
    );
    final resource = codec.decodeResourceChunk(
      codec.encodeResourceChunk(
        AvacaResourceChunkDto(offset: 32, bytes: bytes, eof: false),
      ),
    );
    expect(resource.offset, 32);
    expect(resource.bytes, orderedEquals(bytes));

    final asset = codec.decodeAssetOpened(
      codec.encodeAssetOpened(
        AvacaAssetOpenedDto(
          assetId: 'asset-cover',
          revision: 3,
          offset: 32,
          bytes: bytes,
          eof: false,
          mimeType: 'image/jpeg',
        ),
      ),
    );
    expect(asset.bytes, orderedEquals(bytes));
  });

  test('asset ranges round-trip without a Server path or source URL', () {
    final request = const AvacaAssetOpenRequestDto(
      assetId: 'asset-cover',
      revision: 3,
      offset: 4,
      length: 8,
    );
    final wire = codec.encodeAssetOpenRequest(request);
    expect(String.fromCharCodes(wire), isNot(contains('C:\\')));
    expect(String.fromCharCodes(wire), isNot(contains('https://')));
    final decodedRequest = codec.decodeAssetOpenRequest(wire);
    expect(decodedRequest.assetId, 'asset-cover');
    expect(decodedRequest.revision, 3);

    final response = AvacaAssetOpenedDto(
      assetId: 'asset-cover',
      revision: 3,
      offset: 4,
      bytes: Uint8List.fromList(const <int>[1, 2, 3]),
      eof: true,
      mimeType: 'image/jpeg',
    );
    final decodedResponse = codec.decodeAssetOpened(
      codec.encodeAssetOpened(response),
    );
    expect(decodedResponse.bytes, orderedEquals(const <int>[1, 2, 3]));
    expect(decodedResponse.mimeType, 'image/jpeg');
  });

  test('asset ranges reject zero, negative, and oversized lengths', () {
    expect(
      () => codec.encodeAssetOpenRequest(
        const AvacaAssetOpenRequestDto(
          assetId: 'asset-cover',
          revision: 3,
          offset: 0,
          length: 0,
        ),
      ),
      throwsA(isA<AvacaProtocolException>()),
    );
    expect(
      () => codec.encodeAssetOpenRequest(
        AvacaAssetOpenRequestDto(
          assetId: 'asset-cover',
          revision: 3,
          offset: 0,
          length: AvacaApplicationCodec.maxBinaryRangeBytes + 1,
        ),
      ),
      throwsA(isA<AvacaProtocolException>()),
    );
    expect(
      () => codec.encodeAssetOpenRequest(
        const AvacaAssetOpenRequestDto(
          assetId: 'asset-cover',
          revision: 3,
          offset: -1,
          length: 1,
        ),
      ),
      throwsA(isA<AvacaProtocolException>()),
    );
    expect(
      () => codec.encodeAssetOpenRequest(
        const AvacaAssetOpenRequestDto(
          assetId: 'asset-cover',
          revision: 3,
          offset: 0,
          length: -1,
        ),
      ),
      throwsA(isA<AvacaProtocolException>()),
    );
    expect(
      () => codec.encodeAssetOpenRequest(
        const AvacaAssetOpenRequestDto(
          assetId: 'asset-cover',
          revision: 3,
          offset: 0,
          length: 4 * 1024 * 1024 + 1,
        ),
      ),
      throwsA(isA<AvacaProtocolException>()),
    );
  });
}
