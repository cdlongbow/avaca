import 'dart:convert';
import 'dart:typed_data';

export 'src/application_codec.dart';
export 'src/handshake.dart';

/// The separated application protocol.  Version 1 is intentionally not
/// accepted anywhere in this package; changing the application split also
/// changes the authentication transcript and ALPN.
abstract final class AvacaProtocol {
  static const version = 2;
  static const alpn = 'avaca-remote/2';
  static const exporterLabel = 'EXPORTER-AVACA-REMOTE-V2';
  static const preAuthContext = 'AVACA-REMOTE/PREAUTH/V2';
  static const discoveryContext = 'AVACA-REMOTE/DISCOVERY/V2';
  static const namespaceContext = 'AVACA-REMOTE/NAMESPACE/V2';
  static const pairingContextPrefix = 'AVACA-REMOTE/PAIR/V2/';
}

/// Explicit wire opcodes.  Never use enum declaration order as a wire value;
/// reserved gaps allow compatible additions without renumbering commands.
enum AvacaOpcode {
  clientHello(0x01),
  serverHello(0x02),
  authenticatePair(0x03),
  authenticatePlaybackGrant(0x04),
  authenticated(0x05),
  getCapabilities(0x10),
  capabilities(0x11),
  listCollection(0x20),
  collectionPage(0x21),
  getWorkDetail(0x22),
  workDetail(0x23),
  openAsset(0x24),
  assetOpened(0x25),
  createPlaybackSession(0x30),
  playbackSessionCreated(0x31),
  closePlaybackSession(0x32),
  playbackSessionClosed(0x33),
  openResource(0x40),
  resourceOpened(0x41),
  readResource(0x42),
  resourceChunk(0x43),
  cancelRead(0x44),
  closeResource(0x45),
  resourceClosed(0x46),
  ping(0x70),
  pong(0x71),
  error(0x7f);

  const AvacaOpcode(this.value);

  final int value;

  static AvacaOpcode? fromValue(int value) {
    for (final opcode in values) {
      if (opcode.value == value) return opcode;
    }
    return null;
  }
}

enum AvacaFramePhase { preAuth, auth, application }

class AvacaProtocolException implements Exception {
  const AvacaProtocolException(this.message);

  final String message;

  @override
  String toString() => 'AvacaProtocolException: $message';
}

class AvacaFrame {
  const AvacaFrame({
    required this.opcode,
    required this.requestId,
    required this.payload,
    this.flags = 0,
    this.version = AvacaProtocol.version,
  });

  final AvacaOpcode opcode;
  final int requestId;
  final List<int> payload;
  final int flags;
  final int version;
}

class AvacaFrameCodec {
  const AvacaFrameCodec();

  static const headerLength = 16;
  static const preAuthMax = 1024;
  static const authMax = 16 * 1024;
  static const applicationMax = 1024 * 1024;

  Uint8List encode(
    AvacaFrame frame, {
    AvacaFramePhase phase = AvacaFramePhase.application,
  }) {
    _checkHeader(frame);
    _checkPayload(frame.payload.length, phase);
    final bytes = ByteData(headerLength + frame.payload.length);
    bytes.setUint8(0, frame.version);
    bytes.setUint8(1, frame.opcode.value);
    bytes.setUint16(2, frame.flags, Endian.big);
    bytes.setUint32(4, frame.payload.length, Endian.big);
    bytes.setUint64(8, frame.requestId, Endian.big);
    final result = bytes.buffer.asUint8List();
    result.setRange(headerLength, result.length, frame.payload);
    return result;
  }

  AvacaFrame decode(
    List<int> wire, {
    AvacaFramePhase phase = AvacaFramePhase.application,
  }) {
    if (wire.length < headerLength) {
      throw const AvacaProtocolException('frame header is truncated');
    }
    final bytes = Uint8List.fromList(wire);
    final data = ByteData.sublistView(bytes);
    final version = data.getUint8(0);
    if (version != AvacaProtocol.version) {
      throw const AvacaProtocolException(
        'protocol v1 or another version is not supported',
      );
    }
    final opcode = AvacaOpcode.fromValue(data.getUint8(1));
    if (opcode == null) throw const AvacaProtocolException('opcode is unknown');
    final flags = data.getUint16(2, Endian.big);
    final length = data.getUint32(4, Endian.big);
    _checkPayload(length, phase);
    if (wire.length != headerLength + length) {
      throw const AvacaProtocolException(
        'declared frame length does not match wire length',
      );
    }
    final requestId = data.getUint64(8, Endian.big);
    return AvacaFrame(
      opcode: opcode,
      requestId: requestId,
      flags: flags,
      version: version,
      payload: Uint8List.fromList(bytes.sublist(headerLength)),
    );
  }

  void _checkHeader(AvacaFrame frame) {
    if (frame.version != AvacaProtocol.version ||
        frame.flags < 0 ||
        frame.flags > 0xffff ||
        frame.requestId < 0 ||
        frame.requestId > 0x7fffffffffffffff) {
      throw const AvacaProtocolException('frame header is invalid');
    }
  }

  void _checkPayload(int length, AvacaFramePhase phase) {
    final max = switch (phase) {
      AvacaFramePhase.preAuth => preAuthMax,
      AvacaFramePhase.auth => authMax,
      AvacaFramePhase.application => applicationMax,
    };
    if (length < 0 || length > max) {
      throw const AvacaProtocolException(
        'frame payload exceeds its phase bound',
      );
    }
  }
}

/// Deterministic vectors are kept as data rather than generated at runtime so
/// Dart, native C++, and future clients can compare bytes byte-for-byte.
String avacaGoldenVector(AvacaFrame frame) =>
    base64UrlEncode(const AvacaFrameCodec().encode(frame));
