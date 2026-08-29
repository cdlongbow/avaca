import 'dart:async';
import 'dart:io';

import 'package:avaca/remote/remote.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/remote_fakes.dart';

class FailingDeleteRemoteSecretStore extends MemoryRemoteSecretStore {
  @override
  Future<void> delete(String key) async {
    deleteCount++;
    throw StateError('simulated protected-secret deletion failure');
  }
}

class BlockingEndpointCandidateProvider implements EndpointCandidateProvider {
  BlockingEndpointCandidateProvider(this.endpoint);

  final RemoteEndpoint endpoint;
  bool blockNext = false;
  int calls = 0;
  Completer<void> started = Completer<void>();
  Completer<void> release = Completer<void>();

  @override
  Future<List<RemoteEndpoint>> getCandidates() async {
    calls++;
    if (blockNext) {
      blockNext = false;
      started.complete();
      await release.future;
    }
    return <RemoteEndpoint>[endpoint];
  }
}

void main() {
  test(
    'Remote OFF performs no listener, discovery, endpoint, or secret work',
    () async {
      final state = InMemoryRemoteStateStore();
      final secrets = MemoryRemoteSecretStore();
      final clock = FixedRemoteClock();
      final identity = RemoteIdentityManager(
        stateStore: state,
        secretStore: secrets,
        crypto: RemoteCrypto(random: FixedRemoteRandom()),
        clock: clock,
      );
      final pairing = RemotePairingManager(
        stateStore: state,
        secretStore: secrets,
        identityManager: identity,
        clock: clock,
        random: FixedRemoteRandom(100),
      );
      final endpoints = FakeEndpointCandidateProvider(<RemoteEndpoint>[]);
      final discovery = FakeRemoteDiscovery();
      final transport = FakeRemoteTransport();
      final coordinator = RemoteServiceCoordinator(
        stateStore: state,
        secretStore: secrets,
        identityManager: identity,
        pairingManager: pairing,
        discovery: discovery,
        endpointProvider: endpoints,
        transport: transport,
      );

      await coordinator.startIfEnabled();
      expect(coordinator.state, RemoteConnectivityState.disabled);
      expect(endpoints.calls, 0);
      expect(secrets.readCount, 0);
      expect(discovery.published, isEmpty);
      expect(transport.listenCount, 0);
      await coordinator.dispose();
      expect(discovery.closeCount, 0);
      expect(transport.closeCount, 0);
    },
  );

  test(
    'endpoint A to B increments sequence before publish and survives restart',
    () async {
      final state = InMemoryRemoteStateStore();
      final secrets = MemoryRemoteSecretStore();
      final clock = FixedRemoteClock(DateTime.utc(2026, 1, 1));
      final identity = RemoteIdentityManager(
        stateStore: state,
        secretStore: secrets,
        crypto: RemoteCrypto(random: FixedRemoteRandom(1)),
        clock: clock,
      );
      final pairing = RemotePairingManager(
        stateStore: state,
        secretStore: secrets,
        identityManager: identity,
        clock: clock,
        random: FixedRemoteRandom(20),
      );
      final peerState = InMemoryRemoteStateStore();
      final peerSecrets = MemoryRemoteSecretStore();
      final peerIdentity = RemoteIdentityManager(
        stateStore: peerState,
        secretStore: peerSecrets,
        crypto: RemoteCrypto(random: FixedRemoteRandom(80)),
        clock: clock,
      );
      final peer = await peerIdentity.loadOrCreate();
      final invitation = await pairing.beginPairing();
      await pairing.completePairing(
        sessionId: invitation.sessionId,
        pairingSecret: invitation.pairingSecret,
        peerDeviceId: peer.deviceId,
        peerPublicKey: peer.publicKeyBytes,
      );

      final endpointA = RemoteEndpoint(
        host: '192.168.1.10',
        port: 4587,
        kind: RemoteEndpointKind.lanIpv4,
      );
      final endpointB = RemoteEndpoint(
        host: '192.168.1.11',
        port: 4587,
        kind: RemoteEndpointKind.lanIpv4,
      );
      final provider = FakeEndpointCandidateProvider(<RemoteEndpoint>[
        endpointA,
      ]);
      final discovery = FakeRemoteDiscovery();
      final transport = FakeRemoteTransport();
      final coordinator = RemoteServiceCoordinator(
        stateStore: state,
        secretStore: secrets,
        identityManager: identity,
        pairingManager: pairing,
        discovery: discovery,
        endpointProvider: provider,
        transport: transport,
        clock: clock,
      );
      await coordinator.setEnabled(true);
      expect(coordinator.state, RemoteConnectivityState.online);
      expect((await state.load()).publicationSequence, 1);
      expect(discovery.published, hasLength(1));

      provider.candidates = <RemoteEndpoint>[endpointB];
      await coordinator.refreshEndpoints();
      expect((await state.load()).publicationSequence, 2);
      expect(discovery.published, hasLength(2));
      await coordinator.stop();

      final identityAfterRestart = RemoteIdentityManager(
        stateStore: state,
        secretStore: secrets,
        crypto: RemoteCrypto(random: FixedRemoteRandom(200)),
        clock: clock,
      );
      final pairingAfterRestart = RemotePairingManager(
        stateStore: state,
        secretStore: secrets,
        identityManager: identityAfterRestart,
        clock: clock,
        random: FixedRemoteRandom(220),
      );
      final persistedIdentity = await identityAfterRestart.loadOrCreate();
      expect(
        persistedIdentity.deviceId,
        (await identity.loadOrCreate()).deviceId,
      );
      expect(
        (await pairingAfterRestart.findPeer(peer.deviceId))?.revoked,
        isFalse,
      );
      final restartDiscovery = FakeRemoteDiscovery();
      final restartTransport = FakeRemoteTransport();
      final restarted = RemoteServiceCoordinator(
        stateStore: state,
        secretStore: secrets,
        identityManager: identityAfterRestart,
        pairingManager: pairingAfterRestart,
        discovery: restartDiscovery,
        endpointProvider: FakeEndpointCandidateProvider(<RemoteEndpoint>[
          endpointB,
        ]),
        transport: restartTransport,
        clock: clock,
      );
      await restarted.startIfEnabled();
      expect(restarted.state, RemoteConnectivityState.online);
      expect((await state.load()).publicationSequence, 3);
      expect(restartDiscovery.published, hasLength(1));
      await restarted.dispose();
      await coordinator.dispose();
    },
  );

  test(
    'production composition starts disabled and has no non-Windows insecure fallback',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca-remote-coordinator-',
      );
      try {
        final coordinator = RemoteServiceCoordinator.forApp(baseDir: root.path);
        await coordinator.startIfEnabled();
        expect(coordinator.state, RemoteConnectivityState.disabled);
        await coordinator.dispose();
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'revoke closes sessions even when protected-secret deletion fails',
    () async {
      final clock = FixedRemoteClock();
      final state = InMemoryRemoteStateStore();
      final secrets = FailingDeleteRemoteSecretStore();
      final identity = RemoteIdentityManager(
        stateStore: state,
        secretStore: secrets,
        crypto: RemoteCrypto(random: FixedRemoteRandom(1)),
        clock: clock,
      );
      final pairing = RemotePairingManager(
        stateStore: state,
        secretStore: secrets,
        identityManager: identity,
        clock: clock,
        random: FixedRemoteRandom(20),
      );
      final peerState = InMemoryRemoteStateStore();
      final peerSecrets = MemoryRemoteSecretStore();
      final peerIdentity = RemoteIdentityManager(
        stateStore: peerState,
        secretStore: peerSecrets,
        crypto: RemoteCrypto(random: FixedRemoteRandom(80)),
        clock: clock,
      );
      final peer = await peerIdentity.loadOrCreate();
      final invitation = await pairing.beginPairing();
      await pairing.completePairing(
        sessionId: invitation.sessionId,
        pairingSecret: invitation.pairingSecret,
        peerDeviceId: peer.deviceId,
        peerPublicKey: peer.publicKeyBytes,
      );

      var closed = false;
      final sessions = InMemoryRemoteSessionRegistry();
      sessions.register(peer.deviceId, () async => closed = true);
      final coordinator = RemoteServiceCoordinator(
        stateStore: state,
        secretStore: secrets,
        identityManager: identity,
        pairingManager: pairing,
        discovery: FakeRemoteDiscovery(),
        endpointProvider: FakeEndpointCandidateProvider(<RemoteEndpoint>[]),
        transport: FakeRemoteTransport(),
        sessions: sessions,
        clock: clock,
      );

      await expectLater(
        coordinator.revokePeer(peer.deviceId),
        throwsA(isA<StateError>()),
      );
      expect(closed, isTrue);
      expect((await state.load()).pairedDevices.single.revoked, isTrue);
      await coordinator.dispose();
    },
  );

  test(
    'enable changes wait behind an in-flight endpoint publication',
    () async {
      final clock = FixedRemoteClock();
      final state = InMemoryRemoteStateStore(
        const RemoteState(remoteEnabled: true),
      );
      final secrets = MemoryRemoteSecretStore();
      final identity = RemoteIdentityManager(
        stateStore: state,
        secretStore: secrets,
        crypto: RemoteCrypto(random: FixedRemoteRandom(1)),
        clock: clock,
      );
      final pairing = RemotePairingManager(
        stateStore: state,
        secretStore: secrets,
        identityManager: identity,
        clock: clock,
        random: FixedRemoteRandom(20),
      );
      final provider = BlockingEndpointCandidateProvider(
        RemoteEndpoint(
          host: '192.168.1.10',
          port: 4587,
          kind: RemoteEndpointKind.lanIpv4,
        ),
      );
      final coordinator = RemoteServiceCoordinator(
        stateStore: state,
        secretStore: secrets,
        identityManager: identity,
        pairingManager: pairing,
        discovery: FakeRemoteDiscovery(),
        endpointProvider: provider,
        transport: FakeRemoteTransport(),
        clock: clock,
      );

      await coordinator.startIfEnabled();
      provider.blockNext = true;
      final refresh = coordinator.refreshEndpoints();
      await provider.started.future;
      final disable = coordinator.setEnabled(false);
      await Future<void>.delayed(Duration.zero);
      expect((await state.load()).remoteEnabled, isTrue);

      provider.release.complete();
      await Future.wait(<Future<void>>[refresh, disable]);
      expect((await state.load()).remoteEnabled, isFalse);
      expect(coordinator.state, RemoteConnectivityState.disabled);
      expect(coordinator.isStarted, isFalse);
      await coordinator.dispose();
    },
  );
}
