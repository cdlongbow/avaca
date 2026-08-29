import 'dart:async';
import 'dart:typed_data';

import 'package:avaca/remote/remote.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/remote_fakes.dart';

class _SessionFixture {
  _SessionFixture({
    required this.serverIdentity,
    required this.serverPairing,
    required this.clientIdentity,
    required this.clientPairing,
    required this.serverAuthenticator,
    required this.clientAuthenticator,
  });

  final RemoteIdentityManager serverIdentity;
  final RemotePairingManager serverPairing;
  final RemoteIdentityManager clientIdentity;
  final RemotePairingManager clientPairing;
  final RemoteSessionAuthenticator serverAuthenticator;
  final RemoteSessionAuthenticator clientAuthenticator;
}

class _ReconnectTransport implements RemoteTransport {
  _ReconnectTransport(this.serverAuthenticator);

  final RemoteSessionAuthenticator serverAuthenticator;
  int connectCount = 0;
  Future<RemoteAuthenticatedSession>? serverSession;

  @override
  Future<RemoteConnection> connect(
    RemoteEndpoint endpoint, {
    Duration timeout = RemoteLimits.connectionTimeout,
  }) async {
    connectCount++;
    final pair = linkedRemoteConnectionPair();
    serverSession = serverAuthenticator.authenticateServer(pair.server);
    return pair.client;
  }

  @override
  Future<RemoteListener> listen(RemoteConnectionHandler onConnection) {
    throw UnimplementedError();
  }

  @override
  Future<void> close() async {}
}

class _BlockingRevokePairingManager extends RemotePairingManager {
  _BlockingRevokePairingManager({
    required super.stateStore,
    required super.secretStore,
    required super.identityManager,
    required super.clock,
    required super.random,
  });

  final Completer<void> revokeStarted = Completer<void>();
  final Completer<void> releaseRevoke = Completer<void>();

  @override
  Future<void> revoke(String deviceId) async {
    if (!revokeStarted.isCompleted) {
      revokeStarted.complete();
    }
    await releaseRevoke.future;
    return super.revoke(deviceId);
  }
}

class _BlockingServerAuthenticator extends RemoteSessionAuthenticator {
  _BlockingServerAuthenticator({
    required super.identityManager,
    required super.pairingManager,
  });

  final Completer<void> authenticationStarted = Completer<void>();
  final Completer<void> releaseAuthentication = Completer<void>();

  @override
  Future<RemoteAuthenticatedSession> authenticateServer(
    RemoteConnection connection, {
    String source = 'unknown',
  }) async {
    if (!authenticationStarted.isCompleted) {
      authenticationStarted.complete();
    }
    await releaseAuthentication.future;
    throw const RemoteException(
      RemoteFailureCode.timeout,
      'stalled authentication released by test',
    );
  }
}

Future<_SessionFixture> _createFixture() async {
  final clock = FixedRemoteClock();
  final serverState = InMemoryRemoteStateStore();
  final serverSecrets = MemoryRemoteSecretStore();
  final serverIdentity = RemoteIdentityManager(
    stateStore: serverState,
    secretStore: serverSecrets,
    crypto: RemoteCrypto(random: FixedRemoteRandom(1)),
    clock: clock,
  );
  final serverPairing = RemotePairingManager(
    stateStore: serverState,
    secretStore: serverSecrets,
    identityManager: serverIdentity,
    clock: clock,
    random: FixedRemoteRandom(50),
  );

  final clientState = InMemoryRemoteStateStore();
  final clientSecrets = MemoryRemoteSecretStore();
  final clientIdentity = RemoteIdentityManager(
    stateStore: clientState,
    secretStore: clientSecrets,
    crypto: RemoteCrypto(random: FixedRemoteRandom(90)),
    clock: clock,
  );
  final clientPairing = RemotePairingManager(
    stateStore: clientState,
    secretStore: clientSecrets,
    identityManager: clientIdentity,
    clock: clock,
    random: FixedRemoteRandom(50),
  );

  final serverRecord = await serverIdentity.loadOrCreate();
  final clientRecord = await clientIdentity.loadOrCreate();
  final serverInvitation = await serverPairing.beginPairing();
  final clientInvitation = await clientPairing.beginPairing();
  expect(clientInvitation.pairingSecret, serverInvitation.pairingSecret);
  await serverPairing.completePairing(
    sessionId: serverInvitation.sessionId,
    pairingSecret: serverInvitation.pairingSecret,
    peerDeviceId: clientRecord.deviceId,
    peerPublicKey: clientRecord.publicKeyBytes,
  );
  await clientPairing.completePairing(
    sessionId: clientInvitation.sessionId,
    pairingSecret: clientInvitation.pairingSecret,
    peerDeviceId: serverRecord.deviceId,
    peerPublicKey: serverRecord.publicKeyBytes,
  );

  final serverAuth = RemoteAuthenticator(
    localIdentity: serverIdentity,
    resolvePeer: serverPairing.findPeer,
    crypto: serverIdentity.crypto,
    clock: clock,
    random: FixedRemoteRandom(180),
  );
  final clientAuth = RemoteAuthenticator(
    localIdentity: clientIdentity,
    resolvePeer: clientPairing.findPeer,
    crypto: clientIdentity.crypto,
    clock: clock,
    random: FixedRemoteRandom(220),
  );
  return _SessionFixture(
    serverIdentity: serverIdentity,
    serverPairing: serverPairing,
    clientIdentity: clientIdentity,
    clientPairing: clientPairing,
    serverAuthenticator: RemoteSessionAuthenticator(
      identityManager: serverIdentity,
      pairingManager: serverPairing,
      authenticator: serverAuth,
      preAuthGate: RemotePreAuthGate(
        crypto: serverIdentity.crypto,
        clock: clock,
      ),
    ),
    clientAuthenticator: RemoteSessionAuthenticator(
      identityManager: clientIdentity,
      pairingManager: clientPairing,
      authenticator: clientAuth,
      preAuthGate: RemotePreAuthGate(
        crypto: clientIdentity.crypto,
        clock: clock,
      ),
    ),
  );
}

void main() {
  test(
    'mutual session authentication binds pairing to the transport',
    () async {
      final fixture = await _createFixture();
      final pair = linkedRemoteConnectionPair();
      final serverFuture = fixture.serverAuthenticator.authenticateServer(
        pair.server,
      );
      final clientFuture = fixture.clientAuthenticator.authenticateClient(
        pair.client,
        serverDeviceId: (await fixture.serverIdentity.loadOrCreate()).deviceId,
      );
      final sessions = await Future.wait(<Future<RemoteAuthenticatedSession>>[
        serverFuture,
        clientFuture,
      ]);
      final serverSession = sessions[0];
      final clientSession = sessions[1];

      expect(serverSession.role, RemoteSessionRole.server);
      expect(clientSession.role, RemoteSessionRole.client);
      expect(
        serverSession.peerDeviceId,
        (await fixture.clientIdentity.loadOrCreate()).deviceId,
      );
      expect(
        clientSession.peerDeviceId,
        (await fixture.serverIdentity.loadOrCreate()).deviceId,
      );
      expect(serverSession.protocol.state, RemoteProtocolState.authenticated);
      expect(clientSession.protocol.state, RemoteProtocolState.authenticated);

      const codec = RemoteFrameCodec();
      final first = codec.encode(
        const RemoteFrame(
          command: RemoteCommand.ping,
          flags: 0,
          requestId: 10,
          payload: <int>[1],
        ),
      );
      final second = codec.encode(
        const RemoteFrame(
          command: RemoteCommand.ping,
          flags: 0,
          requestId: 11,
          payload: <int>[2],
        ),
      );
      await clientSession.connection.write(
        Uint8List.fromList(<int>[...first, ...second]),
      );
      expect((await serverSession.readFrame()).requestId, 10);
      expect((await serverSession.readFrame()).requestId, 11);

      await serverSession.close();
      await clientSession.close();
    },
  );

  test(
    'a different channel binding fails before the server challenge',
    () async {
      final fixture = await _createFixture();
      final pair = linkedRemoteConnectionPair(
        clientChannelBinding: List<int>.filled(
          RemoteLimits.channelBindingBytes,
          0x5a,
        ),
        serverChannelBinding: List<int>.filled(
          RemoteLimits.channelBindingBytes,
          0x6b,
        ),
      );
      final serverFuture = fixture.serverAuthenticator.authenticateServer(
        pair.server,
      );
      final clientFuture = fixture.clientAuthenticator.authenticateClient(
        pair.client,
        serverDeviceId: (await fixture.serverIdentity.loadOrCreate()).deviceId,
      );

      await expectLater(
        Future.wait(<Future<RemoteAuthenticatedSession>>[
          serverFuture,
          clientFuture,
        ]),
        throwsA(
          isA<RemoteException>().having(
            (error) => error.code,
            'code',
            anyOf(
              RemoteFailureCode.authenticationFailed,
              RemoteFailureCode.connectionFailed,
            ),
          ),
        ),
      );
    },
  );

  test(
    'authenticated reconnect runs the handshake on every new connection',
    () async {
      final fixture = await _createFixture();
      final transport = _ReconnectTransport(fixture.serverAuthenticator);
      final controller = RemoteAuthenticatedReconnectController(
        endpointProvider: FakeEndpointCandidateProvider(<RemoteEndpoint>[
          RemoteEndpoint(
            host: '192.168.1.21',
            port: 4587,
            kind: RemoteEndpointKind.lanIpv4,
          ),
        ]),
        transport: transport,
        sessionAuthenticator: fixture.clientAuthenticator,
      );

      final serverRecord = await fixture.serverIdentity.loadOrCreate();
      final clientSession = await controller.reconnect(
        serverDeviceId: serverRecord.deviceId,
      );
      expect(transport.connectCount, 1);
      expect(clientSession.role, RemoteSessionRole.client);
      final serverSession = await transport.serverSession!;
      expect(
        serverSession.peerDeviceId,
        (await fixture.clientIdentity.loadOrCreate()).deviceId,
      );

      await clientSession.close();
      await serverSession.close();
    },
  );

  test('auth payload codec round-trips bounded handshake records', () {
    const codec = RemoteAuthPayloadCodec();
    final proof = RemotePreAuthProof(
      timestampMs: 123,
      nonce: Uint8List.fromList(List<int>.generate(32, (index) => index)),
      mac: Uint8List.fromList(List<int>.filled(32, 0x77)),
    );
    final hello = codec.decodeClientHello(
      codec.encodeClientHello(peerDeviceId: 'peer-1', proof: proof),
    );
    expect(hello.peerDeviceId, 'peer-1');
    expect(hello.proof.timestampMs, 123);
    expect(hello.proof.mac, proof.mac);

    final challenge = RemoteAuthChallenge(
      sessionId: 'session-1',
      peerDeviceId: 'peer-1',
      serverNonce: List<int>.filled(32, 0x11),
      serverPublicKey: List<int>.filled(32, 0x22),
      issuedAt: DateTime.utc(2026, 1, 1),
      expiresAt: DateTime.utc(2026, 1, 1, 0, 0, 5),
    );
    final decodedChallenge = codec.decodeServerHello(
      codec.encodeServerHello(challenge),
    );
    expect(decodedChallenge.sessionId, challenge.sessionId);
    expect(decodedChallenge.serverPublicKey, challenge.serverPublicKey);

    final response = RemoteAuthResponse(
      peerDeviceId: 'peer-1',
      peerPublicKey: List<int>.filled(32, 0x33),
      clientNonce: List<int>.filled(32, 0x44),
      signature: List<int>.filled(64, 0x55),
    );
    final decodedResponse = codec.decodeAuthenticate(
      codec.encodeAuthenticate(response),
    );
    expect(decodedResponse.peerDeviceId, response.peerDeviceId);
    expect(decodedResponse.signature, response.signature);

    final acceptance = RemoteAuthAcceptance(
      sessionId: 'session-1',
      signature: List<int>.filled(64, 0x66),
    );
    final decodedAcceptance = codec.decodeAuthenticated(
      codec.encodeAuthenticated(acceptance),
    );
    expect(decodedAcceptance.sessionId, acceptance.sessionId);
    expect(decodedAcceptance.signature, acceptance.signature);
  });

  test(
    'coordinator authenticates and tracks incoming sessions when injected',
    () async {
      final fixture = await _createFixture();
      final serverRecord = await fixture.serverIdentity.loadOrCreate();
      final clientRecord = await fixture.clientIdentity.loadOrCreate();
      final state =
          fixture.serverPairing.stateStore as InMemoryRemoteStateStore;
      final transport = FakeRemoteTransport();
      final handledPeer = Completer<String>();
      final coordinator = RemoteServiceCoordinator(
        stateStore: state,
        secretStore: fixture.serverPairing.secretStore,
        identityManager: fixture.serverIdentity,
        pairingManager: fixture.serverPairing,
        discovery: FakeRemoteDiscovery(),
        endpointProvider: FakeEndpointCandidateProvider(<RemoteEndpoint>[
          RemoteEndpoint(
            host: '192.168.1.20',
            port: 4587,
            kind: RemoteEndpointKind.lanIpv4,
          ),
        ]),
        transport: transport,
        sessionAuthenticator: fixture.serverAuthenticator,
        sessionHandler: (session) async {
          handledPeer.complete(session.peerDeviceId);
        },
      );
      await coordinator.setEnabled(true);
      final listener = transport.listener;
      expect(listener, isNotNull);

      final pair = linkedRemoteConnectionPair();
      final clientFuture = fixture.clientAuthenticator.authenticateClient(
        pair.client,
        serverDeviceId: serverRecord.deviceId,
      );
      final incomingFuture = listener!.accept(pair.server);
      final clientSession = await clientFuture;
      await incomingFuture;

      expect(await handledPeer.future, clientRecord.deviceId);
      expect(coordinator.sessions.activeCount, 0);
      await clientSession.close();
      await coordinator.dispose();
    },
  );

  test('incoming authentication is fenced by peer revocation', () async {
    final fixture = await _createFixture();
    final state = fixture.serverPairing.stateStore as InMemoryRemoteStateStore;
    final clock = FixedRemoteClock();
    final pairing = _BlockingRevokePairingManager(
      stateStore: state,
      secretStore: fixture.serverPairing.secretStore,
      identityManager: fixture.serverIdentity,
      clock: clock,
      random: FixedRemoteRandom(50),
    );
    final transport = FakeRemoteTransport();
    var handled = false;
    final coordinator = RemoteServiceCoordinator(
      stateStore: state,
      secretStore: fixture.serverPairing.secretStore,
      identityManager: fixture.serverIdentity,
      pairingManager: pairing,
      discovery: FakeRemoteDiscovery(),
      endpointProvider: FakeEndpointCandidateProvider(<RemoteEndpoint>[
        RemoteEndpoint(
          host: '192.168.1.20',
          port: 4587,
          kind: RemoteEndpointKind.lanIpv4,
        ),
      ]),
      transport: transport,
      sessionAuthenticator: fixture.serverAuthenticator,
      sessionHandler: (session) async {
        handled = true;
      },
    );
    await coordinator.setEnabled(true);
    final listener = transport.listener;
    expect(listener, isNotNull);

    final peerId = (await fixture.clientIdentity.loadOrCreate()).deviceId;
    final revokeFuture = coordinator.revokePeer(peerId);
    await pairing.revokeStarted.future;

    final pair = linkedRemoteConnectionPair();
    final clientAuthFuture = fixture.clientAuthenticator.authenticateClient(
      pair.client,
      serverDeviceId: (await fixture.serverIdentity.loadOrCreate()).deviceId,
    );
    final incomingFuture = listener!.accept(pair.server);
    await Future<void>.delayed(Duration.zero);
    expect(handled, isFalse);

    pairing.releaseRevoke.complete();
    await revokeFuture;
    await incomingFuture;
    final clientSession = await clientAuthFuture;

    expect(handled, isFalse);
    expect((await state.load()).pairedDevices.single.revoked, isTrue);
    expect(clientSession.isOpen, isFalse);
    await clientSession.close();
    await coordinator.dispose();
  });

  test(
    'stalled incoming authentication does not block coordinator operations',
    () async {
      final fixture = await _createFixture();
      final state =
          fixture.serverPairing.stateStore as InMemoryRemoteStateStore;
      final authenticator = _BlockingServerAuthenticator(
        identityManager: fixture.serverIdentity,
        pairingManager: fixture.serverPairing,
      );
      final transport = FakeRemoteTransport();
      final coordinator = RemoteServiceCoordinator(
        stateStore: state,
        secretStore: fixture.serverPairing.secretStore,
        identityManager: fixture.serverIdentity,
        pairingManager: fixture.serverPairing,
        discovery: FakeRemoteDiscovery(),
        endpointProvider: FakeEndpointCandidateProvider(<RemoteEndpoint>[
          RemoteEndpoint(
            host: '192.168.1.20',
            port: 4587,
            kind: RemoteEndpointKind.lanIpv4,
          ),
        ]),
        transport: transport,
        sessionAuthenticator: authenticator,
        sessionHandler: (session) async {},
      );
      await coordinator.setEnabled(true);
      final listener = transport.listener;
      expect(listener, isNotNull);

      final peerId = (await fixture.clientIdentity.loadOrCreate()).deviceId;
      final incomingPair = linkedRemoteConnectionPair();
      final incomingFuture = listener!.accept(incomingPair.server);
      await authenticator.authenticationStarted.future;

      await coordinator.revokePeer(peerId).timeout(const Duration(seconds: 1));
      expect((await state.load()).pairedDevices.single.revoked, isTrue);

      authenticator.releaseAuthentication.complete();
      await incomingFuture;
      await coordinator.dispose();
    },
  );

  test(
    'stalled authentication cannot hand off after disable completes',
    () async {
      final fixture = await _createFixture();
      final state =
          fixture.serverPairing.stateStore as InMemoryRemoteStateStore;
      final authenticator = _BlockingServerAuthenticator(
        identityManager: fixture.serverIdentity,
        pairingManager: fixture.serverPairing,
      );
      final transport = FakeRemoteTransport();
      var handled = false;
      final coordinator = RemoteServiceCoordinator(
        stateStore: state,
        secretStore: fixture.serverPairing.secretStore,
        identityManager: fixture.serverIdentity,
        pairingManager: fixture.serverPairing,
        discovery: FakeRemoteDiscovery(),
        endpointProvider: FakeEndpointCandidateProvider(<RemoteEndpoint>[
          RemoteEndpoint(
            host: '192.168.1.20',
            port: 4587,
            kind: RemoteEndpointKind.lanIpv4,
          ),
        ]),
        transport: transport,
        sessionAuthenticator: authenticator,
        sessionHandler: (session) async {
          handled = true;
        },
      );
      await coordinator.setEnabled(true);
      final listener = transport.listener;
      expect(listener, isNotNull);

      final incomingPair = linkedRemoteConnectionPair();
      final incomingFuture = listener!.accept(incomingPair.server);
      await authenticator.authenticationStarted.future;

      await coordinator.setEnabled(false).timeout(const Duration(seconds: 1));
      expect(coordinator.remoteEnabled, isFalse);
      expect(coordinator.isStarted, isFalse);

      authenticator.releaseAuthentication.complete();
      await incomingFuture;
      expect(handled, isFalse);
      await coordinator.dispose();
    },
  );
}
