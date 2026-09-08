import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../avaca_remote_core.dart';

typedef _NativeEvent =
    Void Function(
      Pointer<Void> context,
      Uint64 object,
      Uint32 event,
      Int32 status,
      Uint64 operation,
      Pointer<Uint8> data,
      Uint32 length,
      Uint8 flags,
    );

typedef _NativeCreateServer =
    Int32 Function(
      Pointer<Uint8> certificateSha1,
      Uint32 certificateSha1Length,
      Pointer<NativeFunction<_NativeEvent>> callback,
      Pointer<Void> context,
      Pointer<Uint64> transport,
    );
typedef _DartCreateServer =
    int Function(
      Pointer<Uint8> certificateSha1,
      int certificateSha1Length,
      Pointer<NativeFunction<_NativeEvent>> callback,
      Pointer<Void> context,
      Pointer<Uint64> transport,
    );

typedef _NativeCreateClient =
    Int32 Function(
      Pointer<Uint8> certificateSha256Pin,
      Uint32 certificateSha256PinLength,
      Pointer<NativeFunction<_NativeEvent>> callback,
      Pointer<Void> context,
      Pointer<Uint64> transport,
    );
typedef _DartCreateClient =
    int Function(
      Pointer<Uint8> certificateSha256Pin,
      int certificateSha256PinLength,
      Pointer<NativeFunction<_NativeEvent>> callback,
      Pointer<Void> context,
      Pointer<Uint64> transport,
    );

typedef _NativeListen =
    Int32 Function(Uint64 transport, Uint16 port, Pointer<Uint64> listener);
typedef _DartListen =
    int Function(int transport, int port, Pointer<Uint64> listener);

typedef _NativeConnect =
    Int32 Function(
      Uint64 transport,
      Pointer<Utf8> host,
      Uint16 port,
      Pointer<Uint64> connection,
    );
typedef _DartConnect =
    int Function(
      int transport,
      Pointer<Utf8> host,
      int port,
      Pointer<Uint64> connection,
    );

typedef _NativeSend =
    Int32 Function(
      Uint64 connection,
      Pointer<Uint8> data,
      Uint32 length,
      Uint64 operation,
    );
typedef _DartSend =
    int Function(
      int connection,
      Pointer<Uint8> data,
      int length,
      int operation,
    );

typedef _NativeCloseConnection = Int32 Function(Uint64 connection);
typedef _DartCloseConnection = int Function(int connection);

typedef _NativeCloseListener =
    Int32 Function(Uint64 transport, Uint64 listener);
typedef _DartCloseListener = int Function(int transport, int listener);

typedef _NativeClose = Int32 Function(Uint64 transport);
typedef _DartClose = int Function(int transport);

typedef _NativeFreeBuffer = Void Function(Pointer<Uint8> data);
typedef _DartFreeBuffer = void Function(Pointer<Uint8> data);

typedef _NativeAckReceive =
    Void Function(Uint64 transport, Uint64 connection, Uint32 length);
typedef _DartAckReceive =
    void Function(int transport, int connection, int length);

/// Windows MsQuic transport used by the separated Server and AVACA
/// compositions. The native bridge is loaded only from the application
/// bundle, and every constructor is role-specific.
final class AvacaMsQuicTransport implements AvacaRemoteTransport {
  AvacaMsQuicTransport.server({
    required List<int> certificateSha1Thumbprint,
    required this.listenPort,
  }) : role = AvacaRemoteRole.server,
       _certificateSha1 = _exact(
         certificateSha1Thumbprint,
         20,
         'server certificate thumbprint',
       ),
       _certificateSha256Pin = null {
    _initialize();
  }

  AvacaMsQuicTransport.client({required List<int> certificateSha256Pin})
    : role = AvacaRemoteRole.client,
      listenPort = 0,
      _certificateSha1 = null,
      _certificateSha256Pin = _exact(
        certificateSha256Pin,
        32,
        'server certificate pin',
      ) {
    _initialize();
  }

  @override
  final AvacaRemoteRole role;
  final int listenPort;
  final Uint8List? _certificateSha1;
  final Uint8List? _certificateSha256Pin;

  late final _NativeQuicBindings _bindings;
  late final NativeCallable<_NativeEvent> _callback;
  late final Pointer<Void> _context;
  late final int _transport;

  final Map<int, _AvacaQuicConnection> _connections =
      <int, _AvacaQuicConnection>{};
  _AvacaQuicListener? _listener;
  AvacaRemoteConnectionHandler? _connectionHandler;
  bool _closing = false;
  bool _closed = false;

  @override
  Future<AvacaRemoteConnection> connect(AvacaRemoteEndpoint endpoint) async {
    _ensureOpen();
    if (role != AvacaRemoteRole.client) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'a Server transport cannot create an outbound connection',
      );
    }
    final host = endpoint.host.toNativeUtf8();
    final output = calloc<Uint64>();
    try {
      final status = _bindings.connect(_transport, host, endpoint.port, output);
      if (status != 0 || output.value == 0) {
        throw _nativeError(
          status,
          AvacaRemoteFailureCode.connectionFailed,
          'remote QUIC connection start failed',
        );
      }
      final connection = _connections.putIfAbsent(
        output.value,
        () => _AvacaQuicConnection(this, output.value),
      );
      try {
        await connection._waitUntilConnected(
          AvacaRemoteLimits.connectionTimeout,
        );
        return connection;
      } on TimeoutException {
        await connection.close();
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.timeout,
          'remote QUIC connection timed out',
        );
      } on Object {
        await connection.close();
        rethrow;
      }
    } finally {
      calloc.free(output);
      calloc.free(host);
    }
  }

  @override
  Future<AvacaRemoteListener> listen(
    AvacaRemoteConnectionHandler onConnection,
  ) async {
    _ensureOpen();
    if (role != AvacaRemoteRole.server) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'a client transport cannot start a Server listener',
      );
    }
    if (listenPort <= 0 || listenPort > 65535) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidInput,
        'a fixed listen port is required for the Server transport',
      );
    }
    if (_listener != null) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'remote QUIC listener is already open',
      );
    }
    _connectionHandler = onConnection;
    final output = calloc<Uint64>();
    try {
      final status = _bindings.listen(_transport, listenPort, output);
      if (status != 0 || output.value == 0) {
        _connectionHandler = null;
        throw _nativeError(
          status,
          AvacaRemoteFailureCode.connectionFailed,
          'remote QUIC listener could not be started',
        );
      }
      final listener = _AvacaQuicListener(this, output.value);
      _listener = listener;
      return listener;
    } finally {
      calloc.free(output);
    }
  }

  @override
  Future<void> close() async {
    if (_closed || _closing) return;
    _closing = true;
    final listener = _listener;
    _listener = null;
    try {
      await listener?.close();
    } on Object {
      // Continue closing connections; native transport close is authoritative.
    }
    final connections = _connections.values.toList(growable: false);
    for (final connection in connections) {
      try {
        await connection.close();
      } on Object {
        // Registration close below remains authoritative for cleanup.
      }
    }
    _bindings.close(_transport);
    _closed = true;
    _connectionHandler = null;
    _connections.clear();
    _callback.close();
    calloc.free(_context);
  }

  void _initialize() {
    if (!Platform.isWindows) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.unsupported,
        'the MsQuic transport is only available on Windows',
      );
    }
    _bindings = _NativeQuicBindings.open();
    _callback = NativeCallable<_NativeEvent>.listener(_handleNativeEvent);
    _context = calloc<Uint8>(1).cast<Void>();
    final output = calloc<Uint64>();
    final certificate = _certificateSha1 ?? _certificateSha256Pin!;
    final nativeCertificate = calloc<Uint8>(certificate.length);
    try {
      nativeCertificate.asTypedList(certificate.length).setAll(0, certificate);
      final status = role == AvacaRemoteRole.server
          ? _bindings.createServer(
              nativeCertificate,
              certificate.length,
              _callback.nativeFunction,
              _context,
              output,
            )
          : _bindings.createClient(
              nativeCertificate,
              certificate.length,
              _callback.nativeFunction,
              _context,
              output,
            );
      if (status != 0 || output.value == 0) {
        throw _nativeError(
          status,
          AvacaRemoteFailureCode.unsupported,
          'the configured MsQuic bridge could not be initialized',
        );
      }
      _transport = output.value;
    } on Object {
      _callback.close();
      calloc.free(_context);
      rethrow;
    } finally {
      nativeCertificate
          .asTypedList(certificate.length)
          .fillRange(0, certificate.length, 0);
      calloc.free(nativeCertificate);
      calloc.free(output);
    }
  }

  void _handleNativeEvent(
    Pointer<Void> context,
    int object,
    int event,
    int status,
    int operation,
    Pointer<Uint8> data,
    int length,
    int flags,
  ) {
    if (context.address != _context.address || object == 0) {
      _freeBuffer(data);
      return;
    }
    final incoming =
        event == _NativeQuicBindings.connectedEvent &&
        !_connections.containsKey(object);
    final connection =
        _connections[object] ??
        (incoming
            ? (_connections[object] = _AvacaQuicConnection(this, object))
            : null);
    if (connection == null) {
      if (event == _NativeQuicBindings.dataEvent) {
        _ackReceive(object, length);
      }
      _freeBuffer(data);
      return;
    }
    late final Uint8List payload;
    try {
      payload = _copyAndFree(data, length);
    } on Object {
      if (event == _NativeQuicBindings.dataEvent) {
        _ackReceive(object, length);
      }
      unawaited(connection.close());
      return;
    }
    if (event == _NativeQuicBindings.dataEvent) {
      _ackReceive(object, length);
    }
    switch (event) {
      case _NativeQuicBindings.connectedEvent:
        connection._onConnected(payload);
        if (incoming) {
          final handler = _connectionHandler;
          if (handler != null) {
            unawaited(_dispatchIncoming(handler, connection));
          } else {
            unawaited(connection.close());
          }
        }
      case _NativeQuicBindings.dataEvent:
        connection._onData(payload, flags);
      case _NativeQuicBindings.sendCompleteEvent:
        connection._onSendComplete(operation, status);
      case _NativeQuicBindings.closedEvent:
        connection._onClosed(status);
        _connections.remove(object);
      case _NativeQuicBindings.errorEvent:
        connection._onError(status);
    }
  }

  Future<void> _dispatchIncoming(
    AvacaRemoteConnectionHandler handler,
    _AvacaQuicConnection connection,
  ) async {
    try {
      await handler(connection);
    } on Object {
      await connection.close();
    }
  }

  Uint8List _copyAndFree(Pointer<Uint8> data, int length) {
    if (data.address == 0) {
      if (length != 0) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.internal,
          'native QUIC event has a missing data buffer',
        );
      }
      return Uint8List(0);
    }
    try {
      if (length > AvacaRemoteLimits.maxBufferedBytes) {
        throw const AvacaRemoteException(
          AvacaRemoteFailureCode.frameTooLarge,
          'native QUIC event exceeds the session buffer bound',
        );
      }
      return Uint8List.fromList(data.asTypedList(length));
    } finally {
      _freeBuffer(data);
    }
  }

  void _freeBuffer(Pointer<Uint8> data) {
    if (data.address != 0) _bindings.freeBuffer(data);
  }

  void _ackReceive(int connection, int length) {
    if (!_closed && length > 0) {
      _bindings.ackReceive(_transport, connection, length);
    }
  }

  int _send(int connection, Pointer<Uint8> data, int length, int operation) {
    _ensureOpen();
    return _bindings.send(connection, data, length, operation);
  }

  int _closeConnection(int connection) {
    if (_closed) return 0;
    return _bindings.closeConnection(connection);
  }

  int _closeListener(int listener) {
    if (_closed) return 0;
    return _bindings.closeListener(_transport, listener);
  }

  void _ensureOpen() {
    if (_closed || _closing) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'remote QUIC transport is closed',
      );
    }
  }

  static Uint8List _exact(List<int> bytes, int length, String name) {
    if (bytes.length != length) {
      throw AvacaRemoteException(
        AvacaRemoteFailureCode.invalidInput,
        '$name must contain exactly $length bytes',
      );
    }
    return Uint8List.fromList(bytes);
  }
}

final class AvacaMsQuicTransportFactory implements AvacaRemoteTransportFactory {
  const AvacaMsQuicTransportFactory();

  @override
  Future<AvacaRemoteTransport> createServer(
    AvacaRemoteServerConfig config,
  ) async {
    return AvacaMsQuicTransport.server(
      certificateSha1Thumbprint: config.certificateSha1Thumbprint,
      listenPort: config.listenPort,
    );
  }

  @override
  Future<AvacaRemoteTransport> createClient(
    AvacaRemoteClientConfig config,
  ) async {
    return AvacaMsQuicTransport.client(
      certificateSha256Pin: config.certificateSha256Pin,
    );
  }
}

final class _NativeQuicBindings {
  _NativeQuicBindings(DynamicLibrary library)
    : createServer = library
          .lookupFunction<_NativeCreateServer, _DartCreateServer>(
            'avaca_remote_quic_create_server',
          ),
      createClient = library
          .lookupFunction<_NativeCreateClient, _DartCreateClient>(
            'avaca_remote_quic_create_client',
          ),
      listen = library.lookupFunction<_NativeListen, _DartListen>(
        'avaca_remote_quic_listen',
      ),
      connect = library.lookupFunction<_NativeConnect, _DartConnect>(
        'avaca_remote_quic_connect',
      ),
      send = library.lookupFunction<_NativeSend, _DartSend>(
        'avaca_remote_quic_send',
      ),
      closeConnection = library
          .lookupFunction<_NativeCloseConnection, _DartCloseConnection>(
            'avaca_remote_quic_close_connection',
          ),
      closeListener = library
          .lookupFunction<_NativeCloseListener, _DartCloseListener>(
            'avaca_remote_quic_close_listener',
          ),
      close = library.lookupFunction<_NativeClose, _DartClose>(
        'avaca_remote_quic_close',
      ),
      freeBuffer = library.lookupFunction<_NativeFreeBuffer, _DartFreeBuffer>(
        'avaca_remote_quic_free_buffer',
      ),
      ackReceive = library.lookupFunction<_NativeAckReceive, _DartAckReceive>(
        'avaca_remote_quic_ack_receive',
      );

  static const connectedEvent = 1;
  static const dataEvent = 2;
  static const sendCompleteEvent = 3;
  static const closedEvent = 4;
  static const errorEvent = 5;

  final _DartCreateServer createServer;
  final _DartCreateClient createClient;
  final _DartListen listen;
  final _DartConnect connect;
  final _DartSend send;
  final _DartCloseConnection closeConnection;
  final _DartCloseListener closeListener;
  final _DartClose close;
  final _DartFreeBuffer freeBuffer;
  final _DartAckReceive ackReceive;

  static _NativeQuicBindings open() {
    try {
      final directory = File(Platform.resolvedExecutable).parent.path;
      final path = '$directory${Platform.pathSeparator}avaca_remote_quic.dll';
      return _NativeQuicBindings(DynamicLibrary.open(path));
    } on Object {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.unsupported,
        'the AVACA MsQuic bridge is not present beside the app',
      );
    }
  }
}

final class _AvacaQuicListener implements AvacaRemoteListener {
  _AvacaQuicListener(this._transport, this._handle);

  final AvacaMsQuicTransport _transport;
  final int _handle;
  bool _closed = false;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _transport._listener = null;
    final status = _transport._closeListener(_handle);
    if (status != 0) {
      throw _nativeError(
        status,
        AvacaRemoteFailureCode.connectionFailed,
        'remote QUIC listener close failed',
      );
    }
  }
}

final class _AvacaQuicConnection implements AvacaRemoteConnection {
  _AvacaQuicConnection(this._transport, this._handle) {
    _incoming = StreamController<Uint8List>(
      sync: false,
      onListen: _drainIncoming,
      onResume: _drainIncoming,
      onPause: () => _incomingPaused = true,
      onCancel: _clearIncoming,
    );
  }

  final AvacaMsQuicTransport _transport;
  final int _handle;
  late final StreamController<Uint8List> _incoming;
  final Queue<Uint8List> _incomingQueue = Queue<Uint8List>();
  final Completer<void> _connected = Completer<void>();
  final Completer<Uint8List> _channelBinding = Completer<Uint8List>();
  final Completer<void> _closed = Completer<void>();
  final Map<int, ({Completer<void> done, int length})> _writes =
      <int, ({Completer<void> done, int length})>{};

  bool _open = false;
  bool _closeRequested = false;
  bool _incomingPaused = false;
  bool _draining = false;
  int _bufferedBytes = 0;
  int _incomingBytes = 0;
  int _nextOperation = 1;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  bool get isOpen => _open && !_closed.isCompleted;

  @override
  Future<Uint8List> get channelBinding => _channelBinding.future;

  Future<void> _waitUntilConnected(Duration timeout) =>
      _connected.future.timeout(timeout);

  @override
  Future<void> write(Uint8List bytes) async {
    if (!isOpen) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.invalidState,
        'remote QUIC connection is not open',
      );
    }
    if (bytes.isEmpty || bytes.length > AvacaRemoteLimits.maxFrameBytes + 16) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.frameTooLarge,
        'remote QUIC write is outside the frame bound',
      );
    }
    if (_bufferedBytes > AvacaRemoteLimits.maxBufferedBytes - bytes.length) {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.frameTooLarge,
        'remote QUIC pending writes exceed the session bound',
      );
    }
    final operation = _nextOperation++;
    final done = Completer<void>();
    _writes[operation] = (done: done, length: bytes.length);
    _bufferedBytes += bytes.length;
    final nativeBytes = calloc<Uint8>(bytes.length);
    try {
      nativeBytes.asTypedList(bytes.length).setAll(0, bytes);
      final status = _transport._send(
        _handle,
        nativeBytes,
        bytes.length,
        operation,
      );
      if (status != 0) {
        _writes.remove(operation);
        _bufferedBytes -= bytes.length;
        throw _nativeError(
          status,
          AvacaRemoteFailureCode.connectionFailed,
          'remote QUIC write could not be queued',
        );
      }
    } finally {
      nativeBytes.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      calloc.free(nativeBytes);
    }
    await done.future;
  }

  @override
  Future<void> close() async {
    if (_closed.isCompleted) return;
    if (!_closeRequested) {
      _closeRequested = true;
      final status = _transport._closeConnection(_handle);
      if (status != 0) {
        _onError(status);
        _onClosed(status);
      }
    }
    try {
      await _closed.future.timeout(AvacaRemoteLimits.connectionTimeout);
    } on TimeoutException {
      throw const AvacaRemoteException(
        AvacaRemoteFailureCode.timeout,
        'remote QUIC connection close timed out',
      );
    }
  }

  void _onConnected(Uint8List binding) {
    if (_connected.isCompleted || _closed.isCompleted) return;
    if (binding.length != 32) {
      _onError(-1);
      return;
    }
    _open = true;
    _channelBinding.complete(Uint8List.fromList(binding));
    _connected.complete();
  }

  void _onData(Uint8List data, int flags) {
    if (!isOpen) return;
    if (data.isNotEmpty) {
      if (data.length > AvacaRemoteLimits.maxBufferedBytes ||
          _incomingBytes > AvacaRemoteLimits.maxBufferedBytes - data.length) {
        _onError(-1);
        unawaited(close());
        return;
      }
      _incomingQueue.add(data);
      _incomingBytes += data.length;
      _drainIncoming();
    }
    if ((flags & 1) != 0) unawaited(_incoming.close());
  }

  void _onSendComplete(int operation, int status) {
    final pending = _writes.remove(operation);
    if (pending == null) return;
    _bufferedBytes -= pending.length;
    if (_bufferedBytes < 0) _bufferedBytes = 0;
    if (status == 0) {
      pending.done.complete();
    } else {
      pending.done.completeError(
        _nativeError(
          status,
          AvacaRemoteFailureCode.connectionFailed,
          'remote QUIC write was cancelled',
        ),
      );
    }
  }

  void _onError(int status) {
    final error = _nativeError(
      status,
      AvacaRemoteFailureCode.connectionFailed,
      'remote QUIC connection reported a transport error',
    );
    if (!_connected.isCompleted) _connected.completeError(error);
    if (!_channelBinding.isCompleted) _channelBinding.completeError(error);
    for (final pending in _writes.values) {
      if (!pending.done.isCompleted) pending.done.completeError(error);
    }
    _writes.clear();
    _bufferedBytes = 0;
  }

  void _onClosed(int status) {
    if (_closed.isCompleted) return;
    _open = false;
    if (!_connected.isCompleted) {
      _connected.completeError(
        _nativeError(
          status,
          AvacaRemoteFailureCode.connectionFailed,
          'remote QUIC connection closed before setup',
        ),
      );
    }
    if (!_channelBinding.isCompleted) {
      _channelBinding.completeError(
        const AvacaRemoteException(
          AvacaRemoteFailureCode.connectionFailed,
          'remote QUIC connection closed before channel binding',
        ),
      );
    }
    final error = _nativeError(
      status,
      AvacaRemoteFailureCode.connectionFailed,
      'remote QUIC connection closed',
    );
    for (final pending in _writes.values) {
      if (!pending.done.isCompleted) pending.done.completeError(error);
    }
    _writes.clear();
    _bufferedBytes = 0;
    _clearIncoming();
    _closed.complete();
    unawaited(_incoming.close());
  }

  void _drainIncoming() {
    if (_incomingPaused || _draining) return;
    _draining = true;
    try {
      while (_incomingQueue.isNotEmpty && !_incomingPaused) {
        final data = _incomingQueue.removeFirst();
        _incomingBytes -= data.length;
        if (_incomingBytes < 0) _incomingBytes = 0;
        _incoming.add(data);
      }
    } finally {
      _draining = false;
    }
  }

  void _clearIncoming() {
    _incomingQueue.clear();
    _incomingBytes = 0;
  }
}

AvacaRemoteException _nativeError(
  int status,
  AvacaRemoteFailureCode fallback,
  String message,
) {
  if (status == 0x80070057 || status == -2147024809) {
    return const AvacaRemoteException(
      AvacaRemoteFailureCode.invalidInput,
      'native QUIC input was rejected',
    );
  }
  if (status == 0x80004002 || status == -2147467262) {
    return const AvacaRemoteException(
      AvacaRemoteFailureCode.unsupported,
      'native QUIC operation is unavailable',
    );
  }
  return AvacaRemoteException(fallback, message);
}
