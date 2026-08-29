import 'dart:math' as math;
import 'dart:typed_data';

import 'remote_errors.dart';

abstract interface class RemoteClock {
  DateTime get now;
}

class SystemRemoteClock implements RemoteClock {
  const SystemRemoteClock();

  @override
  DateTime get now => DateTime.now().toUtc();
}

abstract interface class RemoteRandom {
  Uint8List bytes(int length);
}

class SecureRemoteRandom implements RemoteRandom {
  SecureRemoteRandom([math.Random? random])
    : _random = random ?? math.Random.secure();

  final math.Random _random;

  @override
  Uint8List bytes(int length) {
    if (length < 0) {
      throw ArgumentError.value(length, 'length');
    }
    final output = Uint8List(length);
    for (var index = 0; index < output.length; index++) {
      output[index] = _random.nextInt(256);
    }
    return output;
  }
}

bool remoteConstantTimeEquals(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final length = math.max(left.length, right.length);
  for (var index = 0; index < length; index++) {
    final leftByte = index < left.length ? left[index] : 0;
    final rightByte = index < right.length ? right[index] : 0;
    difference |= leftByte ^ rightByte;
  }
  return difference == 0;
}

class RemoteByteWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void writeUint8(int value) {
    _checkUnsigned(value, 0xff, 'uint8');
    _builder.add(<int>[value]);
  }

  void writeUint16(int value) {
    _checkUnsigned(value, 0xffff, 'uint16');
    _builder.add(<int>[(value >> 8) & 0xff, value & 0xff]);
  }

  void writeUint32(int value) {
    _checkUnsigned(value, 0xffffffff, 'uint32');
    _builder.add(<int>[
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ]);
  }

  void writeUint64(int value) {
    if (value < 0 || value > 0x7fffffffffffffff) {
      throw ArgumentError.value(
        value,
        'value',
        'must be an unsigned 63-bit integer',
      );
    }
    for (var shift = 56; shift >= 0; shift -= 8) {
      _builder.add(<int>[(value >> shift) & 0xff]);
    }
  }

  void writeBytes(List<int> bytes) => _builder.add(bytes);

  void writeLengthPrefixedBytes(List<int> bytes, {required int maxBytes}) {
    if (bytes.length > maxBytes || bytes.length > 0xffff) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'length-prefixed bytes exceed the configured bound',
      );
    }
    writeUint16(bytes.length);
    writeBytes(bytes);
  }

  Uint8List takeBytes() => _builder.takeBytes();

  static void _checkUnsigned(int value, int maximum, String name) {
    if (value < 0 || value > maximum) {
      throw ArgumentError.value(value, name);
    }
  }
}

class RemoteByteReader {
  RemoteByteReader(List<int> input) : _bytes = Uint8List.fromList(input);

  final Uint8List _bytes;
  int _offset = 0;

  int get offset => _offset;
  int get remaining => _bytes.length - _offset;
  bool get isDone => _offset == _bytes.length;

  int readUint8() {
    _ensure(1);
    return _bytes[_offset++];
  }

  int readUint16() {
    _ensure(2);
    final value = (_bytes[_offset] << 8) | _bytes[_offset + 1];
    _offset += 2;
    return value;
  }

  int readUint32() {
    _ensure(4);
    final value =
        (_bytes[_offset] << 24) |
        (_bytes[_offset + 1] << 16) |
        (_bytes[_offset + 2] << 8) |
        _bytes[_offset + 3];
    _offset += 4;
    return value;
  }

  int readUint64() {
    _ensure(8);
    var value = 0;
    for (var index = 0; index < 8; index++) {
      value = (value << 8) | _bytes[_offset + index];
    }
    _offset += 8;
    if (value < 0) {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'uint64 exceeds the supported integer range',
      );
    }
    return value;
  }

  Uint8List readBytes(int length, {required int maxBytes}) {
    if (length < 0 || length > maxBytes) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'requested bytes exceed the configured bound',
      );
    }
    _ensure(length);
    final result = Uint8List.fromList(
      _bytes.sublist(_offset, _offset + length),
    );
    _offset += length;
    return result;
  }

  Uint8List readLengthPrefixedBytes({required int maxBytes}) {
    final length = readUint16();
    return readBytes(length, maxBytes: maxBytes);
  }

  void requireDone() {
    if (!isDone) {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'trailing bytes after a complete record',
      );
    }
  }

  void _ensure(int length) {
    if (length < 0 || remaining < length) {
      throw const RemoteException(
        RemoteFailureCode.truncatedFrame,
        'record is truncated',
      );
    }
  }
}

String remoteSafeIdentifier(String value, {int maxBytes = 1024}) {
  final bytes = Uint8List.fromList(value.codeUnits);
  if (value.isEmpty ||
      bytes.length > maxBytes ||
      !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(value)) {
    throw const RemoteException(
      RemoteFailureCode.invalidInput,
      'identifier is not valid',
    );
  }
  return value;
}
