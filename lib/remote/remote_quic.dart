import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'remote_endpoint.dart';
import 'remote_errors.dart';
import 'remote_limits.dart';
import 'remote_transport.dart';

typedef _NativeRemoteQuicEvent =
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
typedef _NativeCreate =
    Int32 Function(
      Pointer<Uint8> pinnedServerCertificateSha256,
      Uint32 pinnedServerCertificateSha256Length,
      Pointer<Uint8> serverCertificateSha1,
      Uint32 serverCertificateSha1Length,
      Pointer<NativeFunction<_NativeRemoteQuicEvent>> callback,
      Pointer<Void> context,
      Pointer<Uint64> transport,
    );
typedef _DartCreate =
    int Function(
      Pointer<Uint8> pinnedServerCertificateSha256,
      int pinnedServerCertificateSha256Length,
      Pointer<Uint8> serverCertificateSha1,
      int serverCertificateSha1Length,
      Pointer<NativeFunction<_NativeRemoteQuicEvent>> callback,
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

typedef _NativeAcknowledgeReceive =
    Void Function(Uint64 transport, Uint64 connection, Uint32 length);
typedef _DartAcknowledgeReceive =
    void Function(int transport, int connection, int length);

/// Optional Windows transport backed by the official MsQuic v2 API.
///
/// The bridge is intentionally not part of the default app composition. It is
/// constructed only when a build has been configured with a validated native
/// bridge and a pinned server certificate. No plaintext or accept-all fallback
/// is attempted when the bridge is absent.
class RemoteQuicTransport implements RemoteTransport {
  RemoteQuicTransport({
    required List<int> pinnedServerCertificateSha256,
    List<int>? serverCertificateSha1,
    this.listenPort = 0,
  }) : pinnedServerCertificateSha256 = _copyHash(
         pinnedServerCertificateSha256,
         RemoteLimits.channelBindingBytes,
         'server certificate pin',
       ),
       serverCertificateSha1 = serverCertificateSha1 == null
           ? null
           : _copyHash(
               serverCertificateSha1,
               20,
               'server certificate thumbprint',
             ) {
    if (!Platform.isWindows) {
      throw const RemoteException(
        RemoteFailureCode.unsupported,
        'the MsQuic transport is only available on Windows',
      );
    }
    if (listenPort < 0 || listenPort > RemoteLimits.maxEndpointPort) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'remote QUIC listen port is invalid',
      );
    }

    _bindings = _RemoteQuicBindings.open();
    _callback = NativeCallable<_NativeRemoteQuicEvent>.listener(
      _handleNativeEvent,
    );
    _context = calloc<Uint8>(1).cast<Void>();
    final pinned = calloc<Uint8>(pinnedServerCertificateSha256.length);
    final serverThumbprint = serverCertificateSha1 == null
        ? Pointer<Uint8>.fromAddress(0)
        : calloc<Uint8>(serverCertificateSha1.length);
    final output = calloc<Uint64>();
    try {
      pinned
          .asTypedList(pinnedServerCertificateSha256.length)
          .setAll(0, pinnedServerCertificateSha256);
      if (serverCertificateSha1 != null) {
        serverThumbprint
            .asTypedList(serverCertificateSha1.length)
            .setAll(0, serverCertificateSha1);
      }
      final status = _bindings.create(
        pinned,
        pinnedServerCertificateSha256.length,
        serverThumbprint,
        serverCertificateSha1?.length ?? 0,
        _callback.nativeFunction,
        _context,
        output,
      );
      if (status != 0) {
        throw _nativeError(
          status,
          RemoteFailureCode.unsupported,
          'the configured MsQuic bridge could not be initialized',
        );
      }
      _transportHandle = output.value;
    } on Object {
      _callback.close();
      calloc.free(_context);
      rethrow;
    } finally {
      calloc.free(pinned);
      if (serverCertificateSha1 != null) {
        calloc.free(serverThumbprint);
      }
      calloc.free(output);
    }
  }

  final Uint8List pinnedServerCertificateSha256;
  final Uint8List? serverCertificateSha1;
  final int listenPort;

  late final _RemoteQuicBindings _bindings;
  late final NativeCallable<_NativeRemoteQuicEvent> _callback;
  late final Pointer<Void> _context;
  late final int _transportHandle;

  final Map<int, _RemoteQuicConnection> _connections =
      <int, _RemoteQuicConnection>{};
  RemoteConnectionHandler? _connectionHandler;
  _RemoteQuicListener? _listener;
  bool _closing = false;
  bool _closed = false;

  @override
  Future<RemoteConnection> connect(
    RemoteEndpoint endpoint, {
    Duration timeout = RemoteLimits.connectionTimeout,
  }) async {
    _ensureOpen();
    final host = endpoint.host.toNativeUtf8();
    final output = calloc<Uint64>();
    try {
      final status = _bindings.connect(
        _transportHandle,
        host,
        endpoint.port,
        output,
      );
      if (status != 0 || output.value == 0) {
        throw _nativeError(
          status,
          RemoteFailureCode.connectionFailed,
          'remote QUIC connection start failed',
        );
      }
      final connection = _RemoteQuicConnection(this, output.value);
      _connections[output.value] = connection;
      try {
        await connection._waitUntilConnected(timeout);
        return connection;
      } on TimeoutException {
        await connection.close();
        throw const RemoteException(
          RemoteFailureCode.timeout,
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
  Future<RemoteListener> listen(RemoteConnectionHandler onConnection) async {
    _ensureOpen();
    if (listenPort == 0) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'a fixed listen port is required for the remote QUIC listener',
      );
    }
    if (_listener != null) {
      throw const RemoteException(
        RemoteFailureCode.invalidState,
        'remote QUIC listener is already open',
      );
    }
    _connectionHandler = onConnection;
    final output = calloc<Uint64>();
    try {
      final status = _bindings.listen(_transportHandle, listenPort, output);
      if (status != 0 || output.value == 0) {
        _connectionHandler = null;
        throw _nativeError(
          status,
          RemoteFailureCode.connectionFailed,
          'remote QUIC listener could not be started',
        );
      }
      final listener = _RemoteQuicListener(this, output.value);
      _listener = listener;
      return listener;
    } finally {
      calloc.free(output);
    }
  }

  @override
  Future<void> close() async {
    if (_closed || _closing) {
      return;
    }
    _closing = true;
    final listener = _listener;
    _listener = null;
    await listener?.close();
    final connections = _connections.values.toList(growable: false);
    for (final connection in connections) {
      try {
        await connection.close();
      } on Object {
        // The native registration close below is still required to drain all
        // child handles. The connection records remain owned by the native
        // callbacks until that close completes.
      }
    }
    _bindings.close(_transportHandle);
    _closed = true;
    _connections.clear();
    _callback.close();
    calloc.free(_context);
  }

  int _send(int connection, Pointer<Uint8> data, int length, int operation) {
    _ensureOpen();
    return _bindings.send(connection, data, length, operation);
  }

  int _closeConnection(int connection) {
    if (_closed) {
      return 0;
    }
    return _bindings.closeConnection(connection);
  }

  int _closeListener(int listener) {
    if (_closed) {
      return 0;
    }
    return _bindings.closeListener(_transportHandle, listener);
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
      _freeNativeBuffer(data);
      return;
    }
    final isConnectedEvent =
        event == _RemoteQuicBindings.connectedEvent &&
        !_connections.containsKey(object);
    final connection =
        _connections[object] ??
        (isConnectedEvent
            ? (_connections[object] = _RemoteQuicConnection(this, object))
            : null);
    if (connection == null) {
      if (event == _RemoteQuicBindings.dataEvent) {
        _acknowledgeReceive(object, length);
      }
      _freeNativeBuffer(data);
      return;
    }
    final receiveReserved =
        event != _RemoteQuicBindings.dataEvent ||
        connection._reserveIncoming(length);
    if (!receiveReserved) {
      _acknowledgeReceive(object, length);
      _freeNativeBuffer(data);
      return;
    }
    late final Uint8List payload;
    try {
      payload = _copyAndFreeNativeBuffer(data, length);
    } on Object {
      if (event == _RemoteQuicBindings.dataEvent) {
        connection._releaseIncoming(length);
      }
      rethrow;
    } finally {
      if (event == _RemoteQuicBindings.dataEvent) {
        _acknowledgeReceive(object, length);
      }
    }
    switch (event) {
      case _RemoteQuicBindings.connectedEvent:
        connection._onConnected(payload);
        if (isConnectedEvent) {
          final handler = _connectionHandler;
          if (handler != null) {
            unawaited(_dispatchIncoming(handler, connection));
          }
        }
        break;
      case _RemoteQuicBindings.dataEvent:
        connection._onData(payload, flags, reserved: true);
        break;
      case _RemoteQuicBindings.sendCompleteEvent:
        connection._onSendComplete(operation, status);
        break;
      case _RemoteQuicBindings.closedEvent:
        connection._onClosed(status);
        _connections.remove(object);
        break;
      case _RemoteQuicBindings.errorEvent:
        connection._onError(status);
        break;
    }
  }

  Future<void> _dispatchIncoming(
    RemoteConnectionHandler handler,
    _RemoteQuicConnection connection,
  ) async {
    try {
      await handler(connection);
    } on Object {
      await connection.close();
    }
  }

  Uint8List _copyAndFreeNativeBuffer(Pointer<Uint8> data, int length) {
    if (data.address == 0) {
      if (length != 0) {
        throw const RemoteException(
          RemoteFailureCode.internal,
          'native QUIC event has a missing data buffer',
        );
      }
      return Uint8List(0);
    }
    try {
      if (length > RemoteLimits.maxBufferedBytesPerSession) {
        throw const RemoteException(
          RemoteFailureCode.frameTooLarge,
          'native QUIC event exceeds the session buffer bound',
        );
      }
      return Uint8List.fromList(data.asTypedList(length));
    } finally {
      _freeNativeBuffer(data);
    }
  }

  void _freeNativeBuffer(Pointer<Uint8> data) {
    if (data.address != 0) {
      _bindings.freeBuffer(data);
    }
  }

  void _acknowledgeReceive(int object, int length) {
    if (!_closed && length > 0) {
      _bindings.acknowledgeReceive(_transportHandle, object, length);
    }
  }

  void _ensureOpen() {
    if (_closed || _closing) {
      throw const RemoteException(
        RemoteFailureCode.invalidState,
        'remote QUIC transport is closed',
      );
    }
  }

  static Uint8List _copyHash(List<int> value, int length, String name) {
    if (value.length != length) {
      throw RemoteException(
        RemoteFailureCode.invalidInput,
        '$name must contain exactly $length bytes',
      );
    }
    return Uint8List.fromList(value);
  }
}

class _RemoteQuicBindings {
  _RemoteQuicBindings(DynamicLibrary library)
    : create = library.lookupFunction<_NativeCreate, _DartCreate>(
        'avaca_remote_quic_create',
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
      acknowledgeReceive = library
          .lookupFunction<_NativeAcknowledgeReceive, _DartAcknowledgeReceive>(
            'avaca_remote_quic_ack_receive',
          );

  static const connectedEvent = 1;
  static const dataEvent = 2;
  static const sendCompleteEvent = 3;
  static const closedEvent = 4;
  static const errorEvent = 5;

  final _DartCreate create;
  final _DartListen listen;
  final _DartConnect connect;
  final _DartSend send;
  final _DartCloseConnection closeConnection;
  final _DartCloseListener closeListener;
  final _DartClose close;
  final _DartFreeBuffer freeBuffer;
  final _DartAcknowledgeReceive acknowledgeReceive;

  static _RemoteQuicBindings open() {
    try {
      final executableDirectory = File(Platform.resolvedExecutable).parent.path;
      final path =
          '$executableDirectory${Platform.pathSeparator}avaca_remote_quic.dll';
      return _RemoteQuicBindings(DynamicLibrary.open(path));
    } on Object {
      throw const RemoteException(
        RemoteFailureCode.unsupported,
        'the optional AVACA MsQuic bridge is not present beside the app',
      );
    }
  }
}

class _RemoteQuicListener implements RemoteListener {
  _RemoteQuicListener(this._transport, this._handle);

  final RemoteQuicTransport _transport;
  final int _handle;
  bool _closed = false;

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _transport._listener = null;
    final status = _transport._closeListener(_handle);
    if (status != 0) {
      throw _nativeError(
        status,
        RemoteFailureCode.connectionFailed,
        'remote QUIC listener close failed',
      );
    }
  }
}

class _RemoteQuicConnection implements RemoteConnection {
  _RemoteQuicConnection(this._transport, this._handle) {
    _incoming = StreamController<List<int>>(
      sync: true,
      onListen: _onIncomingListen,
      onPause: _onIncomingPause,
      onResume: _onIncomingResume,
      onCancel: _onIncomingCancel,
    );
  }

  final RemoteQuicTransport _transport;
  final int _handle;
  late final StreamController<List<int>> _incoming;
  final Queue<Uint8List> _incomingQueue = Queue<Uint8List>();
  final Completer<void> _connected = Completer<void>();
  final Completer<Uint8List> _channelBinding = Completer<Uint8List>();
  final Completer<void> _closed = Completer<void>();
  final Map<int, ({Completer<void> completion, int length})> _writes =
      <int, ({Completer<void> completion, int length})>{};

  bool _open = false;
  bool _closeRequested = false;
  bool _incomingListenerActive = false;
  bool _incomingPaused = false;
  bool _drainingIncoming = false;
  bool _incomingOverflowed = false;
  int _incomingBufferedBytes = 0;
  int _bufferedBytes = 0;
  int _nextOperation = 1;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  bool get isOpen => _open && !_closed.isCompleted;

  @override
  Future<Uint8List> get channelBinding => _channelBinding.future;

  Future<void> _waitUntilConnected(Duration timeout) {
    return _connected.future.timeout(timeout);
  }

  @override
  Future<void> write(List<int> bytes) async {
    if (!isOpen) {
      throw const RemoteException(
        RemoteFailureCode.invalidState,
        'remote QUIC connection is not open',
      );
    }
    if (bytes.isEmpty ||
        bytes.length > RemoteLimits.applicationFrameBytes + 16) {
      throw const RemoteException(
        RemoteFailureCode.frameTooLarge,
        'remote QUIC write is outside the application frame bound',
      );
    }
    if (_bufferedBytes >
        RemoteLimits.maxBufferedBytesPerSession - bytes.length) {
      throw const RemoteException(
        RemoteFailureCode.frameTooLarge,
        'remote QUIC pending writes exceed the session buffer bound',
      );
    }
    final operation = _nextOperation++;
    final completion = Completer<void>();
    _writes[operation] = (completion: completion, length: bytes.length);
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
          RemoteFailureCode.connectionFailed,
          'remote QUIC write could not be queued',
        );
      }
    } finally {
      nativeBytes.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      calloc.free(nativeBytes);
    }
    await completion.future;
  }

  @override
  Future<void> close() async {
    if (_closed.isCompleted) {
      return;
    }
    if (!_closeRequested) {
      _closeRequested = true;
      final status = _transport._closeConnection(_handle);
      if (status != 0) {
        _onError(status);
        _onClosed(status);
      }
    }
    try {
      await _closed.future.timeout(RemoteLimits.connectionTimeout);
    } on TimeoutException {
      throw const RemoteException(
        RemoteFailureCode.timeout,
        'remote QUIC connection close timed out',
      );
    }
  }

  void _onConnected(Uint8List binding) {
    if (_connected.isCompleted || _closed.isCompleted) {
      return;
    }
    if (binding.length != RemoteLimits.channelBindingBytes) {
      _onError(0);
      return;
    }
    _open = true;
    _channelBinding.complete(Uint8List.fromList(binding));
    _connected.complete();
  }

  bool _reserveIncoming(int length) {
    if (!isOpen || _incomingOverflowed) {
      return false;
    }
    if (length == 0) {
      return true;
    }
    if (_incomingBufferedBytes >
        RemoteLimits.maxBufferedBytesPerSession - length) {
      _rejectIncomingOverflow();
      return false;
    }
    _incomingBufferedBytes += length;
    return true;
  }

  void _releaseIncoming(int length) {
    if (length == 0) {
      return;
    }
    _incomingBufferedBytes -= length;
    if (_incomingBufferedBytes < 0) {
      _incomingBufferedBytes = 0;
    }
  }

  void _onData(Uint8List data, int flags, {bool reserved = false}) {
    if (!isOpen || _incomingOverflowed) {
      if (reserved) {
        _releaseIncoming(data.length);
      }
      return;
    }
    if (data.isNotEmpty) {
      if (!reserved && !_reserveIncoming(data.length)) {
        return;
      }
      _incomingQueue.add(data);
      _drainIncoming();
    }
    if ((flags & 1) != 0) {
      unawaited(_incoming.close());
    }
  }

  void _onSendComplete(int operation, int status) {
    final pending = _writes.remove(operation);
    if (pending == null) {
      return;
    }
    _bufferedBytes -= pending.length;
    if (_bufferedBytes < 0) {
      _bufferedBytes = 0;
    }
    if (status == 0) {
      pending.completion.complete();
    } else {
      pending.completion.completeError(
        _nativeError(
          status,
          RemoteFailureCode.connectionFailed,
          'remote QUIC write was cancelled',
        ),
      );
    }
  }

  void _onError(int status) {
    final error = _nativeError(
      status,
      RemoteFailureCode.connectionFailed,
      'remote QUIC connection reported a transport error',
    );
    if (!_connected.isCompleted) {
      _connected.completeError(error, StackTrace.current);
    }
    if (!_channelBinding.isCompleted) {
      _channelBinding.completeError(error, StackTrace.current);
    }
    for (final pending in _writes.values) {
      if (!pending.completion.isCompleted) {
        pending.completion.completeError(error, StackTrace.current);
      }
    }
    _writes.clear();
    _bufferedBytes = 0;
  }

  void _onIncomingListen() {
    _incomingListenerActive = true;
    _drainIncoming();
  }

  void _onIncomingPause() {
    _incomingPaused = true;
  }

  void _onIncomingResume() {
    _incomingPaused = false;
    _drainIncoming();
  }

  void _onIncomingCancel() {
    _incomingListenerActive = false;
    _clearIncomingQueue();
  }

  void _drainIncoming() {
    if (!_incomingListenerActive || _incomingPaused || _drainingIncoming) {
      return;
    }
    _drainingIncoming = true;
    try {
      while (_incomingQueue.isNotEmpty &&
          _incomingListenerActive &&
          !_incomingPaused) {
        final data = _incomingQueue.removeFirst();
        _incomingBufferedBytes -= data.length;
        if (_incomingBufferedBytes < 0) {
          _incomingBufferedBytes = 0;
        }
        _incoming.add(data);
      }
    } finally {
      _drainingIncoming = false;
    }
  }

  void _clearIncomingQueue() {
    _incomingQueue.clear();
    _incomingBufferedBytes = 0;
  }

  void _rejectIncomingOverflow() {
    if (_incomingOverflowed) {
      return;
    }
    _incomingOverflowed = true;
    _clearIncomingQueue();
    _incoming.addError(
      const RemoteException(
        RemoteFailureCode.frameTooLarge,
        'remote QUIC inbound data exceeded the session buffer bound',
      ),
    );
    unawaited(_closeQuietly());
  }

  Future<void> _closeQuietly() async {
    try {
      await close();
    } on Object {
      // The native close callback will finish the stream lifecycle.
    }
  }

  void _onClosed(int status) {
    if (_closed.isCompleted) {
      return;
    }
    _open = false;
    if (!_connected.isCompleted) {
      final error = _nativeError(
        status,
        RemoteFailureCode.connectionFailed,
        'remote QUIC connection closed before authentication transport setup',
      );
      _connected.completeError(error, StackTrace.current);
    }
    if (!_channelBinding.isCompleted) {
      _channelBinding.completeError(
        const RemoteException(
          RemoteFailureCode.connectionFailed,
          'remote QUIC connection closed before channel binding was available',
        ),
        StackTrace.current,
      );
    }
    final error = _nativeError(
      status,
      RemoteFailureCode.connectionFailed,
      'remote QUIC connection closed',
    );
    for (final pending in _writes.values) {
      if (!pending.completion.isCompleted) {
        pending.completion.completeError(error, StackTrace.current);
      }
    }
    _writes.clear();
    _bufferedBytes = 0;
    _clearIncomingQueue();
    _closed.complete();
    unawaited(_incoming.close());
  }
}

RemoteException _nativeError(
  int status,
  RemoteFailureCode fallback,
  String message,
) {
  if (status == 0x80004002 || status == -2147467262) {
    return RemoteException(RemoteFailureCode.unsupported, message);
  }
  if (status == 0x80070057 || status == -2147024809) {
    return RemoteException(RemoteFailureCode.invalidInput, message);
  }
  return RemoteException(fallback, message);
}
