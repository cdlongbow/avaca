import 'package:avaca/remote/remote.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/remote_fakes.dart';

void main() {
  test('abuse guard bounds global sessions and throttles a source', () {
    final guard = RemoteAbuseGuard();
    final now = DateTime.utc(2026, 1, 1);
    for (
      var index = 0;
      index < RemoteLimits.maxUnauthenticatedSessions;
      index++
    ) {
      expect(
        guard.tryAcquireUnauthenticated('source-$index', now: now),
        isTrue,
      );
    }
    expect(guard.tryAcquireUnauthenticated('overflow', now: now), isFalse);
    guard.releaseUnauthenticated();
    expect(guard.tryAcquireUnauthenticated('overflow', now: now), isTrue);
    for (
      var index = 0;
      index < RemoteLimits.maxAuthFailuresPerSource;
      index++
    ) {
      guard.recordAuthenticationFailure('bad-source', now: now);
    }
    expect(guard.isThrottled('bad-source', now: now), isTrue);
    expect(guard.tryAcquireUnauthenticated('bad-source', now: now), isFalse);
  });

  test(
    'pairing is one-time, protected, and revocation invalidates access',
    () async {
      final clock = FixedRemoteClock();
      final state = InMemoryRemoteStateStore();
      final secrets = MemoryRemoteSecretStore();
      final desktopIdentity = RemoteIdentityManager(
        stateStore: state,
        secretStore: secrets,
        crypto: RemoteCrypto(random: FixedRemoteRandom(1)),
        clock: clock,
      );
      final pairing = RemotePairingManager(
        stateStore: state,
        secretStore: secrets,
        identityManager: desktopIdentity,
        clock: clock,
        random: FixedRemoteRandom(80),
      );
      final peerState = InMemoryRemoteStateStore();
      final peerSecrets = MemoryRemoteSecretStore();
      final peerIdentity = RemoteIdentityManager(
        stateStore: peerState,
        secretStore: peerSecrets,
        crypto: RemoteCrypto(random: FixedRemoteRandom(140)),
        clock: clock,
      );
      final peer = await peerIdentity.loadOrCreate();

      final invitation = await pairing.beginPairing();
      final paired = await pairing.completePairing(
        sessionId: invitation.sessionId,
        pairingSecret: invitation.pairingSecret,
        peerDeviceId: peer.deviceId,
        peerPublicKey: peer.publicKeyBytes,
        label: 'test peer',
      );
      expect(paired.revoked, isFalse);
      expect((await pairing.readPairSecret(peer.deviceId)).length, 32);
      expect(secrets.values.keys.any((key) => key.contains('paired-')), isTrue);

      await expectLater(
        pairing.completePairing(
          sessionId: invitation.sessionId,
          pairingSecret: invitation.pairingSecret,
          peerDeviceId: 'another-peer',
          peerPublicKey: peer.publicKeyBytes,
        ),
        throwsA(isA<RemoteException>()),
      );

      await pairing.revoke(peer.deviceId);
      await expectLater(
        pairing.readPairSecret(peer.deviceId),
        throwsA(isA<RemoteException>()),
      );
      expect(secrets.deleteCount, greaterThanOrEqualTo(1));
    },
  );

  test(
    'pre-auth proof is pair-scoped, bounded, and replay resistant',
    () async {
      final clock = FixedRemoteClock();
      final crypto = RemoteCrypto(random: FixedRemoteRandom(3));
      final gate = RemotePreAuthGate(crypto: crypto, clock: clock);
      final key = List<int>.generate(32, (index) => index + 1);
      final context = 'session-context'.codeUnits;
      final proof = await gate.create(pairKey: key, context: context);
      await gate.verify(pairKey: key, context: context, proof: proof);
      await expectLater(
        gate.verify(pairKey: key, context: context, proof: proof),
        throwsA(isA<RemoteException>()),
      );
      await expectLater(
        gate.verify(
          pairKey: List<int>.filled(32, 99),
          context: context,
          proof: proof,
        ),
        throwsA(isA<RemoteException>()),
      );
    },
  );

  test(
    'pre-auth replay entries remain protected while still unexpired',
    () async {
      final clock = FixedRemoteClock();
      final gate = RemotePreAuthGate(
        crypto: RemoteCrypto(random: FixedRemoteRandom(3)),
        clock: clock,
      );
      final key = List<int>.filled(32, 7);
      final context = 'bounded-replay-context'.codeUnits;
      final proofs = <RemotePreAuthProof>[];
      final baseTime = clock.current;

      for (var index = 0; index < RemoteLimits.maxReplayEntries; index++) {
        clock.current = baseTime.add(Duration(milliseconds: index));
        final proof = await gate.create(pairKey: key, context: context);
        proofs.add(proof);
        await gate.verify(pairKey: key, context: context, proof: proof);
      }

      await expectLater(
        gate.verify(pairKey: key, context: context, proof: proofs.first),
        throwsA(
          isA<RemoteException>().having(
            (error) => error.code,
            'code',
            RemoteFailureCode.replayDetected,
          ),
        ),
      );

      clock.current = clock.now.add(
        RemoteLimits.preAuthClockSkew + const Duration(seconds: 1),
      );
      final afterExpiry = await gate.create(pairKey: key, context: context);
      await gate.verify(pairKey: key, context: context, proof: afterExpiry);
    },
  );

  test(
    'mutual auth verifies fresh transcript signatures and rejects replay',
    () async {
      final clock = FixedRemoteClock();
      final desktopState = InMemoryRemoteStateStore();
      final desktopSecrets = MemoryRemoteSecretStore();
      final desktopIdentity = RemoteIdentityManager(
        stateStore: desktopState,
        secretStore: desktopSecrets,
        crypto: RemoteCrypto(random: FixedRemoteRandom(10)),
        clock: clock,
      );
      final pairing = RemotePairingManager(
        stateStore: desktopState,
        secretStore: desktopSecrets,
        identityManager: desktopIdentity,
        clock: clock,
        random: FixedRemoteRandom(50),
      );
      final peerState = InMemoryRemoteStateStore();
      final peerSecrets = MemoryRemoteSecretStore();
      final peerIdentityManager = RemoteIdentityManager(
        stateStore: peerState,
        secretStore: peerSecrets,
        crypto: RemoteCrypto(random: FixedRemoteRandom(90)),
        clock: clock,
      );
      final peerIdentity = await peerIdentityManager.loadOrCreate();
      final invitation = await pairing.beginPairing();
      await pairing.completePairing(
        sessionId: invitation.sessionId,
        pairingSecret: invitation.pairingSecret,
        peerDeviceId: peerIdentity.deviceId,
        peerPublicKey: peerIdentity.publicKeyBytes,
      );

      final auth = RemoteAuthenticator(
        localIdentity: desktopIdentity,
        resolvePeer: pairing.findPeer,
        crypto: RemoteCrypto(random: FixedRemoteRandom(180)),
        clock: clock,
        random: FixedRemoteRandom(200),
      );
      final challenge = await auth.issueChallenge(
        peerDeviceId: peerIdentity.deviceId,
      );
      final channelBinding = List<int>.filled(
        RemoteLimits.channelBindingBytes,
        0x5a,
      );
      final mismatchChallenge = await auth.issueChallenge(
        peerDeviceId: peerIdentity.deviceId,
      );
      final mismatchResponse = await auth.createResponse(
        challenge: mismatchChallenge,
        peerIdentity: peerIdentity,
        channelBinding: channelBinding,
      );
      await expectLater(
        auth.verifyResponse(
          challenge: mismatchChallenge,
          response: mismatchResponse,
          channelBinding: List<int>.filled(
            RemoteLimits.channelBindingBytes,
            0x6b,
          ),
        ),
        throwsA(
          isA<RemoteException>().having(
            (error) => error.code,
            'code',
            RemoteFailureCode.authenticationFailed,
          ),
        ),
      );
      final response = await auth.createResponse(
        challenge: challenge,
        peerIdentity: peerIdentity,
        channelBinding: channelBinding,
      );
      await auth.verifyResponse(
        challenge: challenge,
        response: response,
        channelBinding: channelBinding,
      );
      final acceptance = await auth.createAcceptance(
        challenge: challenge,
        response: response,
        channelBinding: channelBinding,
      );
      expect(
        await auth.verifyAcceptance(
          challenge: challenge,
          response: response,
          acceptance: acceptance,
          expectedServerPublicKey: challenge.serverPublicKey,
          channelBinding: channelBinding,
        ),
        isTrue,
      );
      await expectLater(
        auth.verifyResponse(
          challenge: challenge,
          response: response,
          channelBinding: channelBinding,
        ),
        throwsA(isA<RemoteException>()),
      );
    },
  );

  test('authentication rejects a caller-modified challenge expiry', () async {
    final clock = FixedRemoteClock();
    final desktopState = InMemoryRemoteStateStore();
    final desktopSecrets = MemoryRemoteSecretStore();
    final desktopIdentity = RemoteIdentityManager(
      stateStore: desktopState,
      secretStore: desktopSecrets,
      crypto: RemoteCrypto(random: FixedRemoteRandom(10)),
      clock: clock,
    );
    final pairing = RemotePairingManager(
      stateStore: desktopState,
      secretStore: desktopSecrets,
      identityManager: desktopIdentity,
      clock: clock,
      random: FixedRemoteRandom(50),
    );
    final peerState = InMemoryRemoteStateStore();
    final peerSecrets = MemoryRemoteSecretStore();
    final peerIdentityManager = RemoteIdentityManager(
      stateStore: peerState,
      secretStore: peerSecrets,
      crypto: RemoteCrypto(random: FixedRemoteRandom(90)),
      clock: clock,
    );
    final peerIdentity = await peerIdentityManager.loadOrCreate();
    final invitation = await pairing.beginPairing();
    await pairing.completePairing(
      sessionId: invitation.sessionId,
      pairingSecret: invitation.pairingSecret,
      peerDeviceId: peerIdentity.deviceId,
      peerPublicKey: peerIdentity.publicKeyBytes,
    );

    final auth = RemoteAuthenticator(
      localIdentity: desktopIdentity,
      resolvePeer: pairing.findPeer,
      crypto: RemoteCrypto(random: FixedRemoteRandom(180)),
      clock: clock,
      random: FixedRemoteRandom(200),
    );
    final challenge = await auth.issueChallenge(
      peerDeviceId: peerIdentity.deviceId,
    );
    final channelBinding = List<int>.filled(
      RemoteLimits.channelBindingBytes,
      0xa5,
    );
    final modifiedChallenge = RemoteAuthChallenge(
      sessionId: challenge.sessionId,
      peerDeviceId: challenge.peerDeviceId,
      serverNonce: challenge.serverNonce,
      serverPublicKey: challenge.serverPublicKey,
      issuedAt: challenge.issuedAt,
      expiresAt: challenge.expiresAt.add(const Duration(minutes: 1)),
    );
    final response = await auth.createResponse(
      challenge: modifiedChallenge,
      peerIdentity: peerIdentity,
      channelBinding: channelBinding,
    );

    await expectLater(
      auth.verifyResponse(
        challenge: modifiedChallenge,
        response: response,
        channelBinding: channelBinding,
      ),
      throwsA(
        isA<RemoteException>().having(
          (error) => error.code,
          'code',
          RemoteFailureCode.replayDetected,
        ),
      ),
    );
  });
}
