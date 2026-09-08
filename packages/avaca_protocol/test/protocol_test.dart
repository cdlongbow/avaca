import 'package:avaca_protocol/avaca_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('v2 uses explicit sparse opcodes and round trips', () {
    const frame = AvacaFrame(
      opcode: AvacaOpcode.readResource,
      requestId: 7,
      payload: <int>[1, 2, 3],
    );
    final codec = const AvacaFrameCodec();
    final decoded = codec.decode(codec.encode(frame));
    expect(decoded.opcode, AvacaOpcode.readResource);
    expect(AvacaOpcode.readResource.value, 0x42);
    expect(AvacaProtocol.version, 2);
  });
}
