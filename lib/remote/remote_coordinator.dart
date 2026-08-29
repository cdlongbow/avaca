import 'dart:async';
import 'dart:io';

import 'remote_bytes.dart';
import 'remote_diagnostics.dart';
import 'remote_discovery.dart';
import 'remote_endpoint.dart';
import 'remote_errors.dart';
import 'remote_identity.dart';
import 'remote_limits.dart';
import 'remote_pairing.dart';
import 'remote_quic.dart';
import 'remote_state_store.dart';
import 'remote_transport.dart';
import 'remote_secret_store.dart';
import 'remote_session.dart';

enum RemoteConnectivityState {
  disabled,
  offline,
  starting,
  discovering,
  publishing,
  online,
  endpointChanged,
  republishing,
  degraded,
  stopped,
  connectionFailed,
}

abstract interface class RemoteSessionRegistry {
  int get activeCount;
  Object register(String peerDeviceId, Future<void> Function() close);
  void unregister(Object token);
  Future<void> closePeer(String peerDeviceId);
  Future<void> closeAll();
}

class InMemoryRemoteSessionRegistry implements RemoteSessionRegistry {
  final Map<Object, ({String peerDeviceId, Future<void> Function() close})>
  _sessions =
      <Object, ({String peerDeviceId, Future<void> Function() close})>{};

  @override
  int get activeCount => _sessions.length;

  @override
  Object register(String peerDeviceId, Future<void> Function() close) {
    final token = Object();
    _sessions[token] = (peerDeviceId: peerDeviceId, close: close);
    return token;
  }

  @override
  void unregister(Object token) {
    _sessions.remove(token);
  }

  @override
  Future<void> closePeer(String peerDeviceId) async {
    final matching = _sessions.entries
        .where((entry) => entry.value.peerDeviceId == peerDeviceId)
        .toList(growable: false);
    for (final entry in matching) {
      _sessions.remove(entry.key);
      await entry.value.close();
    }
  }

  @override
  Future<void> closeAll() async {
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    for (final session in sessions) {
      await session.close();
    }
  }
}

class _IncomingSessionLease {
  const _IncomingSessionLease({
    required this.session,
    required this.token,
    required this.handler,
  });

  final RemoteAuthenticatedSession session;
  final Object token;
  final Future<void> handler;
}

class RemoteServiceCoordinator {
  RemoteServiceCoordinator({
    required this.stateStore,
    required this.secretStore,
    required this.identityManager,
    required this.pairingManager,
    required this.discovery,
    required this.endpointProvider,
    required this.transport,
    RemoteEndpointChangeSource? endpointChanges,
    RemoteDiagnosticsSink? diagnostics,
    RemoteSessionRegistry? sessions,
    RemoteClock? clock,
    this.sessionAuthenticator,
    this.sessionHandler,
  }) : endpointChanges =
           endpointChanges ?? const NoopRemoteEndpointChangeSource(),
       diagnostics = diagnostics ?? const NoopRemoteDiagnosticsSink(),
       sessions = sessions ?? InMemoryRemoteSessionRegistry(),
       clock = clock ?? const SystemRemoteClock();

  factory RemoteServiceCoordinator.forApp({
    required String baseDir,
    RemoteDiagnosticsSink? diagnostics,
  }) {
    final dependencies = _RemoteAppDependencies.create(baseDir);
    return RemoteServiceCoordinator(
      stateStore: dependencies.stateStore,
      secretStore: dependencies.secretStore,
      identityManager: dependencies.identityManager,
      pairingManager: dependencies.pairingManager,
      discovery: const UnavailableRemoteDiscovery(),
      endpointProvider: const UnavailableEndpointCandidateProvider(),
      transport: const UnavailableRemoteTransport(),
      diagnostics: diagnostics,
    );
  }

  /// Creates the persistent app composition with explicitly supplied
  /// production providers. No endpoint, discovery, certificate, or transport
  /// fallback is inferred by this factory.
  factory RemoteServiceCoordinator.forConfiguredApp({
    required String baseDir,
    required RemoteDiscovery discovery,
    required EndpointCandidateProvider endpointProvider,
    required RemoteTransport transport,
    RemoteEndpointChangeSource? endpointChanges,
    RemoteDiagnosticsSink? diagnostics,
    RemoteAuthenticatedSessionHandler? sessionHandler,
  }) {
    final dependencies = _RemoteAppDependencies.create(baseDir);
    return RemoteServiceCoordinator(
      stateStore: dependencies.stateStore,
      secretStore: dependencies.secretStore,
      identityManager: dependencies.identityManager,
      pairingManager: dependencies.pairingManager,
      discovery: discovery,
      endpointProvider: endpointProvider,
      transport: transport,
      endpointChanges: endpointChanges,
      diagnostics: diagnostics,
      sessionAuthenticator: RemoteSessionAuthenticator(
        identityManager: dependencies.identityManager,
        pairingManager: dependencies.pairingManager,
      ),
      sessionHandler: sessionHandler,
    );
  }

  /// Windows production composition for a caller that has already provisioned
  /// the server certificate pin and supplied real endpoint/discovery
  /// providers. MsQuic construction fails closed when the bridge or pin is
  /// absent; no plaintext transport is substituted.
  factory RemoteServiceCoordinator.forWindowsMsQuic({
    required String baseDir,
    required List<int> pinnedServerCertificateSha256,
    required List<int> serverCertificateSha1,
    required int listenPort,
    required RemoteDiscovery discovery,
    required EndpointCandidateProvider endpointProvider,
    RemoteEndpointChangeSource? endpointChanges,
    RemoteDiagnosticsSink? diagnostics,
    RemoteAuthenticatedSessionHandler? sessionHandler,
  }) => RemoteServiceCoordinator.forConfiguredApp(
    baseDir: baseDir,
    discovery: discovery,
    endpointProvider: endpointProvider,
    transport: RemoteQuicTransport(
      pinnedServerCertificateSha256: pinnedServerCertificateSha256,
      serverCertificateSha1: serverCertificateSha1,
      listenPort: listenPort,
    ),
    endpointChanges: endpointChanges,
    diagnostics: diagnostics,
    sessionHandler: sessionHandler,
  );

  final RemoteStateStore stateStore;
  final RemoteSecretStore secretStore;
  final RemoteIdentityManager identityManager;
  final RemotePairingManager pairingManager;
  final RemoteDiscovery discovery;
  final EndpointCandidateProvider endpointProvider;
  final RemoteTransport transport;
  final RemoteEndpointChangeSource endpointChanges;
  final RemoteDiagnosticsSink diagnostics;
  final RemoteSessionRegistry sessions;
  final RemoteClock clock;
  final RemoteSessionAuthenticator? sessionAuthenticator;
  final RemoteAuthenticatedSessionHandler? sessionHandler;

  RemoteConnectivityState state = RemoteConnectivityState.stopped;
  bool _remoteEnabled = false;
  bool _started = false;
  bool _disposed = false;
  RemoteListener? _listener;
  StreamSubscription<List<RemoteEndpoint>>? _endpointSubscription;
  Future<void> _operationTail = Future<void>.value();
  bool _identityLoaded = false;

  bool get remoteEnabled => _remoteEnabled;
  bool get isStarted => _started;

  Future<void> startIfEnabled() async {
    _ensureNotDisposed();
    await _enqueue(() async {
      final persisted = await stateStore.load();
      _remoteEnabled = persisted.remoteEnabled;
      if (!_remoteEnabled) {
        state = RemoteConnectivityState.disabled;
        return;
      }
      await _startEnabled();
    });
  }

  Future<void> setEnabled(bool enabled) async {
    _ensureNotDisposed();
    await _enqueue(() async {
      final persisted = await stateStore.load();
      await stateStore.save(persisted.copyWith(remoteEnabled: enabled));
      _remoteEnabled = enabled;
      if (!enabled) {
        await _stopInternal();
        state = RemoteConnectivityState.disabled;
        return;
      }
      await _startEnabled();
    });
  }

  Future<void> refreshEndpoints() async {
    _ensureNotDisposed();
    if (!_remoteEnabled || !_started) {
      return;
    }
    await _enqueue(() => _publishCurrentEndpoints(isChange: true));
  }

  Future<void> revokePeer(String peerDeviceId) async {
    _ensureNotDisposed();
    await _enqueue(() async {
      Object? firstError;
      StackTrace? firstStack;
      try {
        await pairingManager.revoke(peerDeviceId);
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }

      // Revocation must close live sessions even if protected-secret deletion
      // fails after the revoked metadata has already been persisted.
      try {
        await sessions.closePeer(peerDeviceId);
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }

      if (_remoteEnabled && _started) {
        try {
          await _publishCurrentEndpoints(isChange: true);
        } on Object catch (error, stackTrace) {
          firstError ??= error;
          firstStack ??= stackTrace;
        }
      }

      if (firstError != null) {
        Error.throwWithStackTrace(firstError, firstStack ?? StackTrace.current);
      }
    });
  }

  Future<void> stop() async {
    if (_disposed && !_started) {
      return;
    }
    await _enqueue(_stopInternal);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await stop();
    _disposed = true;
    if (_identityLoaded) {
      await identityManager.dispose();
    }
  }

  Future<void> _startEnabled() async {
    if (_started) {
      return;
    }
    _started = true;
    state = RemoteConnectivityState.starting;
    try {
      await identityManager.loadOrCreate();
      _identityLoaded = true;
      await _publishCurrentEndpoints(isChange: false);
      _endpointSubscription = endpointChanges.changes.listen(
        (_) => _scheduleRefresh(),
        onError: (Object error, StackTrace stackTrace) {
          _diagnostic(
            'endpoint-change-source-failed',
            level: RemoteDiagnosticLevel.warning,
          );
        },
      );
    } on RemoteException catch (error) {
      state = error.code == RemoteFailureCode.authenticationFailed
          ? RemoteConnectivityState.connectionFailed
          : RemoteConnectivityState.degraded;
      _diagnostic(
        'start-degraded',
        level: RemoteDiagnosticLevel.warning,
        failureCode: error.code.name,
      );
    } on Object {
      state = RemoteConnectivityState.degraded;
      _diagnostic('start-degraded', level: RemoteDiagnosticLevel.warning);
    }
  }

  Future<void> _stopInternal() async {
    if (!_started) {
      return;
    }
    _started = false;
    await _endpointSubscription?.cancel();
    _endpointSubscription = null;
    await _listener?.close();
    _listener = null;
    await sessions.closeAll();
    await transport.close();
    await discovery.close();
    state = _remoteEnabled
        ? RemoteConnectivityState.stopped
        : RemoteConnectivityState.disabled;
    _diagnostic('stopped');
  }

  Future<void> _publishCurrentEndpoints({required bool isChange}) async {
    if (!_remoteEnabled || !_started) {
      return;
    }
    state = isChange
        ? RemoteConnectivityState.endpointChanged
        : RemoteConnectivityState.discovering;
    late final List<RemoteEndpoint> candidates;
    try {
      candidates = await endpointProvider.getCandidates();
    } on RemoteException catch (error) {
      state = RemoteConnectivityState.degraded;
      _diagnostic(
        'endpoint-discovery-unavailable',
        level: RemoteDiagnosticLevel.warning,
        failureCode: error.code.name,
      );
      return;
    }
    final lanCandidates = candidates
        .where((endpoint) => endpoint.isLan)
        .toList(growable: false);
    if (lanCandidates.isEmpty || lanCandidates.length > 16) {
      state = RemoteConnectivityState.degraded;
      _diagnostic('no-proven-endpoint', level: RemoteDiagnosticLevel.warning);
      return;
    }
    final oldState = await stateStore.load();
    final nextSequence = oldState.publicationSequence + 1;
    // Persist the monotonic sequence before publication so a restart cannot
    // accidentally publish a stale mutable record.
    await stateStore.save(
      oldState.copyWith(
        publicationSequence: nextSequence,
        lastPublishedEndpointFingerprint: _fingerprint(lanCandidates),
      ),
    );

    state = isChange
        ? RemoteConnectivityState.republishing
        : RemoteConnectivityState.publishing;
    final peers = oldState.pairedDevices
        .where((peer) => !peer.revoked)
        .toList(growable: false);
    if (peers.isEmpty) {
      state = RemoteConnectivityState.online;
      return;
    }
    final record = RemoteDiscoveryRecord(
      sequence: nextSequence,
      expiresAt: clock.now.toUtc().add(const Duration(hours: 1)),
      endpoints: lanCandidates,
    );
    for (final peer in peers) {
      final pairSecret = await pairingManager.readPairSecret(peer.deviceId);
      try {
        final envelope = await RemoteDiscoveryCodec(
          crypto: identityManager.crypto,
          clock: clock,
        ).seal(pairSecret: pairSecret, record: record);
        await discovery.publish(envelope);
      } finally {
        pairSecret.fillRange(0, pairSecret.length, 0);
      }
    }
    try {
      _listener ??= await transport.listen(_handleConnection);
      state = RemoteConnectivityState.online;
    } on RemoteException catch (error) {
      state = RemoteConnectivityState.degraded;
      _diagnostic(
        'transport-unavailable',
        level: RemoteDiagnosticLevel.warning,
        failureCode: error.code.name,
      );
    }
  }

  void _scheduleRefresh() {
    unawaited(
      refreshEndpoints().catchError((Object error) {
        state = RemoteConnectivityState.degraded;
        _diagnostic(
          'endpoint-refresh-failed',
          level: RemoteDiagnosticLevel.warning,
        );
      }),
    );
  }

  Future<void> _handleConnection(RemoteConnection connection) async {
    final authenticator = sessionAuthenticator;
    final handler = sessionHandler;
    if (authenticator == null || handler == null) {
      // A listener without an authenticated session handler must not leave an
      // accepted transport untracked. This is also the safe default for the
      // legacy/unavailable app composition.
      await _closeConnectionQuietly(connection);
      return;
    }

    RemoteAuthenticatedSession? session;
    Object? token;
    try {
      // Authentication is deliberately outside the mutation queue. A peer
      // that withholds its first frame must not block revokePeer, stop, or
      // endpoint publication. The authenticator and this outer timeout both
      // close stalled connections; the queue below is only the short
      // revocation fence around state and session ownership.
      session = await authenticator
          .authenticateServer(connection, source: 'listener')
          .timeout(
            RemoteLimits.authTimeout,
            onTimeout: () => throw const RemoteException(
              RemoteFailureCode.timeout,
              'incoming remote authentication timed out',
            ),
          );
      final authenticated = session;
      final lease = await _enqueue(() async {
        Object? registeredToken;
        try {
          if (!_remoteEnabled || !_started || _disposed) {
            throw const RemoteException(
              RemoteFailureCode.invalidState,
              'remote connectivity stopped before session handoff',
            );
          }
          final state = await stateStore.load();
          RemotePairedDeviceMetadata? peer;
          for (final candidate in state.pairedDevices) {
            if (candidate.deviceId == authenticated.peerDeviceId) {
              peer = candidate;
              break;
            }
          }
          if (peer == null || peer.revoked) {
            throw const RemoteException(
              RemoteFailureCode.authenticationFailed,
              'the authenticated remote peer has been revoked',
            );
          }
          registeredToken = sessions.register(
            authenticated.peerDeviceId,
            authenticated.close,
          );
          // Invoke the handler before relinquishing the operation-queue
          // fence, but let its long-lived work run outside that queue. A
          // later revokePeer can therefore close the registered session.
          final handlerFuture = handler(authenticated);
          return _IncomingSessionLease(
            session: authenticated,
            token: registeredToken,
            handler: handlerFuture,
          );
        } on Object {
          if (registeredToken != null) {
            sessions.unregister(registeredToken);
          }
          await _closeAuthenticatedSessionQuietly(authenticated);
          rethrow;
        }
      });
      session = lease.session;
      token = lease.token;
      await lease.handler;
    } on RemoteException catch (error) {
      _diagnostic(
        'incoming-session-rejected',
        level: RemoteDiagnosticLevel.warning,
        failureCode: error.code.name,
      );
    } on Object {
      _diagnostic(
        'incoming-session-failed',
        level: RemoteDiagnosticLevel.warning,
      );
    } finally {
      if (token != null) {
        sessions.unregister(token);
      }
      if (session != null) {
        await _closeAuthenticatedSessionQuietly(session);
      } else {
        await _closeConnectionQuietly(connection);
      }
    }
  }

  Future<void> _closeAuthenticatedSessionQuietly(
    RemoteAuthenticatedSession session,
  ) async {
    try {
      await session.close();
    } on Object {
      _diagnostic(
        'incoming-session-close-failed',
        level: RemoteDiagnosticLevel.warning,
      );
    }
  }

  Future<void> _closeConnectionQuietly(RemoteConnection connection) async {
    try {
      await connection.close();
    } on Object {
      _diagnostic(
        'incoming-connection-close-failed',
        level: RemoteDiagnosticLevel.warning,
      );
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final previous = _operationTail;
    final completed = Completer<void>();
    _operationTail = completed.future;
    return previous.then((_) => operation()).whenComplete(completed.complete);
  }

  String _fingerprint(List<RemoteEndpoint> endpoints) {
    final fingerprints =
        endpoints.map((endpoint) => endpoint.fingerprint).toList()..sort();
    return fingerprints.join(',');
  }

  void _diagnostic(
    String event, {
    RemoteDiagnosticLevel level = RemoteDiagnosticLevel.info,
    String? failureCode,
  }) {
    diagnostics.record(
      RemoteDiagnostic(
        level: level,
        event: event,
        state: state.name,
        failureCode: failureCode,
      ),
    );
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('RemoteServiceCoordinator has been disposed');
    }
  }
}

class _RemoteAppDependencies {
  _RemoteAppDependencies({
    required this.stateStore,
    required this.secretStore,
    required this.identityManager,
    required this.pairingManager,
  });

  factory _RemoteAppDependencies.create(String baseDir) {
    final remoteRoot = Directory('$baseDir${Platform.pathSeparator}remote');
    final secretRoot = Directory(
      '${remoteRoot.path}${Platform.pathSeparator}secrets',
    );
    final stateStore = FileRemoteStateStore(remoteRoot);
    final secretStore = Platform.isWindows
        ? WindowsDpapiSecretStore(secretRoot)
        : const UnavailableRemoteSecretStore();
    final identityManager = RemoteIdentityManager(
      stateStore: stateStore,
      secretStore: secretStore,
    );
    final pairingManager = RemotePairingManager(
      stateStore: stateStore,
      secretStore: secretStore,
      identityManager: identityManager,
    );
    return _RemoteAppDependencies(
      stateStore: stateStore,
      secretStore: secretStore,
      identityManager: identityManager,
      pairingManager: pairingManager,
    );
  }

  final RemoteStateStore stateStore;
  final RemoteSecretStore secretStore;
  final RemoteIdentityManager identityManager;
  final RemotePairingManager pairingManager;
}
