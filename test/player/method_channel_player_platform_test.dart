import 'package:avaca/player/player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Windows method channel session decodes a GPU texture descriptor',
    () async {
      final control = const MethodChannel('avaca/player/control');
      final events = const EventChannel('avaca/player/events');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(control, null);
      });
      messenger.setMockMethodCallHandler(control, (call) async {
        calls.add(call);
        if (call.method == 'createSession') {
          return <String, Object?>{
            'surfaceType': 'windowsTexture',
            'textureId': 42,
          };
        }
        return null;
      });

      final session = await MethodChannelPlayerPlatform(
        control: control,
        events: events,
      ).createSession('windows-session');

      expect(session.surface.type, PlayerSurfaceType.windowsTexture);
      expect(session.surface.textureId, 42);
      expect(calls.single.method, 'createSession');
      expect(calls.single.arguments, {'sessionId': 'windows-session'});
      await session.close();
    },
  );

  test(
    'unsupported method channel platforms expose no native surface',
    () async {
      final control = const MethodChannel('avaca/player/control');
      final events = const EventChannel('avaca/player/events');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(control, null);
      });
      messenger.setMockMethodCallHandler(control, (call) async {
        if (call.method == 'close') return null;
        fail('Unsupported platforms must not invoke native createSession.');
      });

      final session = await MethodChannelPlayerPlatform(
        control: control,
        events: events,
      ).createSession('linux-session');

      expect(session.surface.type, PlayerSurfaceType.none);
      await session.close();
    },
  );
}
