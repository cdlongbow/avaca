import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'remote_auth.dart';
import 'remote_bytes.dart';
import 'remote_errors.dart';
import 'remote_identity.dart';
import 'remote_limits.dart';
import 'remote_endpoint.dart';
import 'remote_pairing.dart';
import 'remote_protocol.dart';
import 'remote_state_store.dart';
import 'remote_transport.dart';

enum RemoteSessionRole { client, server }

typedef RemoteAuthenticatedSessionHandler =
    Future<void> Function(RemoteAuthenticatedSession session);

/// An authenticated, framed channel. The application layer only receives a
/// [RemoteAuthenticatedSession] after the QUIC channel binding and the
/// pair-scoped mutual-authentication transcript have both succeeded.
class RemoteAuthenticatedSession {
  RemoteAuthenticatedSession._({
    required this.connection,
    required this.peerDeviceId,
    required this.role,
    required this.protocol,
    required _RemoteFrameChannel channel,
  }) : _channel = channel;

  final RemoteConnection connection;
  final String peerDeviceId;
  final RemoteSessionRole role;
  final RemoteProtocolSession protocol;
  final _RemoteFrameChannel _channel;
  bool _closed = false;

  bool get isOpen => !_closed && connection.isOpen;

  Future<RemoteFrame> readFrame() async {
    if (_closed) {
      throw const RemoteException(
        RemoteFailureCode.invalidState,
        'authenticated remote session is closed',
      );
    }
    final frame = await _channel.read(RemoteFramePhase.application);
    protocol.accept(frame);
    return frame;
  }

  Future<void> writeFrame(RemoteFrame frame) {
    if (_closed) {
      throw const RemoteException(
        RemoteFailureCode.invalidState,
        'authenticated remote session is closed',
      );
    }
    if (_isHandshakeCommand(frame.command)) {
      throw const RemoteException(
        RemoteFailureCode.invalidState,
        'authentication frames are not allowed after session setup',
      );
    }
    return _channel.write(frame, phase: RemoteFramePhase.application);
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    protocol.close();
    Object? firstError;
    StackTrace? firstStack;
    try {
      await _channel.cancel();
    } on Object catch (error, stackTrace) {
      firstError = error;
      firstStack = stackTrace;
    }
    try {
      await connection.close();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStack ??= stackTrace;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack ?? StackTrace.current);
    }
  }

  bool _isHandshakeCommand(RemoteCommand command) =>
      command == RemoteCommand.clientHello ||
      command == RemoteCommand.serverHello ||
      command == RemoteCommand.authenticate ||
      command == RemoteCommand.authenticatePlaybackGrant ||
      command == RemoteCommand.authenticated;
}

/// Runs the bounded, channel-bound handshake on either side of a transport.
///
/// This class deliberately does not create a transport or discover endpoints.
/// A caller must inject a transport whose [RemoteConnection.channelBinding] is
/// supplied by an authenticated TLS/QUIC session.
class RemoteSessionAuthenticator {
  RemoteSessionAuthenticator({
    required this.identityManager,
    required this.pairingManager,
    RemoteAuthenticator? authenticator,
    RemotePreAuthGate? preAuthGate,
    RemoteAuthPayloadCodec? payloadCodec,
  }) : authenticator =
           authenticator ??
           RemoteAuthenticator(
             localIdentity: identityManager,
             resolvePeer: pairingManager.findPeer,
           ),
       preAuthGate = preAuthGate ?? RemotePreAuthGate(),
       payloadCodec = payloadCodec ?? const RemoteAuthPayloadCodec();

  final RemoteIdentityManager identityManager;
  final RemotePairingManager pairingManager;
  final RemoteAuthenticator authenticator;
  final RemotePreAuthGate preAuthGate;
  final RemoteAuthPayloadCodec payloadCodec;

  Future<RemoteAuthenticatedSession> authenticateClient(
    RemoteConnection connection, {
    required String serverDeviceId,
  }) async {
    try {
      return await _authenticateClient(
        connection,
        serverDeviceId: serverDeviceId,
      ).timeout(RemoteLimits.authTimeout);
    } on TimeoutException {
      await _closeQuietly(connection);
      throw const RemoteException(
        RemoteFailureCode.timeout,
        'remote client authentication timed out',
      );
    }
  }

  Future<RemoteAuthenticatedSession> _authenticateClient(
    RemoteConnection connection, {
    required String serverDeviceId,
  }) async {
    final channel = _RemoteFrameChannel(connection);
    var handedOff = false;
    try {
      final localIdentity = await identityManager.loadOrCreate();
      final server = await _requirePeer(serverDeviceId);
      final expectedServerPublicKey = _decodePublicKey(server.publicKey);
      final binding = await _readChannelBinding(connection);
      final pairKey = await pairingManager.derivePairKey(
        serverDeviceId,
        purpose: 'preauth',
      );
      RemotePreAuthProof proof;
      try {
        proof = await preAuthGate.create(
          pairKey: pairKey,
          context: _preAuthContext(binding),
        );
      } finally {
        pairKey.fillRange(0, pairKey.length, 0);
      }
      await channel.write(
        RemoteFrame(
          command: RemoteCommand.clientHello,
          flags: 0,
          requestId: channel.nextRequestId(),
          payload: payloadCodec.encodeClientHello(
            peerDeviceId: localIdentity.deviceId,
            proof: proof,
          ),
        ),
        phase: RemoteFramePhase.preAuth,
      );

      final protocol = RemoteProtocolSession(isServer: false);
      final serverHello = await channel.read(RemoteFramePhase.auth);
      if (serverHello.command != RemoteCommand.serverHello) {
        throw const RemoteException(
          RemoteFailureCode.invalidState,
          'remote server did not send a server hello',
        );
      }
      final challenge = payloadCodec.decodeServerHello(serverHello.payload);
      if (challenge.peerDeviceId != localIdentity.deviceId ||
          !remoteConstantTimeEquals(
            expectedServerPublicKey,
            challenge.serverPublicKey,
          )) {
        throw const RemoteException(
          RemoteFailureCode.authenticationFailed,
          'remote server identity does not match pairing metadata',
        );
      }
      protocol.accept(serverHello);
      final response = await authenticator.createResponse(
        challenge: challenge,
        peerIdentity: localIdentity,
        channelBinding: binding,
      );
      await channel.write(
        RemoteFrame(
          command: RemoteCommand.authenticate,
          flags: 0,
          requestId: channel.nextRequestId(),
          payload: payloadCodec.encodeAuthenticate(response),
        ),
        phase: RemoteFramePhase.auth,
      );

      final authenticated = await channel.read(RemoteFramePhase.auth);
      if (authenticated.command != RemoteCommand.authenticated) {
        throw const RemoteException(
          RemoteFailureCode.invalidState,
          'remote server did not send authentication acceptance',
        );
      }
      final acceptance = payloadCodec.decodeAuthenticated(
        authenticated.payload,
      );
      final valid = await authenticator.verifyAcceptance(
        challenge: challenge,
        response: response,
        acceptance: acceptance,
        expectedServerPublicKey: expectedServerPublicKey,
        channelBinding: binding,
      );
      if (!valid) {
        throw const RemoteException(
          RemoteFailureCode.authenticationFailed,
          'remote server authentication acceptance is invalid',
        );
      }
      protocol.accept(authenticated);
      final session = RemoteAuthenticatedSession._(
        connection: connection,
        peerDeviceId: serverDeviceId,
        role: RemoteSessionRole.client,
        protocol: protocol,
        channel: channel,
      );
      handedOff = true;
      return session;
    } on Object {
      await channel.cancel();
      await _closeQuietly(connection);
      rethrow;
    } finally {
      if (!handedOff) {
        await channel.cancel();
      }
    }
  }

  Future<RemoteAuthenticatedSession> authenticateServer(
    RemoteConnection connection, {
    String source = 'unknown',
  }) async {
    try {
      return await _authenticateServer(
        connection,
        source: source,
      ).timeout(RemoteLimits.authTimeout);
    } on TimeoutException {
      await _closeQuietly(connection);
      throw const RemoteException(
        RemoteFailureCode.timeout,
        'remote server authentication timed out',
      );
    }
  }

  Future<RemoteAuthenticatedSession> _authenticateServer(
    RemoteConnection connection, {
    String source = 'unknown',
  }) async {
    final channel = _RemoteFrameChannel(connection);
    RemoteAuthChallenge? challenge;
    var handedOff = false;
    try {
      final binding = await _readChannelBinding(connection);
      final protocol = RemoteProtocolSession(isServer: true);
      final clientHello = await channel.read(RemoteFramePhase.preAuth);
      if (clientHello.command != RemoteCommand.clientHello) {
        throw const RemoteException(
          RemoteFailureCode.invalidState,
          'remote client did not send a client hello',
        );
      }
      final hello = payloadCodec.decodeClientHello(clientHello.payload);
      await _requirePeer(hello.peerDeviceId);
      final pairKey = await pairingManager.derivePairKey(
        hello.peerDeviceId,
        purpose: 'preauth',
      );
      try {
        await preAuthGate.verify(
          pairKey: pairKey,
          context: _preAuthContext(binding),
          proof: hello.proof,
        );
      } finally {
        pairKey.fillRange(0, pairKey.length, 0);
      }
      protocol.accept(clientHello);
      challenge = await authenticator.issueChallenge(
        peerDeviceId: hello.peerDeviceId,
        source: source,
      );
      await channel.write(
        RemoteFrame(
          command: RemoteCommand.serverHello,
          flags: 0,
          requestId: channel.nextRequestId(),
          payload: payloadCodec.encodeServerHello(challenge),
        ),
        phase: RemoteFramePhase.auth,
      );

      final authenticateFrame = await channel.read(RemoteFramePhase.auth);
      if (authenticateFrame.command != RemoteCommand.authenticate) {
        throw const RemoteException(
          RemoteFailureCode.invalidState,
          'remote client did not send an authentication response',
        );
      }
      final response = payloadCodec.decodeAuthenticate(
        authenticateFrame.payload,
      );
      await authenticator.verifyResponse(
        challenge: challenge,
        response: response,
        channelBinding: binding,
      );
      protocol.accept(authenticateFrame);
      final acceptance = await authenticator.createAcceptance(
        challenge: challenge,
        response: response,
        channelBinding: binding,
      );
      await channel.write(
        RemoteFrame(
          command: RemoteCommand.authenticated,
          flags: 0,
          requestId: channel.nextRequestId(),
          payload: payloadCodec.encodeAuthenticated(acceptance),
        ),
        phase: RemoteFramePhase.auth,
      );
      final session = RemoteAuthenticatedSession._(
        connection: connection,
        peerDeviceId: response.peerDeviceId,
        role: RemoteSessionRole.server,
        protocol: protocol,
        channel: channel,
      );
      handedOff = true;
      return session;
    } on Object {
      if (challenge != null) {
        authenticator.cancelChallenge(challenge);
      }
      await channel.cancel();
      await _closeQuietly(connection);
      rethrow;
    } finally {
      if (!handedOff) {
        await channel.cancel();
      }
    }
  }

  Future<RemotePairedDeviceMetadata> _requirePeer(String deviceId) async {
    remoteSafeIdentifier(deviceId);
    final peer = await pairingManager.findPeer(deviceId);
    if (peer == null) {
      throw const RemoteException(
        RemoteFailureCode.unknownPeer,
        'peer is not paired',
      );
    }
    if (peer.revoked) {
      throw const RemoteException(
        RemoteFailureCode.revokedPeer,
        'peer has been revoked',
      );
    }
    return peer;
  }

  Uint8List _decodePublicKey(String encoded) {
    try {
      final bytes = base64Url.decode(base64Url.normalize(encoded));
      if (bytes.length != 32) {
        throw const RemoteException(
          RemoteFailureCode.stateCorrupt,
          'paired peer public key metadata is malformed',
        );
      }
      return Uint8List.fromList(bytes);
    } on RemoteException {
      rethrow;
    } on FormatException {
      throw const RemoteException(
        RemoteFailureCode.stateCorrupt,
        'paired peer public key metadata is malformed',
      );
    }
  }

  Future<Uint8List> _readChannelBinding(RemoteConnection connection) async {
    try {
      final binding = await connection.channelBinding.timeout(
        RemoteLimits.authTimeout,
      );
      if (binding.length != RemoteLimits.channelBindingBytes) {
        throw const RemoteException(
          RemoteFailureCode.authenticationFailed,
          'remote transport channel binding has an invalid length',
        );
      }
      return Uint8List.fromList(binding);
    } on TimeoutException {
      throw const RemoteException(
        RemoteFailureCode.timeout,
        'remote transport channel binding was not available in time',
      );
    }
  }

  List<int> _preAuthContext(List<int> binding) {
    final writer = RemoteByteWriter()
      ..writeBytes(utf8.encode(RemoteLimits.preAuthContext))
      ..writeUint8(RemoteLimits.protocolVersion)
      ..writeLengthPrefixedBytes(
        binding,
        maxBytes: RemoteLimits.channelBindingBytes,
      );
    return writer.takeBytes();
  }

  Future<void> _closeQuietly(RemoteConnection connection) async {
    try {
      await connection.close();
    } on Object {
      // Preserve the authentication failure. The transport is still asked to
      // close, but a secondary close error must not hide the root cause.
    }
  }
}

/// Client-side reconnect composition that authenticates every newly opened
/// connection before returning it to the caller. A prior authenticated
/// connection is never reused as proof for another endpoint candidate.
class RemoteAuthenticatedReconnectController {
  RemoteAuthenticatedReconnectController({
    required this.endpointProvider,
    required this.transport,
    required this.sessionAuthenticator,
  });

  final EndpointCandidateProvider endpointProvider;
  final RemoteTransport transport;
  final RemoteSessionAuthenticator sessionAuthenticator;

  Future<RemoteAuthenticatedSession> reconnect({
    required String serverDeviceId,
  }) async {
    final candidates = (await endpointProvider.getCandidates())
        .where((endpoint) => endpoint.isLan)
        .take(RemoteLimits.maxDiscoveryEndpoints);
    var attempted = false;
    for (final endpoint in candidates) {
      attempted = true;
      RemoteConnection? connection;
      try {
        connection = await transport.connect(endpoint);
        return await sessionAuthenticator.authenticateClient(
          connection,
          serverDeviceId: serverDeviceId,
        );
      } on Object {
        try {
          await connection?.close();
        } on Object {
          // Preserve the authentication/connectivity failure for the next
          // candidate and keep the connection boundary fail-closed.
        }
      }
    }
    throw RemoteException(
      attempted
          ? RemoteFailureCode.connectionFailed
          : RemoteFailureCode.unavailable,
      attempted
          ? 'all resolved remote connection candidates failed authentication'
          : 'no proven remote connection candidate is available',
    );
  }
}

class _RemoteFrameChannel {
  _RemoteFrameChannel(this.connection)
    : _iterator = StreamIterator<List<int>>(connection.incoming);

  final RemoteConnection connection;
  final StreamIterator<List<int>> _iterator;
  final RemoteFrameCodec _codec = const RemoteFrameCodec();
  Uint8List _buffer = Uint8List(0);
  Future<void> _writeTail = Future<void>.value();
  int _nextRequest = 1;
  bool _cancelled = false;

  int nextRequestId() {
    if (_nextRequest > 0x7fffffffffffffff) {
      throw const RemoteException(
        RemoteFailureCode.invalidState,
        'remote request identifier space is exhausted',
      );
    }
    return _nextRequest++;
  }

  Future<void> write(RemoteFrame frame, {required RemoteFramePhase phase}) {
    final wire = _codec.encode(frame, phase: phase);
    final result = _writeTail.then((_) => connection.write(wire));
    _writeTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<RemoteFrame> read(RemoteFramePhase phase) async {
    while (true) {
      if (_buffer.length >= RemoteFrameCodec.headerLength) {
        final payloadLength =
            (_buffer[4] << 24) |
            (_buffer[5] << 16) |
            (_buffer[6] << 8) |
            _buffer[7];
        final maxPayload = switch (phase) {
          RemoteFramePhase.preAuth => RemoteLimits.preAuthFrameBytes,
          RemoteFramePhase.auth => RemoteLimits.authFrameBytes,
          RemoteFramePhase.application => RemoteLimits.applicationFrameBytes,
        };
        if (payloadLength > maxPayload) {
          throw const RemoteException(
            RemoteFailureCode.frameTooLarge,
            'remote frame exceeds the current phase limit',
          );
        }
        final frameLength = RemoteFrameCodec.headerLength + payloadLength;
        if (_buffer.length >= frameLength) {
          final frame = _codec.decode(
            _buffer.sublist(0, frameLength),
            phase: phase,
          );
          _buffer = Uint8List.fromList(_buffer.sublist(frameLength));
          return frame;
        }
      }

      if (!await _iterator.moveNext()) {
        if (_buffer.isNotEmpty) {
          throw const RemoteException(
            RemoteFailureCode.truncatedFrame,
            'remote stream ended with a partial frame',
          );
        }
        throw const RemoteException(
          RemoteFailureCode.connectionFailed,
          'remote stream ended before the expected frame',
        );
      }
      final chunk = _iterator.current;
      if (chunk.isEmpty) {
        continue;
      }
      if (chunk.length > RemoteLimits.maxBufferedBytesPerSession ||
          _buffer.length >
              RemoteLimits.maxBufferedBytesPerSession - chunk.length) {
        throw const RemoteException(
          RemoteFailureCode.frameTooLarge,
          'remote stream buffered bytes exceed the session limit',
        );
      }
      final combined = Uint8List(_buffer.length + chunk.length);
      combined.setAll(0, _buffer);
      combined.setAll(_buffer.length, chunk);
      _buffer = combined;
    }
  }

  Future<void> cancel() async {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    await _iterator.cancel();
  }
}
