import 'dart:async';
import 'dart:typed_data';

import 'package:avaca_protocol/avaca_protocol.dart';
import 'package:avaca_remote_core/avaca_remote_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'v2 client/server handshake and concurrent requests stay framed',
    () async {
      final pair = _MemoryConnectionPair();
      final secret = Uint8List.fromList(
        List<int>.generate(32, (index) => (index * 17) & 0xff),
      );
      final serverFuture = AvacaApplicationSession.authenticateServer(
        pair.server,
        serverId: 'server-1',
        expectedClientId: 'client-1',
        pairingSecret: secret,
      );
      final clientFuture = AvacaApplicationSession.authenticateClient(
        pair.client,
        clientId: 'client-1',
        expectedServerId: 'server-1',
        pairingSecret: secret,
      );
      final server = await serverFuture;
      final client = await clientFuture;
      final serve = server.serve((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        expect(request.opcode, AvacaOpcode.ping);
        return AvacaFrame(
          opcode: AvacaOpcode.pong,
          requestId: request.requestId,
          payload: Uint8List(0),
        );
      });

      final responses = await Future.wait(
        List<Future<AvacaFrame>>.generate(
          8,
          (_) => client.request(
            AvacaOpcode.ping,
            Uint8List(0),
            expectedResponses: const <AvacaOpcode>{AvacaOpcode.pong},
          ),
        ),
      );
      expect(responses, hasLength(8));
      expect(
        responses.every((frame) => frame.opcode == AvacaOpcode.pong),
        isTrue,
      );

      await client.close();
      await server.close();
      await serve;
    },
  );

  test('wrong pairing secret fails closed without exposing details', () async {
    final pair = _MemoryConnectionPair();
    final server = AvacaApplicationSession.authenticateServer(
      pair.server,
      serverId: 'server-1',
      pairingSecret: Uint8List.fromList(List<int>.filled(32, 1)),
    );
    final client = AvacaApplicationSession.authenticateClient(
      pair.client,
      clientId: 'client-1',
      expectedServerId: 'server-1',
      pairingSecret: Uint8List.fromList(List<int>.filled(32, 2)),
    );
    await expectLater(
      Future.wait<Object>([server, client]),
      throwsA(isA<AvacaRemoteException>()),
    );
    expect(pair.client.isOpen, isFalse);
    expect(pair.server.isOpen, isFalse);
  });

  test('a timed-out request does not poison the following response', () async {
    final pair = _MemoryConnectionPair();
    final secret = Uint8List.fromList(List<int>.filled(32, 9));
    final serverFuture = AvacaApplicationSession.authenticateServer(
      pair.server,
      serverId: 'server-1',
      pairingSecret: secret,
    );
    final clientFuture = AvacaApplicationSession.authenticateClient(
      pair.client,
      clientId: 'client-1',
      expectedServerId: 'server-1',
      pairingSecret: secret,
    );
    final server = await serverFuture;
    final client = await clientFuture;
    final serve = server.serve((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return AvacaFrame(
        opcode: AvacaOpcode.pong,
        requestId: request.requestId,
        payload: Uint8List(0),
      );
    });

    await expectLater(
      client.request(
        AvacaOpcode.ping,
        Uint8List(0),
        expectedResponses: const <AvacaOpcode>{AvacaOpcode.pong},
        timeout: const Duration(milliseconds: 5),
      ),
      throwsA(
        isA<AvacaRemoteException>().having(
          (error) => error.code,
          'code',
          AvacaRemoteFailureCode.timeout,
        ),
      ),
    );
    final response = await client.request(
      AvacaOpcode.ping,
      Uint8List(0),
      expectedResponses: const <AvacaOpcode>{AvacaOpcode.pong},
    );
    expect(response.opcode, AvacaOpcode.pong);
    await client.close();
    await server.close();
    await serve;
  });
}

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
      Uint8List.fromList(List<int>.filled(32, 7));

  @override
  Future<void> write(Uint8List bytes) async {
    if (!_open || !_peer!._open) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'memory connection is closed',
      );
    }
    _peer!._incoming.add(Uint8List.fromList(bytes));
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
