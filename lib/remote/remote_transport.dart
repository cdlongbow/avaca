import 'dart:typed_data';

import 'remote_endpoint.dart';
import 'remote_errors.dart';
import 'remote_limits.dart';

abstract interface class RemoteConnection {
  Stream<List<int>> get incoming;
  bool get isOpen;
  Future<Uint8List> get channelBinding;
  Future<void> write(List<int> bytes);
  Future<void> close();
}

abstract interface class RemoteListener {
  Future<void> close();
}

typedef RemoteConnectionHandler =
    Future<void> Function(RemoteConnection connection);

abstract interface class RemoteTransport {
  Future<RemoteConnection> connect(
    RemoteEndpoint endpoint, {
    Duration timeout = RemoteLimits.connectionTimeout,
  });

  Future<RemoteListener> listen(RemoteConnectionHandler onConnection);
  Future<void> close();
}

/// No plaintext socket or accept-all TLS transport is provided by the first
/// phase. A future adapter must prove encrypted, authenticated peer transport
/// before replacing this implementation in the production composition.
class UnavailableRemoteTransport implements RemoteTransport {
  const UnavailableRemoteTransport();

  @override
  Future<RemoteConnection> connect(
    RemoteEndpoint endpoint, {
    Duration timeout = RemoteLimits.connectionTimeout,
  }) async {
    throw const RemoteException(
      RemoteFailureCode.unsupported,
      'authenticated remote transport is not enabled in this phase',
    );
  }

  @override
  Future<RemoteListener> listen(RemoteConnectionHandler onConnection) async {
    throw const RemoteException(
      RemoteFailureCode.unsupported,
      'authenticated remote listener is not enabled in this phase',
    );
  }

  @override
  Future<void> close() async {}
}

typedef RemoteConnectionAuthenticator =
    Future<void> Function(RemoteConnection connection);

/// Reconnects only through newly resolved candidates and runs the complete
/// authentication callback on every new socket. A previously trusted socket
/// is never reused as proof of a new connection.
class RemoteReconnectController {
  RemoteReconnectController({
    required this.endpointProvider,
    required this.transport,
    required this.authenticate,
  });

  final EndpointCandidateProvider endpointProvider;
  final RemoteTransport transport;
  final RemoteConnectionAuthenticator authenticate;

  Future<RemoteConnection> reconnect() async {
    final candidates = await endpointProvider.getCandidates();
    final lanCandidates = candidates
        .where((endpoint) => endpoint.isLan)
        .take(16);
    var attempted = false;
    for (final endpoint in lanCandidates) {
      attempted = true;
      RemoteConnection? connection;
      try {
        connection = await transport.connect(endpoint);
        await authenticate(connection);
        return connection;
      } on Object {
        await connection?.close();
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
