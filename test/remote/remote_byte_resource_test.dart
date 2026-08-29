import 'dart:math' as math;

import 'package:avaca/remote/remote.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/remote_fakes.dart';

void main() {
  test('synthetic opaque resource preserves 1000 random seeks', () async {
    final source = SyntheticRemoteMediaSource(length: 1024 * 1024);
    final service = RemoteResourceService(source);
    final handle = await service.open(RemoteResourceId(<int>[0x52, 0x31]));
    final random = math.Random(42);
    for (var index = 0; index < 1000; index++) {
      final length = random.nextInt(4096) + 1;
      final offset = random.nextInt(handle.length - length + 1);
      final result = await service.read(
        handle,
        RemoteByteRange(offset: offset, length: length),
      );
      expect(result.offset, offset);
      expect(result.bytes.length, length);
      for (var byteIndex = 0; byteIndex < result.bytes.length; byteIndex++) {
        expect(result.bytes[byteIndex], (offset + byteIndex) & 0xff);
      }
      expect(result.eof, offset + length >= handle.length);
    }
    await service.close(handle);
    await expectLater(
      service.read(handle, const RemoteByteRange(offset: 0, length: 1)),
      throwsA(isA<RemoteException>()),
    );
  });
}
