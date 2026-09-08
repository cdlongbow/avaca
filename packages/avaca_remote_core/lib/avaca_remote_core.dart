import 'dart:typed_data';

import 'package:avaca_protocol/avaca_protocol.dart';

export 'src/application_session.dart';
export 'src/client_profile.dart';
export 'src/discovery.dart';
export 'src/native_quic_transport.dart';
export 'src/profile_store_stub.dart'
    if (dart.library.ui) 'src/profile_store.dart';

enum AvacaRemoteRole { server, client }

enum AvacaRemoteFailureCode {
  invalidInput,
  unsupported,
  invalidState,
  connectionFailed,
  timeout,
  cancelled,
  frameTooLarge,
  internal,
}

class AvacaRemoteException implements Exception {
  const AvacaRemoteException(this.code, this.message);

  final AvacaRemoteFailureCode code;
  final String message;

  @override
  String toString() => 'AvacaRemoteException(${code.name}): $message';
}

class AvacaRemoteEndpoint {
  const AvacaRemoteEndpoint({required this.host, required this.port})
    : assert(host != ''),
      assert(port > 0 && port <= 65535);

  final String host;
  final int port;
}

abstract final class AvacaRemoteLimits {
  static const maxFrameBytes = 1024 * 1024;
  static const maxBufferedBytes = 16 * 1024 * 1024;
  static const maxReadBytes = 4 * 1024 * 1024;
  static const connectionTimeout = Duration(seconds: 15);
}

/// Role-specific transport configuration.  The server never receives a
/// client certificate pin, and the client never receives the server's private
/// certificate-store identity.
sealed class AvacaRemoteTransportConfig {
  const AvacaRemoteTransportConfig();
}

class AvacaRemoteServerConfig extends AvacaRemoteTransportConfig {
  const AvacaRemoteServerConfig({
    required this.certificateSha1Thumbprint,
    required this.listenPort,
  });

  final Uint8List certificateSha1Thumbprint;
  final int listenPort;
}

class AvacaRemoteClientConfig extends AvacaRemoteTransportConfig {
  const AvacaRemoteClientConfig({required this.certificateSha256Pin});

  final Uint8List certificateSha256Pin;
}

abstract interface class AvacaRemoteConnection {
  Stream<Uint8List> get incoming;
  bool get isOpen;
  Future<Uint8List> get channelBinding;
  Future<void> write(Uint8List bytes);
  Future<void> close();
}

abstract interface class AvacaRemoteListener {
  Future<void> close();
}

typedef AvacaRemoteConnectionHandler =
    Future<void> Function(AvacaRemoteConnection connection);

/// Optional application-layer failure contract.  Server packages can expose a
/// stable code/retry bit without making the transport depend on their
/// database or UI exception types.
abstract interface class AvacaApplicationFailure {
  String get code;

  bool get retryable;
}

abstract interface class AvacaRemoteTransport {
  AvacaRemoteRole get role;

  Future<AvacaRemoteConnection> connect(AvacaRemoteEndpoint endpoint);

  Future<AvacaRemoteListener> listen(AvacaRemoteConnectionHandler onConnection);

  Future<void> close();
}

abstract interface class AvacaRemoteTransportFactory {
  Future<AvacaRemoteTransport> createServer(AvacaRemoteServerConfig config);

  Future<AvacaRemoteTransport> createClient(AvacaRemoteClientConfig config);
}

class AvacaRemoteResourceDescriptor {
  const AvacaRemoteResourceDescriptor({
    required this.resourceId,
    required this.length,
    required this.mimeType,
    this.playbackSessionId,
    this.playbackGrant,
  });

  final String resourceId;
  final int length;
  final String mimeType;
  final String? playbackSessionId;
  final Uint8List? playbackGrant;
}

abstract interface class AvacaRemotePlaybackHandle {
  int get length;

  Future<Uint8List> readAt(int offset, int length);

  Future<void> cancel();

  Future<void> close();
}

/// Native range reads are intentionally exposed as a separate seam from the
/// catalog transport.  No Dart `Uint8List` media proxy or temporary file is
/// part of the production playback contract.
abstract interface class AvacaRemotePlaybackBridge {
  Future<AvacaRemotePlaybackHandle> open(
    AvacaRemoteResourceDescriptor descriptor,
  );
}

/// A tiny compile-time assertion shared by both app compositions.
void assertProtocolV2() {
  if (AvacaProtocol.version != 2 || AvacaProtocol.alpn != 'avaca-remote/2') {
    throw StateError('AVACA remote core requires protocol v2');
  }
}
