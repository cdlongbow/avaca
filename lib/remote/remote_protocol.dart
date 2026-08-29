import 'dart:typed_data';

import 'remote_bytes.dart';
import 'remote_errors.dart';
import 'remote_limits.dart';
import 'remote_media.dart';

enum RemoteFramePhase { preAuth, auth, application }

enum RemoteCommand {
  clientHello,
  serverHello,
  authenticate,
  authenticated,
  openResource,
  resourceOpened,
  readResource,
  resourceChunk,
  cancelRead,
  closeResource,
  ping,
  pong,
  error,
}

class RemoteFrame {
  const RemoteFrame({
    required this.command,
    required this.flags,
    required this.requestId,
    required this.payload,
    this.version = RemoteLimits.protocolVersion,
  });

  final int version;
  final RemoteCommand command;
  final int flags;
  final int requestId;
  final List<int> payload;
}

class RemoteFrameCodec {
  const RemoteFrameCodec();

  static const headerLength = 16;

  Uint8List encode(
    RemoteFrame frame, {
    RemoteFramePhase phase = RemoteFramePhase.application,
  }) {
    _checkHeader(frame);
    _checkPayloadLength(frame.payload.length, phase);
    final writer = RemoteByteWriter()
      ..writeUint8(frame.version)
      ..writeUint8(frame.command.index)
      ..writeUint16(frame.flags)
      ..writeUint32(frame.payload.length)
      ..writeUint64(frame.requestId);
    writer.writeBytes(frame.payload);
    return writer.takeBytes();
  }

  RemoteFrame decode(
    List<int> encoded, {
    RemoteFramePhase phase = RemoteFramePhase.application,
  }) {
    if (encoded.length < headerLength) {
      throw const RemoteException(
        RemoteFailureCode.truncatedFrame,
        'remote frame header is truncated',
      );
    }
    if (encoded.length > headerLength + _maxPayload(phase)) {
      throw const RemoteException(
        RemoteFailureCode.frameTooLarge,
        'remote frame exceeds the phase limit',
      );
    }
    final reader = RemoteByteReader(encoded);
    final version = reader.readUint8();
    final commandValue = reader.readUint8();
    final flags = reader.readUint16();
    final payloadLength = reader.readUint32();
    final requestId = reader.readUint64();
    _checkPayloadLength(payloadLength, phase);
    if (commandValue >= RemoteCommand.values.length) {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'remote command is unknown',
      );
    }
    if (version != RemoteLimits.protocolVersion) {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'remote protocol version is unsupported',
      );
    }
    if (reader.remaining != payloadLength) {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'remote frame length does not match its payload',
      );
    }
    return RemoteFrame(
      version: version,
      command: RemoteCommand.values[commandValue],
      flags: flags,
      requestId: requestId,
      payload: reader.readBytes(payloadLength, maxBytes: _maxPayload(phase)),
    );
  }

  void _checkHeader(RemoteFrame frame) {
    if (frame.version != RemoteLimits.protocolVersion ||
        frame.flags < 0 ||
        frame.flags > 0xffff ||
        frame.requestId < 0 ||
        frame.requestId > 0x7fffffffffffffff) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'remote frame header is invalid',
      );
    }
  }

  void _checkPayloadLength(int length, RemoteFramePhase phase) {
    if (length < 0 || length > _maxPayload(phase)) {
      throw const RemoteException(
        RemoteFailureCode.frameTooLarge,
        'remote frame payload exceeds the phase limit',
      );
    }
  }

  int _maxPayload(RemoteFramePhase phase) {
    return switch (phase) {
      RemoteFramePhase.preAuth => RemoteLimits.preAuthFrameBytes,
      RemoteFramePhase.auth => RemoteLimits.authFrameBytes,
      RemoteFramePhase.application => RemoteLimits.applicationFrameBytes,
    };
  }
}

class RemoteFrameDecoder {
  RemoteFrameDecoder({this.phase = RemoteFramePhase.application});

  final RemoteFramePhase phase;
  final RemoteFrameCodec _codec = const RemoteFrameCodec();
  Uint8List _buffer = Uint8List(0);

  List<RemoteFrame> add(List<int> chunk) {
    if (chunk.isEmpty) {
      return const <RemoteFrame>[];
    }
    if (chunk.length > RemoteLimits.maxBufferedBytesPerSession ||
        _buffer.length >
            RemoteLimits.maxBufferedBytesPerSession - chunk.length) {
      throw const RemoteException(
        RemoteFailureCode.frameTooLarge,
        'remote stream buffered bytes exceed the session limit',
      );
    }
    final declaredPayloadLength = _peekPayloadLength(chunk);
    if (declaredPayloadLength != null) {
      _checkPayloadLength(declaredPayloadLength);
    }
    final combined = Uint8List(_buffer.length + chunk.length);
    combined.setAll(0, _buffer);
    combined.setAll(_buffer.length, chunk);
    _buffer = combined;
    final frames = <RemoteFrame>[];
    while (_buffer.length >= RemoteFrameCodec.headerLength) {
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
          'streamed frame exceeds the phase limit',
        );
      }
      final frameLength = RemoteFrameCodec.headerLength + payloadLength;
      if (_buffer.length < frameLength) {
        break;
      }
      frames.add(_codec.decode(_buffer.sublist(0, frameLength), phase: phase));
      _buffer = Uint8List.fromList(_buffer.sublist(frameLength));
    }
    return frames;
  }

  int? _peekPayloadLength(List<int> chunk) {
    final available = _buffer.length + chunk.length;
    if (available < 8) {
      return null;
    }

    int byteAt(int index) {
      return index < _buffer.length
          ? _buffer[index]
          : chunk[index - _buffer.length];
    }

    return (byteAt(4) << 24) | (byteAt(5) << 16) | (byteAt(6) << 8) | byteAt(7);
  }

  void _checkPayloadLength(int length) {
    final maxPayload = switch (phase) {
      RemoteFramePhase.preAuth => RemoteLimits.preAuthFrameBytes,
      RemoteFramePhase.auth => RemoteLimits.authFrameBytes,
      RemoteFramePhase.application => RemoteLimits.applicationFrameBytes,
    };
    if (length > maxPayload) {
      throw const RemoteException(
        RemoteFailureCode.frameTooLarge,
        'streamed frame exceeds the phase limit',
      );
    }
  }

  void requireDone() {
    if (_buffer.isNotEmpty) {
      throw const RemoteException(
        RemoteFailureCode.truncatedFrame,
        'stream ended with a partial remote frame',
      );
    }
  }
}

enum RemoteProtocolState {
  idle,
  awaitingClientAuthentication,
  awaitingServerAuthentication,
  authenticated,
  closed,
  failed,
}

class RemoteProtocolSession {
  RemoteProtocolSession({required this.isServer});

  final bool isServer;
  RemoteProtocolState state = RemoteProtocolState.idle;
  int _applicationRequests = 0;

  int get applicationRequests => _applicationRequests;

  void accept(RemoteFrame frame) {
    if (state == RemoteProtocolState.closed ||
        state == RemoteProtocolState.failed) {
      throw const RemoteException(
        RemoteFailureCode.invalidState,
        'remote protocol session is closed',
      );
    }
    try {
      if (isServer) {
        _acceptServer(frame.command);
      } else {
        _acceptClient(frame.command);
      }
      if (_isApplicationRequest(frame.command)) {
        _applicationRequests++;
        if (_applicationRequests >
            RemoteLimits.maxAuthenticatedRequestsPerSession) {
          throw const RemoteException(
            RemoteFailureCode.frameTooLarge,
            'remote authenticated request budget is exhausted',
          );
        }
      }
    } on RemoteException {
      state = RemoteProtocolState.failed;
      rethrow;
    }
  }

  void close() => state = RemoteProtocolState.closed;

  void _acceptServer(RemoteCommand command) {
    switch (state) {
      case RemoteProtocolState.idle:
        _require(command, RemoteCommand.clientHello);
        state = RemoteProtocolState.awaitingClientAuthentication;
      case RemoteProtocolState.awaitingClientAuthentication:
        _require(command, RemoteCommand.authenticate);
        state = RemoteProtocolState.authenticated;
      case RemoteProtocolState.authenticated:
        _requireApplicationCommand(command, const <RemoteCommand>{
          RemoteCommand.openResource,
          RemoteCommand.readResource,
          RemoteCommand.cancelRead,
          RemoteCommand.closeResource,
          RemoteCommand.ping,
          RemoteCommand.pong,
        });
      case RemoteProtocolState.awaitingServerAuthentication:
      case RemoteProtocolState.closed:
      case RemoteProtocolState.failed:
        throw const RemoteException(
          RemoteFailureCode.invalidState,
          'server protocol state is invalid',
        );
    }
  }

  void _acceptClient(RemoteCommand command) {
    switch (state) {
      case RemoteProtocolState.idle:
        _require(command, RemoteCommand.serverHello);
        state = RemoteProtocolState.awaitingServerAuthentication;
      case RemoteProtocolState.awaitingServerAuthentication:
        _require(command, RemoteCommand.authenticated);
        state = RemoteProtocolState.authenticated;
      case RemoteProtocolState.authenticated:
        _requireApplicationCommand(command, const <RemoteCommand>{
          RemoteCommand.resourceOpened,
          RemoteCommand.resourceChunk,
          RemoteCommand.ping,
          RemoteCommand.pong,
          RemoteCommand.error,
        });
      case RemoteProtocolState.awaitingClientAuthentication:
      case RemoteProtocolState.closed:
      case RemoteProtocolState.failed:
        throw const RemoteException(
          RemoteFailureCode.invalidState,
          'client protocol state is invalid',
        );
    }
  }

  void _require(RemoteCommand actual, RemoteCommand expected) {
    if (actual != expected) {
      throw RemoteException(
        RemoteFailureCode.invalidState,
        'expected ${expected.name} in the current protocol state',
      );
    }
  }

  void _requireApplicationCommand(
    RemoteCommand command,
    Set<RemoteCommand> allowed,
  ) {
    if (!allowed.contains(command)) {
      throw const RemoteException(
        RemoteFailureCode.invalidState,
        'command is not allowed in the current protocol state',
      );
    }
  }

  bool _isApplicationRequest(RemoteCommand command) =>
      state == RemoteProtocolState.authenticated &&
      (command == RemoteCommand.openResource ||
          command == RemoteCommand.readResource ||
          command == RemoteCommand.cancelRead ||
          command == RemoteCommand.closeResource ||
          command == RemoteCommand.ping);
}

class RemoteProtocolPayloadCodec {
  const RemoteProtocolPayloadCodec();

  Uint8List encodeOpenResource(RemoteResourceId resourceId) {
    final writer = RemoteByteWriter();
    writer.writeLengthPrefixedBytes(
      resourceId.bytes,
      maxBytes: RemoteLimits.maxResourceIdBytes,
    );
    return writer.takeBytes();
  }

  RemoteResourceId decodeOpenResource(List<int> payload) {
    final reader = RemoteByteReader(payload);
    final id = RemoteResourceId(
      reader.readLengthPrefixedBytes(maxBytes: RemoteLimits.maxResourceIdBytes),
    );
    reader.requireDone();
    return id;
  }

  Uint8List encodeReadResource(
    RemoteResourceId resourceId,
    RemoteByteRange range,
  ) {
    if (range.offset < 0 ||
        range.length < 0 ||
        range.length > RemoteLimits.maxReadBytes ||
        range.offset > 0x7fffffffffffffff) {
      throw const RemoteException(
        RemoteFailureCode.rangeInvalid,
        'read range is invalid',
      );
    }
    final writer = RemoteByteWriter();
    writer.writeLengthPrefixedBytes(
      resourceId.bytes,
      maxBytes: RemoteLimits.maxResourceIdBytes,
    );
    writer.writeUint64(range.offset);
    writer.writeUint32(range.length);
    return writer.takeBytes();
  }

  ({RemoteResourceId resourceId, RemoteByteRange range}) decodeReadResource(
    List<int> payload,
  ) {
    final reader = RemoteByteReader(payload);
    final resourceId = RemoteResourceId(
      reader.readLengthPrefixedBytes(maxBytes: RemoteLimits.maxResourceIdBytes),
    );
    final range = RemoteByteRange(
      offset: reader.readUint64(),
      length: reader.readUint32(),
    );
    reader.requireDone();
    return (resourceId: resourceId, range: range);
  }

  Uint8List encodeResourceChunk(RemoteReadResult result) {
    if (result.offset < 0 ||
        result.bytes.length > RemoteLimits.maxReadBytes ||
        result.offset > 0x7fffffffffffffff) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'resource chunk is invalid',
      );
    }
    final writer = RemoteByteWriter()
      ..writeUint64(result.offset)
      ..writeUint8(result.eof ? 1 : 0);
    writer.writeLengthPrefixedBytes(
      result.bytes,
      maxBytes: RemoteLimits.maxReadBytes,
    );
    return writer.takeBytes();
  }

  RemoteReadResult decodeResourceChunk(List<int> payload) {
    final reader = RemoteByteReader(payload);
    final offset = reader.readUint64();
    final eof = reader.readUint8();
    if (eof > 1) {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'resource chunk EOF flag is invalid',
      );
    }
    final bytes = reader.readLengthPrefixedBytes(
      maxBytes: RemoteLimits.maxReadBytes,
    );
    reader.requireDone();
    return RemoteReadResult(offset: offset, bytes: bytes, eof: eof == 1);
  }
}
