final class PlayerDiagnostics {
  const PlayerDiagnostics({
    this.sessionId,
    this.lastEvent,
    this.droppedEvents = 0,
    this.values = const {},
  });
  final String? sessionId;
  final String? lastEvent;
  final int droppedEvents;
  final Map<String, String> values;

  PlayerDiagnostics copyWith({
    Object? sessionId = _unset,
    Object? lastEvent = _unset,
    int? droppedEvents,
    Map<String, String>? values,
  }) => PlayerDiagnostics(
    sessionId: identical(sessionId, _unset)
        ? this.sessionId
        : sessionId as String?,
    lastEvent: identical(lastEvent, _unset)
        ? this.lastEvent
        : lastEvent as String?,
    droppedEvents: droppedEvents ?? this.droppedEvents,
    values: values ?? this.values,
  );

  static const _unset = Object();

  @override
  bool operator ==(Object other) =>
      other is PlayerDiagnostics &&
      other.sessionId == sessionId &&
      other.lastEvent == lastEvent &&
      other.droppedEvents == droppedEvents &&
      _mapsEqual(other.values, values);
  @override
  int get hashCode => Object.hash(
    sessionId,
    lastEvent,
    droppedEvents,
    Object.hashAll(values.entries.map((e) => Object.hash(e.key, e.value))),
  );

  static bool _mapsEqual(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}
