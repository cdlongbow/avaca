import 'package:flutter/services.dart';

/// Channel names shared by the AVACA player Dart adapter and native plugin.
final class AvacaPlayerNative {
  AvacaPlayerNative._();

  static const String viewType = 'avaca_player_native/video';
  static const String controlChannelName = 'avaca/player/control';
  static const String eventsChannelName = 'avaca/player/events';

  static const MethodChannel control = MethodChannel(controlChannelName);
  static const EventChannel events = EventChannel(eventsChannelName);
}
