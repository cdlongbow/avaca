import 'dart:async';
import 'dart:typed_data';

import 'package:avaca/remote/remote.dart';

class FixedRemoteClock implements RemoteClock {
  FixedRemoteClock([DateTime? initial])
    : current = (initial ?? DateTime.utc(2026, 1, 1)).toUtc();

  DateTime current;

  @override
  DateTime get now => current;
}

class FixedRemoteRandom implements RemoteRandom {
  FixedRemoteRandom([this._next = 1]);

  int _next;

  @override
  Uint8List bytes(int length) {
    final result = Uint8List(length);
    for (var index = 0; index < length; index++) {
      result[index] = (_next + index) & 0xff;
    }
    _next = (_next + length) & 0xff;
    return result;
  }
}

class MemoryRemoteSecretStore implements RemoteSecretStore {
  final Map<String, Uint8List> values = <String, Uint8List>{};
  int readCount = 0;
  int writeCount = 0;
  int deleteCount = 0;
  int closeCount = 0;

  @override
  Future<void> write(String key, List<int> secret) async {
    writeCount++;
    values[key] = Uint8List.fromList(secret);
  }

  @override
  Future<List<int>?> read(String key) async {
    readCount++;
    final value = values[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> delete(String key) async {
    deleteCount++;
    values.remove(key);
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}

class RecordingRemoteDiagnosticsSink implements RemoteDiagnosticsSink {
  final List<RemoteDiagnostic> records = <RemoteDiagnostic>[];

  @override
  void record(RemoteDiagnostic diagnostic) {
    records.add(diagnostic);
  }
}

class FakeEndpointCandidateProvider implements EndpointCandidateProvider {
  FakeEndpointCandidateProvider(this.candidates);

  List<RemoteEndpoint> candidates;
  int calls = 0;

  @override
  Future<List<RemoteEndpoint>> getCandidates() async {
    calls++;
    return List<RemoteEndpoint>.of(candidates);
  }
}

class FakeRemoteDiscovery implements RemoteDiscovery {
  final List<RemoteDiscoveryEnvelope> published = <RemoteDiscoveryEnvelope>[];
  int lookupCount = 0;
  int withdrawCount = 0;
  int closeCount = 0;

  @override
  Future<void> publish(RemoteDiscoveryEnvelope envelope) async {
    published.add(envelope);
  }

  @override
  Future<List<RemoteDiscoveryEnvelope>> lookup(String namespace) async {
    lookupCount++;
    return published
        .where((item) => item.namespace == namespace)
        .toList(growable: false);
  }

  @override
  Future<void> withdraw(String namespace) async {
    withdrawCount++;
    published.removeWhere((item) => item.namespace == namespace);
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}

class FakeRemoteTransport implements RemoteTransport {
  int connectCount = 0;
  int listenCount = 0;
  int closeCount = 0;
  FakeRemoteListener? listener;

  @override
  Future<RemoteConnection> connect(
    RemoteEndpoint endpoint, {
    Duration timeout = RemoteLimits.connectionTimeout,
  }) async {
    connectCount++;
    throw StateError('connect is not used by this fake');
  }

  @override
  Future<RemoteListener> listen(RemoteConnectionHandler onConnection) async {
    listenCount++;
    listener = FakeRemoteListener(onConnection);
    return listener!;
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}

class FakeRemoteListener implements RemoteListener {
  FakeRemoteListener([this.onConnection]);

  final RemoteConnectionHandler? onConnection;
  int closeCount = 0;

  Future<void> accept(RemoteConnection connection) async {
    final handler = onConnection;
    if (handler == null) {
      throw StateError('fake remote listener has no connection handler');
    }
    await handler(connection);
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}

class LinkedRemoteConnectionPair {
  LinkedRemoteConnectionPair(this.client, this.server);

  final LinkedRemoteConnection client;
  final LinkedRemoteConnection server;
}

class LinkedRemoteConnection implements RemoteConnection {
  LinkedRemoteConnection(List<int> channelBinding)
    : _channelBinding = Uint8List.fromList(channelBinding);

  final Uint8List _channelBinding;
  final StreamController<List<int>> _incoming = StreamController<List<int>>();
  late LinkedRemoteConnection _peer;
  bool _open = true;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  bool get isOpen => _open;

  @override
  Future<Uint8List> get channelBinding async =>
      Uint8List.fromList(_channelBinding);

  @override
  Future<void> write(List<int> bytes) async {
    if (!_open || !_peer._open) {
      throw const RemoteException(
        RemoteFailureCode.connectionFailed,
        'linked remote connection is closed',
      );
    }
    _peer._incoming.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> close() async {
    if (!_open) {
      return;
    }
    _open = false;
    unawaited(_incoming.close());
    if (_peer._open) {
      _peer._open = false;
      unawaited(_peer._incoming.close());
    }
  }
}

LinkedRemoteConnectionPair linkedRemoteConnectionPair({
  List<int>? clientChannelBinding,
  List<int>? serverChannelBinding,
}) {
  final client = LinkedRemoteConnection(
    clientChannelBinding ??
        List<int>.filled(RemoteLimits.channelBindingBytes, 0x5a),
  );
  final server = LinkedRemoteConnection(
    serverChannelBinding ??
        List<int>.filled(RemoteLimits.channelBindingBytes, 0x5a),
  );
  client._peer = server;
  server._peer = client;
  return LinkedRemoteConnectionPair(client, server);
}

class FakeRemoteEndpointChanges implements RemoteEndpointChangeSource {
  final StreamController<List<RemoteEndpoint>> _controller =
      StreamController<List<RemoteEndpoint>>.broadcast();

  @override
  Stream<List<RemoteEndpoint>> get changes => _controller.stream;

  void add(List<RemoteEndpoint> endpoints) => _controller.add(endpoints);

  @override
  Future<void> close() => _controller.close();
}

class SyntheticRemoteMediaSource implements RemoteMediaSource {
  SyntheticRemoteMediaSource({this.length = 4 * 1024 * 1024});

  final int length;
  final Set<Object> _openHandles = <Object>{};

  @override
  Future<RemoteResourceHandle> open(RemoteResourceId resourceId) async {
    final token = Object();
    _openHandles.add(token);
    return RemoteResourceHandle(token: token, length: length);
  }

  @override
  Future<RemoteReadResult> read(
    RemoteResourceHandle handle,
    RemoteByteRange range,
  ) async {
    if (!_openHandles.contains(handle.token)) {
      throw const RemoteException(
        RemoteFailureCode.resourceClosed,
        'synthetic handle is closed',
      );
    }
    range.validate(resourceLength: length);
    final bytes = Uint8List(range.length);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = (range.offset + index) & 0xff;
    }
    return RemoteReadResult(
      offset: range.offset,
      bytes: bytes,
      eof: range.offset + range.length >= length,
    );
  }

  @override
  Future<void> close(RemoteResourceHandle handle) async {
    _openHandles.remove(handle.token);
  }
}
