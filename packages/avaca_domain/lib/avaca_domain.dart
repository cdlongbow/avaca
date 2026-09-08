import 'dart:typed_data';

/// Stable identities crossing the Server/AVACA boundary.  They are opaque
/// portable IDs, never SQLite integer primary keys or filesystem paths.
class AvacaMediaId {
  const AvacaMediaId(this.value) : assert(value != '');

  final String value;

  @override
  bool operator ==(Object other) =>
      other is AvacaMediaId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

class AvacaWorkId {
  const AvacaWorkId(this.value) : assert(value != '');

  final String value;

  @override
  bool operator ==(Object other) =>
      other is AvacaWorkId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Opaque identities shared by the Server and AVACA client.  These values are
/// never SQLite row IDs, absolute paths, or bearer tokens.
class AvacaActressId {
  const AvacaActressId(this.value) : assert(value != '');

  final String value;

  @override
  bool operator ==(Object other) =>
      other is AvacaActressId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

class AvacaServerId {
  const AvacaServerId(this.value) : assert(value != '');

  final String value;

  @override
  bool operator ==(Object other) =>
      other is AvacaServerId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

class AvacaPlaybackSessionId {
  const AvacaPlaybackSessionId(this.value) : assert(value != '');

  final String value;

  @override
  bool operator ==(Object other) =>
      other is AvacaPlaybackSessionId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

enum AvacaMediaAvailability { available, unavailable, unknown }

class AvacaAssetDescriptor {
  const AvacaAssetDescriptor({
    required this.mediaId,
    required this.resourceId,
    required this.length,
    required this.container,
    this.codec,
    this.durationMs,
    this.sessionId,
    this.playbackGrant,
    this.availability = AvacaMediaAvailability.available,
  });

  final AvacaMediaId mediaId;
  final String resourceId;
  final int length;
  final String container;
  final String? codec;
  final int? durationMs;

  /// The short-lived playback session that authorizes this resource.  It is
  /// deliberately separate from [resourceId]: a server may rotate resource
  /// grants while keeping the catalog media identity stable.
  final String? sessionId;

  /// Short-lived 32-byte grant returned by the authenticated Server.  It is
  /// optional in catalog-only fixtures and is never persisted in the Library.
  final Uint8List? playbackGrant;
  final AvacaMediaAvailability availability;
}

class AvacaCollectionPage {
  const AvacaCollectionPage({required this.items, required this.nextCursor});

  final List<AvacaWorkSummary> items;
  final String? nextCursor;
}

class AvacaPerformerSummary {
  const AvacaPerformerSummary({
    required this.actressId,
    required this.displayName,
  });

  final AvacaActressId actressId;
  final String displayName;
}

class AvacaMediaSummary {
  const AvacaMediaSummary({
    required this.mediaId,
    required this.workId,
    required this.code,
    required this.title,
    this.durationMs,
    required this.availability,
    this.artworkResourceId,
  });

  final AvacaMediaId mediaId;
  final AvacaWorkId workId;
  final String code;
  final String title;
  final int? durationMs;
  final AvacaMediaAvailability availability;
  final String? artworkResourceId;
}

/// Detailed catalog data returned by the Server.  This is still metadata and
/// opaque IDs only; it deliberately has no local path, SQL key, or media bytes.
class AvacaWorkDetail {
  const AvacaWorkDetail({
    required this.workId,
    required this.code,
    required this.title,
    this.description,
    this.releaseDate,
    this.performers = const <AvacaPerformerSummary>[],
    this.media = const <AvacaMediaSummary>[],
    this.coverResourceId,
  });

  final AvacaWorkId workId;
  final String code;
  final String title;
  final String? description;
  final String? releaseDate;
  final List<AvacaPerformerSummary> performers;
  final List<AvacaMediaSummary> media;
  final String? coverResourceId;
}

class AvacaWorkSummary {
  const AvacaWorkSummary({
    required this.workId,
    required this.code,
    required this.title,
    this.coverResourceId,
  });

  final AvacaWorkId workId;
  final String code;
  final String title;
  final String? coverResourceId;
}
