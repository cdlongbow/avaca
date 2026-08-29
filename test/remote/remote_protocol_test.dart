import 'dart:typed_data';

import 'package:avaca/remote/remote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('frame codec enforces version, exact length, and phase bounds', () {
    const codec = RemoteFrameCodec();
    final frame = RemoteFrame(
      command: RemoteCommand.clientHello,
      flags: 0,
      requestId: 1,
      payload: Uint8List.fromList(<int>[1, 2, 3]),
    );
    final wire = codec.encode(frame, phase: RemoteFramePhase.preAuth);
    final decoded = codec.decode(wire, phase: RemoteFramePhase.preAuth);
    expect(decoded.command, RemoteCommand.clientHello);
    expect(decoded.requestId, 1);
    expect(decoded.payload, <int>[1, 2, 3]);
    expect(
      () => codec.decode(wire.sublist(0, wire.length - 1)),
      throwsA(isA<RemoteException>()),
    );
    expect(
      () => codec.encode(
        RemoteFrame(
          command: RemoteCommand.clientHello,
          flags: 0,
          requestId: 1,
          payload: Uint8List(RemoteLimits.preAuthFrameBytes + 1),
        ),
        phase: RemoteFramePhase.preAuth,
      ),
      throwsA(isA<RemoteException>()),
    );
  });

  test(
    'stream decoder handles chunks and rejects oversized declared lengths',
    () {
      const codec = RemoteFrameCodec();
      final first = codec.encode(
        const RemoteFrame(
          command: RemoteCommand.ping,
          flags: 0,
          requestId: 4,
          payload: <int>[9],
        ),
      );
      final second = codec.encode(
        const RemoteFrame(
          command: RemoteCommand.pong,
          flags: 0,
          requestId: 5,
          payload: <int>[8, 7],
        ),
      );
      final decoder = RemoteFrameDecoder();
      expect(decoder.add(first.sublist(0, 5)), isEmpty);
      expect(decoder.add(<int>[...first.sublist(5), ...second]), hasLength(2));
      decoder.requireDone();

      final oversized = Uint8List(RemoteFrameCodec.headerLength);
      oversized[4] = 0x00;
      oversized[5] = 0x10;
      oversized[6] = 0x00;
      oversized[7] = 0x01;
      expect(
        () => RemoteFrameDecoder().add(oversized),
        throwsA(isA<RemoteException>()),
      );
    },
  );

  test('stream decoder enforces the total buffered-byte bound', () {
    final chunk = Uint8List(RemoteLimits.maxBufferedBytesPerSession + 1);
    expect(
      () => RemoteFrameDecoder().add(chunk),
      throwsA(
        isA<RemoteException>().having(
          (error) => error.code,
          'code',
          RemoteFailureCode.frameTooLarge,
        ),
      ),
    );
  });

  test('protocol state machine rejects commands before mutual auth', () {
    final server = RemoteProtocolSession(isServer: true);
    server.accept(
      const RemoteFrame(
        command: RemoteCommand.clientHello,
        flags: 0,
        requestId: 1,
        payload: <int>[],
      ),
    );
    expect(server.state, RemoteProtocolState.awaitingClientAuthentication);
    expect(
      () => server.accept(
        const RemoteFrame(
          command: RemoteCommand.openResource,
          flags: 0,
          requestId: 2,
          payload: <int>[],
        ),
      ),
      throwsA(isA<RemoteException>()),
    );
    expect(server.state, RemoteProtocolState.failed);

    final client = RemoteProtocolSession(isServer: false);
    client.accept(
      const RemoteFrame(
        command: RemoteCommand.serverHello,
        flags: 0,
        requestId: 1,
        payload: <int>[],
      ),
    );
    client.accept(
      const RemoteFrame(
        command: RemoteCommand.authenticated,
        flags: 0,
        requestId: 2,
        payload: <int>[],
      ),
    );
    expect(client.state, RemoteProtocolState.authenticated);
    client.accept(
      const RemoteFrame(
        command: RemoteCommand.resourceOpened,
        flags: 0,
        requestId: 3,
        payload: <int>[],
      ),
    );
    expect(client.applicationRequests, 0);
  });

  test('opaque range codec is overflow-safe and EOF is explicit', () {
    const payloadCodec = RemoteProtocolPayloadCodec();
    final resource = RemoteResourceId(<int>[1, 2, 3]);
    final range = const RemoteByteRange(offset: 10, length: 25);
    final decoded = payloadCodec.decodeReadResource(
      payloadCodec.encodeReadResource(resource, range),
    );
    expect(decoded.resourceId.bytes, <int>[1, 2, 3]);
    expect(decoded.range.offset, 10);
    expect(
      () => const RemoteByteRange(
        offset: 100,
        length: 1,
      ).validate(resourceLength: 100),
      throwsA(isA<RemoteException>()),
    );
    expect(
      () => const RemoteByteRange(
        offset: 0,
        length: RemoteLimits.maxReadBytes + 1,
      ).validate(resourceLength: 10),
      throwsA(isA<RemoteException>()),
    );
    final chunk = payloadCodec.decodeResourceChunk(
      payloadCodec.encodeResourceChunk(
        RemoteReadResult(offset: 35, bytes: <int>[], eof: true),
      ),
    );
    expect(chunk.eof, isTrue);
    expect(chunk.bytes, isEmpty);
  });
}
