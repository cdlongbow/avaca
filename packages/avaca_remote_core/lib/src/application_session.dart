import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:avaca_protocol/avaca_protocol.dart';

import '../avaca_remote_core.dart';

enum AvacaApplicationRole { client, server }

typedef AvacaApplicationRequestHandler =
    Future<AvacaFrame> Function(AvacaFrame request);

/// Authenticated v2 application session shared by the Server and AVACA
/// compositions.  The session owns one framed QUIC stream and never exposes
/// a socket, path, SQL id, or media bytes to Flutter widgets.
final class AvacaApplicationSession {
  AvacaApplicationSession._({
    required this.role,
    required this.localId,
    required this.peerId,
    required this.authDomain,
    required AvacaRemoteConnection connection,
    required _AvacaFrameChannel channel,
  }) : _connection = connection,
       _channel = channel {
    if (role == AvacaApplicationRole.client) {
      _clientPump = _runClientPump();
    }
  }

  static const authenticationTimeout = Duration(seconds: 15);
  static const requestTimeout = Duration(seconds: 15);
  static const closeTimeout = Duration(seconds: 2);
  static const maxPendingRequests = 64;

  final AvacaApplicationRole role;
  final String localId;
  final String peerId;
  final String authDomain;
  final AvacaRemoteConnection _connection;
  final _AvacaFrameChannel _channel;
  final AvacaApplicationCodec _application = const AvacaApplicationCodec();
  final Map<int, _PendingResponse> _pending = <int, _PendingResponse>{};
  final Map<int, Future<void>> _serverTasks = <int, Future<void>>{};
  final Set<int> _ignoredRequestIds = <int>{};
  final Queue<int> _ignoredRequestOrder = Queue<int>();
  int _nextRequestId = 1;
  Future<void>? _clientPump;
  Future<void>? _serverLoop;
  bool _closed = false;

  bool get isOpen => !_closed && _connection.isOpen;

  /// Client-side authenticated session.  Pairing secrets are copied for the
  /// transcript and wiped before this method returns.
  static Future<AvacaApplicationSession> authenticateClient(
    AvacaRemoteConnection connection, {
    required String clientId,
    required String expectedServerId,
    required List<int> pairingSecret,
    String authDomain = AvacaHandshakeCodec.controlDomain,
    Duration timeout = authenticationTimeout,
  }) async {
    try {
      return await _authenticateClient(
        connection,
        clientId: clientId,
        expectedServerId: expectedServerId,
        pairingSecret: pairingSecret,
        authDomain: authDomain,
      ).timeout(timeout);
    } on TimeoutException {
      await _closeQuietly(connection);
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.timeout,
        'AVACA authentication timed out',
      );
    }
  }

  static Future<AvacaApplicationSession> _authenticateClient(
    AvacaRemoteConnection connection, {
    required String clientId,
    required String expectedServerId,
    required List<int> pairingSecret,
    required String authDomain,
  }) async {
    final codec = const AvacaHandshakeCodec();
    final channel = _AvacaFrameChannel(connection);
    final secret = Uint8List.fromList(pairingSecret);
    final clientNonce = _randomBytes(AvacaHandshakeCodec.nonceLength);
    try {
      _checkSecret(secret);
      _checkHandshakeId(clientId);
      _checkHandshakeId(expectedServerId);
      final binding = await _readBinding(connection);
      final hello = AvacaClientHelloDto(
        clientId: clientId,
        clientNonce: clientNonce,
        proof: codec.clientProof(
          secret: secret,
          clientId: clientId,
          clientNonce: clientNonce,
          channelBinding: binding,
          domain: authDomain,
        ),
      );
      await channel.write(
        AvacaFrame(
          opcode: AvacaOpcode.clientHello,
          requestId: 1,
          payload: codec.encodeClientHello(hello),
        ),
        phase: AvacaFramePhase.preAuth,
      );

      final serverFrame = await channel.read(AvacaFramePhase.auth);
      if (serverFrame.opcode != AvacaOpcode.serverHello) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.invalidState,
          'AVACA server hello was not received',
        );
      }
      final serverHello = codec.decodeServerHello(serverFrame.payload);
      if (serverHello.serverId != expectedServerId ||
          serverHello.clientId != clientId) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.connectionFailed,
          'AVACA server identity did not match the pairing record',
        );
      }
      final expectedServerProof = codec.serverProof(
        secret: secret,
        serverId: serverHello.serverId,
        clientId: clientId,
        clientNonce: clientNonce,
        serverNonce: serverHello.serverNonce,
        channelBinding: binding,
        domain: authDomain,
      );
      if (!codec.constantTimeEquals(expectedServerProof, serverHello.proof)) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.connectionFailed,
          'AVACA server authentication proof was invalid',
        );
      }
      final acceptanceProof = codec.clientAcceptanceProof(
        secret: secret,
        serverId: serverHello.serverId,
        clientId: clientId,
        clientNonce: clientNonce,
        serverNonce: serverHello.serverNonce,
        channelBinding: binding,
        domain: authDomain,
      );
      await channel.write(
        AvacaFrame(
          opcode: AvacaOpcode.authenticatePair,
          requestId: 2,
          payload: codec.encodeAuthenticated(
            AvacaAuthenticatedDto(
              serverId: serverHello.serverId,
              clientId: clientId,
              proof: acceptanceProof,
            ),
          ),
        ),
        phase: AvacaFramePhase.auth,
      );

      final authenticatedFrame = await channel.read(AvacaFramePhase.auth);
      if (authenticatedFrame.opcode != AvacaOpcode.authenticated) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.invalidState,
          'AVACA server did not complete authentication',
        );
      }
      final authenticated = codec.decodeAuthenticated(
        authenticatedFrame.payload,
      );
      if (authenticated.serverId != serverHello.serverId ||
          authenticated.clientId != clientId ||
          !codec.constantTimeEquals(acceptanceProof, authenticated.proof)) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.connectionFailed,
          'AVACA server authentication acceptance was invalid',
        );
      }
      return AvacaApplicationSession._(
        role: AvacaApplicationRole.client,
        localId: clientId,
        peerId: serverHello.serverId,
        authDomain: authDomain,
        connection: connection,
        channel: channel,
      );
    } on AvacaRemoteException {
      await channel.close();
      await _closeQuietly(connection);
      rethrow;
    } on AvacaProtocolException {
      await channel.close();
      await _closeQuietly(connection);
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.connectionFailed,
        'AVACA authentication payload was invalid',
      );
    } on Object {
      await channel.close();
      await _closeQuietly(connection);
      rethrow;
    } finally {
      secret.fillRange(0, secret.length, 0);
      clientNonce.fillRange(0, clientNonce.length, 0);
    }
  }

  /// Server-side authenticated session.  A single pairing secret is used by
  /// the first vertical slice; production composition can resolve a secret by
  /// opaque client id before invoking this method.
  static Future<AvacaApplicationSession> authenticateServer(
    AvacaRemoteConnection connection, {
    required String serverId,
    required List<int> pairingSecret,
    FutureOr<List<int>?> Function(String clientId)? pairingSecretResolver,
    String? expectedClientId,
    String authDomain = AvacaHandshakeCodec.controlDomain,
    Iterable<String>? acceptedAuthDomains,
    Duration timeout = authenticationTimeout,
  }) async {
    final authDomains =
        acceptedAuthDomains?.toList(growable: false) ?? <String>[authDomain];
    try {
      return await _authenticateServer(
        connection,
        serverId: serverId,
        pairingSecret: pairingSecret,
        pairingSecretResolver: pairingSecretResolver,
        expectedClientId: expectedClientId,
        authDomains: authDomains,
      ).timeout(timeout);
    } on TimeoutException {
      await _closeQuietly(connection);
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.timeout,
        'AVACA Server authentication timed out',
      );
    }
  }

  static Future<AvacaApplicationSession> _authenticateServer(
    AvacaRemoteConnection connection, {
    required String serverId,
    required List<int> pairingSecret,
    required FutureOr<List<int>?> Function(String clientId)?
    pairingSecretResolver,
    required String? expectedClientId,
    required List<String> authDomains,
  }) async {
    final codec = const AvacaHandshakeCodec();
    final channel = _AvacaFrameChannel(connection);
    Uint8List? secret;
    Uint8List? clientNonce;
    Uint8List? serverNonce;
    try {
      _checkHandshakeId(serverId);
      if (expectedClientId != null) _checkHandshakeId(expectedClientId);
      if (authDomains.isEmpty ||
          authDomains.any(
            (domain) =>
                domain != AvacaHandshakeCodec.controlDomain &&
                domain != AvacaHandshakeCodec.playbackDomain,
          )) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.invalidInput,
          'AVACA Server authentication domain is invalid',
        );
      }
      if (pairingSecretResolver == null) {
        secret = Uint8List.fromList(pairingSecret);
        _checkSecret(secret);
      }
      final binding = await _readBinding(connection);
      final helloFrame = await channel.read(AvacaFramePhase.preAuth);
      if (helloFrame.opcode != AvacaOpcode.clientHello) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.invalidState,
          'AVACA client hello was not received',
        );
      }
      final hello = codec.decodeClientHello(helloFrame.payload);
      if (expectedClientId != null && hello.clientId != expectedClientId) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.connectionFailed,
          'AVACA client is not paired with this Server',
        );
      }
      final resolvedSecret = pairingSecretResolver == null
          ? pairingSecret
          : await pairingSecretResolver(hello.clientId);
      if (resolvedSecret == null) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.connectionFailed,
          'AVACA client is not paired with this Server',
        );
      }
      secret = Uint8List.fromList(resolvedSecret);
      _checkSecret(secret);
      clientNonce = Uint8List.fromList(hello.clientNonce);
      String? authenticatedDomain;
      for (final candidateDomain in authDomains) {
        final expectedClientProof = codec.clientProof(
          secret: secret,
          clientId: hello.clientId,
          clientNonce: clientNonce,
          channelBinding: binding,
          domain: candidateDomain,
        );
        if (codec.constantTimeEquals(expectedClientProof, hello.proof)) {
          authenticatedDomain = candidateDomain;
          break;
        }
      }
      if (authenticatedDomain == null) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.connectionFailed,
          'AVACA client authentication proof was invalid',
        );
      }
      serverNonce = _randomBytes(AvacaHandshakeCodec.nonceLength);
      final serverHello = AvacaServerHelloDto(
        serverId: serverId,
        clientId: hello.clientId,
        serverNonce: serverNonce,
        proof: codec.serverProof(
          secret: secret,
          serverId: serverId,
          clientId: hello.clientId,
          clientNonce: clientNonce,
          serverNonce: serverNonce,
          channelBinding: binding,
          domain: authenticatedDomain,
        ),
      );
      await channel.write(
        AvacaFrame(
          opcode: AvacaOpcode.serverHello,
          requestId: 1,
          payload: codec.encodeServerHello(serverHello),
        ),
        phase: AvacaFramePhase.auth,
      );
      final authenticateFrame = await channel.read(AvacaFramePhase.auth);
      if (authenticateFrame.opcode != AvacaOpcode.authenticatePair) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.invalidState,
          'AVACA client did not complete pair authentication',
        );
      }
      final authenticate = codec.decodeAuthenticated(authenticateFrame.payload);
      final acceptanceProof = codec.clientAcceptanceProof(
        secret: secret,
        serverId: serverId,
        clientId: hello.clientId,
        clientNonce: clientNonce,
        serverNonce: serverNonce,
        channelBinding: binding,
        domain: authenticatedDomain,
      );
      if (authenticate.serverId != serverId ||
          authenticate.clientId != hello.clientId ||
          !codec.constantTimeEquals(acceptanceProof, authenticate.proof)) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.connectionFailed,
          'AVACA pair authentication acceptance was invalid',
        );
      }
      await channel.write(
        AvacaFrame(
          opcode: AvacaOpcode.authenticated,
          requestId: 2,
          payload: codec.encodeAuthenticated(
            AvacaAuthenticatedDto(
              serverId: serverId,
              clientId: hello.clientId,
              proof: acceptanceProof,
            ),
          ),
        ),
        phase: AvacaFramePhase.auth,
      );
      return AvacaApplicationSession._(
        role: AvacaApplicationRole.server,
        localId: serverId,
        peerId: hello.clientId,
        authDomain: authenticatedDomain,
        connection: connection,
        channel: channel,
      );
    } on AvacaRemoteException {
      await channel.close();
      await _closeQuietly(connection);
      rethrow;
    } on AvacaProtocolException {
      await channel.close();
      await _closeQuietly(connection);
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.connectionFailed,
        'AVACA client authentication payload was invalid',
      );
    } on Object {
      await channel.close();
      await _closeQuietly(connection);
      rethrow;
    } finally {
      final secretValue = secret;
      secretValue?.fillRange(0, secretValue.length, 0);
      final clientNonceValue = clientNonce;
      final serverNonceValue = serverNonce;
      clientNonceValue?.fillRange(0, clientNonceValue.length, 0);
      serverNonceValue?.fillRange(0, serverNonceValue.length, 0);
    }
  }

  /// Send one bounded request and wait for its matching response.  Requests
  /// are written serially, while response reads run in one pump so concurrent
  /// UI actions cannot race the stream iterator or deadlock each other.
  Future<AvacaFrame> request(
    AvacaOpcode opcode,
    List<int> payload, {
    required Set<AvacaOpcode> expectedResponses,
    Duration timeout = requestTimeout,
  }) async {
    _ensureClient();
    if (payload.length > AvacaFrameCodec.applicationMax) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.frameTooLarge,
        'AVACA request exceeds the application frame limit',
      );
    }
    if (!_isClientRequest(opcode)) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidInput,
        'AVACA request opcode is not an application request',
      );
    }
    if (expectedResponses.isEmpty) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidInput,
        'AVACA response opcode set cannot be empty',
      );
    }
    if (_pending.length >= maxPendingRequests) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'AVACA request budget is busy; retry shortly',
      );
    }
    final requestId = _allocateRequestId();
    final pending = _PendingResponse(
      expectedResponses: expectedResponses,
      completer: Completer<AvacaFrame>(),
    );
    _pending[requestId] = pending;
    var timedOut = false;
    try {
      await _channel.write(
        AvacaFrame(opcode: opcode, requestId: requestId, payload: payload),
        phase: AvacaFramePhase.application,
      );
      final frame = await pending.completer.future.timeout(timeout);
      if (!pending.expectedResponses.contains(frame.opcode)) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.invalidState,
          'AVACA response opcode did not match the request',
        );
      }
      return frame;
    } on TimeoutException {
      timedOut = true;
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.timeout,
        'AVACA request timed out',
      );
    } finally {
      _pending.remove(requestId);
      if (timedOut) _rememberIgnoredRequest(requestId);
    }
  }

  /// Server-side request loop.  Frame parsing remains serial, while handler
  /// work is dispatched concurrently so a cancelRead frame can be consumed
  /// while another request is blocked in a range read.
  Future<void> serve(AvacaApplicationRequestHandler handler) {
    if (role != AvacaApplicationRole.server) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'only an AVACA Server session can serve requests',
      );
    }
    if (_serverLoop != null) return _serverLoop!;
    _serverLoop = _runServer(handler);
    return _serverLoop!;
  }

  Future<AvacaFrame> readFrame() async {
    _ensureOpen();
    if (role != AvacaApplicationRole.server) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'client sessions use request() instead of readFrame()',
      );
    }
    return _channel.read(AvacaFramePhase.application);
  }

  Future<void> writeResponse(AvacaFrame response) async {
    _ensureServer();
    if (!_isServerResponse(response.opcode)) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidInput,
        'AVACA response opcode is not an application response',
      );
    }
    await _channel.write(response, phase: AvacaFramePhase.application);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final error = const AvacaRemoteException(
      AvacaRemoteFailureCode.cancelled,
      'AVACA application session closed',
    );
    for (final pending in _pending.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error);
      }
    }
    _pending.clear();
    final pump = _clientPump;
    try {
      await _channel.close().timeout(closeTimeout);
    } on Object {
      // Transport close below remains authoritative and bounded.
    }
    if (pump != null) {
      try {
        await pump.timeout(closeTimeout);
      } on Object {
        // Closing the channel releases a reader waiting on the stream.
      }
    }
    await _closeQuietly(_connection);
  }

  Future<void> _runClientPump() async {
    try {
      while (!_closed) {
        final frame = await _channel.read(AvacaFramePhase.application);
        final pending = _pending[frame.requestId];
        if (pending == null) {
          if (_ignoredRequestIds.remove(frame.requestId)) {
            _ignoredRequestOrder.remove(frame.requestId);
            continue;
          }
          throw const AvacaRemoteException(
            AvacaRemoteFailureCode.invalidState,
            'AVACA response request id is unknown',
          );
        }
        _pending.remove(frame.requestId);
        if (frame.opcode == AvacaOpcode.error) {
          final decoded = _application.decodeError(frame.payload);
          pending.completer.completeError(
            AvacaRemoteException(
              _failureCode(decoded.failureCode),
              _redactFailure(decoded.failureCode),
            ),
          );
        } else {
          pending.completer.complete(frame);
        }
      }
    } on Object catch (error, stackTrace) {
      _failPending(error, stackTrace);
    }
  }

  Future<void> _runServer(AvacaApplicationRequestHandler handler) async {
    try {
      while (!_closed) {
        final request = await _channel.read(AvacaFramePhase.application);
        if (!_isServerRequest(request.opcode)) {
          throw const AvacaRemoteException(
            AvacaRemoteFailureCode.invalidState,
            'AVACA request opcode is not allowed on the Server session',
          );
        }
        final task = _dispatchServerRequest(handler, request);
        _serverTasks[request.requestId] = task;
        unawaited(
          task.whenComplete(() => _serverTasks.remove(request.requestId)),
        );
      }
    } on Object catch (error, stackTrace) {
      _failPending(error, stackTrace);
    }
  }

  Future<void> _dispatchServerRequest(
    AvacaApplicationRequestHandler handler,
    AvacaFrame request,
  ) async {
    try {
      final response = await handler(request);
      if (response.requestId != request.requestId) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.invalidState,
          'AVACA handler returned a mismatched request id',
        );
      }
      if (!_closed) await writeResponse(response);
    } on Object catch (error) {
      if (_closed) return;
      final failureCode = error is AvacaRemoteException
          ? error.code.name
          : error is AvacaApplicationFailure
          ? error.code
          : 'internal';
      try {
        await writeResponse(
          AvacaFrame(
            opcode: AvacaOpcode.error,
            requestId: request.requestId,
            payload: _application.encodeError(
              AvacaErrorDto(
                failureCode: failureCode,
                retryable:
                    error is AvacaRemoteException &&
                        (error.code == AvacaRemoteFailureCode.timeout ||
                            error.code == AvacaRemoteFailureCode.cancelled) ||
                    error is AvacaApplicationFailure && error.retryable,
                requestId: request.requestId,
              ),
            ),
          ),
        );
      } on Object {
        // A connection close racing a terminal error is already fail-closed.
      }
    }
  }

  void _failPending(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _closed = true;
    for (final pending in _pending.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error, stackTrace);
      }
    }
    _pending.clear();
    _ignoredRequestIds.clear();
    _ignoredRequestOrder.clear();
    unawaited(_closeQuietly(_connection));
  }

  int _allocateRequestId() {
    if (_nextRequestId > 0x7fffffffffffffff) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'AVACA request identifier space is exhausted',
      );
    }
    return _nextRequestId++;
  }

  void _rememberIgnoredRequest(int requestId) {
    if (_ignoredRequestIds.add(requestId)) {
      _ignoredRequestOrder.addLast(requestId);
    }
    while (_ignoredRequestOrder.length > maxPendingRequests) {
      _ignoredRequestIds.remove(_ignoredRequestOrder.removeFirst());
    }
  }

  void _ensureOpen() {
    if (!isOpen) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'AVACA application session is closed',
      );
    }
  }

  void _ensureClient() {
    _ensureOpen();
    if (role != AvacaApplicationRole.client) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'AVACA request API is client-only',
      );
    }
  }

  void _ensureServer() {
    _ensureOpen();
    if (role != AvacaApplicationRole.server) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'AVACA response API is Server-only',
      );
    }
  }

  bool _isServerRequest(AvacaOpcode opcode) => const <AvacaOpcode>{
    AvacaOpcode.getCapabilities,
    AvacaOpcode.listCollection,
    AvacaOpcode.getWorkDetail,
    AvacaOpcode.openAsset,
    AvacaOpcode.createPlaybackSession,
    AvacaOpcode.closePlaybackSession,
    AvacaOpcode.openResource,
    AvacaOpcode.readResource,
    AvacaOpcode.cancelRead,
    AvacaOpcode.closeResource,
    AvacaOpcode.ping,
  }.contains(opcode);

  bool _isClientRequest(AvacaOpcode opcode) => _isServerRequest(opcode);

  bool _isServerResponse(AvacaOpcode opcode) => const <AvacaOpcode>{
    AvacaOpcode.capabilities,
    AvacaOpcode.collectionPage,
    AvacaOpcode.workDetail,
    AvacaOpcode.assetOpened,
    AvacaOpcode.playbackSessionCreated,
    AvacaOpcode.playbackSessionClosed,
    AvacaOpcode.resourceOpened,
    AvacaOpcode.resourceChunk,
    AvacaOpcode.resourceClosed,
    AvacaOpcode.pong,
    AvacaOpcode.error,
  }.contains(opcode);

  static AvacaRemoteFailureCode _failureCode(String value) {
    for (final code in AvacaRemoteFailureCode.values) {
      if (code.name == value) return code;
    }
    return AvacaRemoteFailureCode.internal;
  }

  static String _redactFailure(String value) =>
      'AVACA remote request failed (${_failureCode(value).name})';

  static Future<Uint8List> _readBinding(
    AvacaRemoteConnection connection,
  ) async {
    try {
      final binding = await connection.channelBinding.timeout(
        authenticationTimeout,
      );
      if (binding.length != 32) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.connectionFailed,
          'QUIC channel binding length is invalid',
        );
      }
      return Uint8List.fromList(binding);
    } on TimeoutException {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.timeout,
        'QUIC channel binding was not available in time',
      );
    }
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static void _checkSecret(List<int> secret) {
    if (secret.length < 32) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidInput,
        'AVACA pairing secret is too short',
      );
    }
  }

  static void _checkHandshakeId(String value) {
    if (value.isEmpty ||
        value.length > AvacaHandshakeCodec.maxIdBytes ||
        !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(value)) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidInput,
        'AVACA device identifier is invalid',
      );
    }
  }

  static Future<void> _closeQuietly(AvacaRemoteConnection connection) async {
    try {
      await connection.close().timeout(closeTimeout);
    } on Object {
      // Keep the authentication or request failure as the primary error.
    }
  }
}

final class _PendingResponse {
  _PendingResponse({required this.expectedResponses, required this.completer});

  final Set<AvacaOpcode> expectedResponses;
  final Completer<AvacaFrame> completer;
}

final class _AvacaFrameChannel {
  _AvacaFrameChannel(this.connection)
    : _iterator = StreamIterator<Uint8List>(connection.incoming);

  final AvacaRemoteConnection connection;
  final StreamIterator<Uint8List> _iterator;
  final AvacaFrameCodec _codec = const AvacaFrameCodec();
  Uint8List _buffer = Uint8List(0);
  Future<void> _writeTail = Future<void>.value();
  bool _closed = false;

  Future<void> write(AvacaFrame frame, {required AvacaFramePhase phase}) {
    if (_closed) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'AVACA frame channel is closed',
      );
    }
    final wire = _codec.encode(frame, phase: phase);
    final result = _writeTail.then<void>((_) => connection.write(wire));
    _writeTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<AvacaFrame> read(AvacaFramePhase phase) async {
    if (_closed) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'AVACA frame channel is closed',
      );
    }
    while (true) {
      if (_buffer.length >= AvacaFrameCodec.headerLength) {
        final header = ByteData.sublistView(_buffer);
        final payloadLength = header.getUint32(4, Endian.big);
        final maxPayload = switch (phase) {
          AvacaFramePhase.preAuth => AvacaFrameCodec.preAuthMax,
          AvacaFramePhase.auth => AvacaFrameCodec.authMax,
          AvacaFramePhase.application => AvacaFrameCodec.applicationMax,
        };
        if (payloadLength > maxPayload) {
          throw const AvacaRemoteException(
            AvacaRemoteFailureCode.frameTooLarge,
            'AVACA frame exceeds its phase limit',
          );
        }
        final frameLength = AvacaFrameCodec.headerLength + payloadLength;
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
          throw const AvacaRemoteException(
            AvacaRemoteFailureCode.connectionFailed,
            'AVACA stream ended with a partial frame',
          );
        }
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.connectionFailed,
          'AVACA stream ended before the expected frame',
        );
      }
      final chunk = _iterator.current;
      if (chunk.isEmpty) continue;
      if (chunk.length > AvacaRemoteLimits.maxBufferedBytes ||
          _buffer.length > AvacaRemoteLimits.maxBufferedBytes - chunk.length) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.frameTooLarge,
          'AVACA stream buffered bytes exceed the session limit',
        );
      }
      final combined = Uint8List(_buffer.length + chunk.length)
        ..setAll(0, _buffer)
        ..setAll(_buffer.length, chunk);
      _buffer = combined;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _iterator.cancel();
    } on Object {
      // Connection close remains authoritative.
    }
    _buffer = Uint8List(0);
  }
}
