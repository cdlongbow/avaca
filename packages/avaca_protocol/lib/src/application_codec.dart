import 'dart:convert';
import 'dart:typed_data';

import 'package:avaca_domain/avaca_domain.dart';

import '../avaca_protocol.dart';

/// DTOs for the v2 application layer.  These are deliberately separate from
/// SQLite entities; no DTO contains a local row id or a filesystem path.
class AvacaCapabilitiesDto {
  const AvacaCapabilitiesDto({
    required this.serverId,
    required this.features,
    required this.maxCollectionPageSize,
    required this.maxReadBytes,
  });

  final AvacaServerId serverId;
  final Set<String> features;
  final int maxCollectionPageSize;
  final int maxReadBytes;
}

class AvacaCollectionListRequestDto {
  const AvacaCollectionListRequestDto({this.cursor, this.limit = 50});

  final String? cursor;
  final int limit;
}

class AvacaMediaCardDto {
  const AvacaMediaCardDto({
    required this.mediaId,
    required this.workId,
    required this.code,
    required this.title,
    this.durationMs,
    required this.availability,
    this.artwork,
  });

  final AvacaMediaId mediaId;
  final AvacaWorkId workId;
  final String code;
  final String title;
  final int? durationMs;
  final AvacaMediaAvailability availability;
  final AvacaAssetRefDto? artwork;
}

class AvacaWorkCardDto {
  const AvacaWorkCardDto({
    required this.workId,
    required this.code,
    required this.title,
    this.cover,
  });

  final AvacaWorkId workId;
  final String code;
  final String title;
  final AvacaAssetRefDto? cover;
}

class AvacaAssetRefDto {
  const AvacaAssetRefDto({required this.assetId, required this.revision});

  final String assetId;
  final int revision;
}

/// Request for one bounded artwork/asset range.  The asset id and revision
/// are opaque catalog references; the Server resolves their private cache
/// path after the authenticated session has been established.
class AvacaAssetOpenRequestDto {
  const AvacaAssetOpenRequestDto({
    required this.assetId,
    required this.revision,
    required this.offset,
    required this.length,
  });

  final String assetId;
  final int revision;
  final int offset;
  final int length;
}

class AvacaAssetOpenedDto {
  AvacaAssetOpenedDto({
    required this.assetId,
    required this.revision,
    required this.offset,
    required List<int> bytes,
    required this.eof,
    this.mimeType,
  }) : bytes = Uint8List.fromList(bytes);

  final String assetId;
  final int revision;
  final int offset;
  final Uint8List bytes;
  final bool eof;
  final String? mimeType;
}

class AvacaCollectionPageDto {
  const AvacaCollectionPageDto({required this.items, this.nextCursor});

  final List<AvacaWorkCardDto> items;
  final String? nextCursor;
}

class AvacaPerformerDto {
  const AvacaPerformerDto({required this.actressId, required this.displayName});

  final AvacaActressId actressId;
  final String displayName;
}

class AvacaWorkDetailDto {
  const AvacaWorkDetailDto({
    required this.workId,
    required this.code,
    required this.title,
    this.description,
    this.releaseDate,
    required this.performers,
    required this.media,
    this.artwork,
  });

  final AvacaWorkId workId;
  final String code;
  final String title;
  final String? description;
  final String? releaseDate;
  final List<AvacaPerformerDto> performers;
  final List<AvacaMediaCardDto> media;
  final AvacaAssetRefDto? artwork;
}

class AvacaPlaybackSessionDto {
  const AvacaPlaybackSessionDto({
    required this.playbackSessionId,
    required this.resourceId,
    required this.playbackGrant,
    required this.contentLength,
    this.mimeType,
    this.durationMs,
    this.expiresAtMs,
  });

  final String playbackSessionId;
  final String resourceId;
  final Uint8List playbackGrant;
  final int contentLength;
  final String? mimeType;
  final int? durationMs;
  final int? expiresAtMs;
}

/// Authorization material carried by the native playback data-plane when it
/// opens a resource.  The client id is intentionally absent: it is taken from
/// the authenticated QUIC connection context on the Server.
class AvacaResourceOpenRequestDto {
  const AvacaResourceOpenRequestDto({
    required this.playbackSessionId,
    required this.resourceId,
    required this.playbackGrant,
  });

  final String playbackSessionId;
  final String resourceId;
  final Uint8List playbackGrant;
}

class AvacaResourceOpenedDto {
  const AvacaResourceOpenedDto({
    String? resourceHandle,
    String? resourceId,
    required this.contentLength,
    this.mimeType,
  }) : resourceHandle = resourceHandle ?? resourceId ?? '',
       resourceId = resourceId ?? resourceHandle ?? '';

  /// Connection-scoped opaque handle returned after authorization.  It must
  /// never be treated as a path or reused on another QUIC connection.
  final String resourceHandle;

  /// Kept as a source-compatibility alias for old fixture callers.  New wire
  /// payloads contain only [resourceHandle].
  final String resourceId;
  final int contentLength;
  final String? mimeType;
}

class AvacaResourceChunkDto {
  AvacaResourceChunkDto({
    required this.offset,
    required List<int> bytes,
    required this.eof,
  }) : bytes = Uint8List.fromList(bytes);

  final int offset;
  final Uint8List bytes;
  final bool eof;
}

class AvacaErrorDto {
  const AvacaErrorDto({
    required this.failureCode,
    required this.retryable,
    required this.requestId,
  });

  final String failureCode;
  final bool retryable;
  final int requestId;
}

class AvacaCancelReadDto {
  const AvacaCancelReadDto({required this.targetRequestId});

  final int targetRequestId;
}

class AvacaCancelReadResultDto {
  const AvacaCancelReadResultDto({
    required this.targetRequestId,
    required this.cancelled,
  });

  final int targetRequestId;
  final bool cancelled;
}

/// Bounded JSON payload codec for the application DTOs.  JSON is used only
/// inside the already framed, authenticated v2 stream; strict validation and
/// the frame limit keep malformed input from causing unbounded allocations.
class AvacaApplicationCodec {
  const AvacaApplicationCodec();

  static const maxPayloadBytes = AvacaFrameCodec.applicationMax;
  static const maxPageSize = 100;
  static const maxStringBytes = 4096;
  // Binary ranges are base64 encoded inside the framed JSON payload.  Keep
  // the decoded bound below the frame limit so the response can carry its
  // JSON/base64 overhead without exceeding the application frame.
  static const maxBinaryRangeBytes = 700 * 1024;

  Uint8List encodeCapabilities(AvacaCapabilitiesDto value) => _encode({
    'serverId': _id(value.serverId.value),
    'protocolVersion': AvacaProtocol.version,
    'features': value.features.toList(growable: false),
    'maxCollectionPageSize': value.maxCollectionPageSize,
    'maxReadBytes': value.maxReadBytes,
  });

  AvacaCapabilitiesDto decodeCapabilities(List<int> payload) {
    final map = _map(payload);
    final protocolVersion = _int(map, 'protocolVersion');
    if (protocolVersion != AvacaProtocol.version) {
      throw const AvacaProtocolException(
        'capabilities protocol version mismatch',
      );
    }
    final features = map['features'];
    if (features is! List ||
        features.length > 64 ||
        features.any((value) => value is! String || value.length > 128)) {
      throw const AvacaProtocolException(
        'capabilities feature list is invalid',
      );
    }
    return AvacaCapabilitiesDto(
      serverId: AvacaServerId(_id(map['serverId'])),
      features: features.cast<String>().toSet(),
      maxCollectionPageSize: _boundedInt(
        map,
        'maxCollectionPageSize',
        min: 1,
        max: maxPageSize,
      ),
      maxReadBytes: _boundedInt(
        map,
        'maxReadBytes',
        min: 1,
        max: 4 * 1024 * 1024,
      ),
    );
  }

  Uint8List encodeCollectionRequest(AvacaCollectionListRequestDto value) {
    if (value.limit < 1 || value.limit > maxPageSize) {
      throw const AvacaProtocolException('collection page limit is invalid');
    }
    return _encode({'cursor': value.cursor, 'limit': value.limit});
  }

  AvacaCollectionListRequestDto decodeCollectionRequest(List<int> payload) {
    final map = _map(payload);
    final cursor = map['cursor'];
    if (cursor != null && (cursor is! String || !_validString(cursor))) {
      throw const AvacaProtocolException('collection cursor is invalid');
    }
    return AvacaCollectionListRequestDto(
      cursor: cursor as String?,
      limit: _boundedInt(map, 'limit', min: 1, max: maxPageSize),
    );
  }

  Uint8List encodeCollectionPage(AvacaCollectionPageDto value) => _encode({
    'items': value.items.map(_encodeWorkCardMap).toList(growable: false),
    'nextCursor': value.nextCursor,
  });

  AvacaCollectionPageDto decodeCollectionPage(List<int> payload) {
    final map = _map(payload);
    final items = map['items'];
    if (items is! List || items.length > maxPageSize) {
      throw const AvacaProtocolException('collection page items are invalid');
    }
    return AvacaCollectionPageDto(
      items: items.map((item) => _decodeWorkCard(item)).toList(growable: false),
      nextCursor: _optionalString(map, 'nextCursor'),
    );
  }

  Uint8List encodeWorkDetail(AvacaWorkDetailDto value) => _encode({
    'workId': _id(value.workId.value),
    'code': _string(value.code),
    'title': _string(value.title),
    'description': value.description,
    'releaseDate': value.releaseDate,
    'performers': value.performers
        .map(
          (performer) => {
            'actressId': _id(performer.actressId.value),
            'displayName': _string(performer.displayName),
          },
        )
        .toList(growable: false),
    'media': value.media.map(_encodeMediaCardMap).toList(growable: false),
    'artwork': _encodeArtwork(value.artwork),
  });

  AvacaWorkDetailDto decodeWorkDetail(List<int> payload) {
    final map = _map(payload);
    final performers = map['performers'];
    final media = map['media'];
    if (performers is! List ||
        performers.length > 1024 ||
        media is! List ||
        media.length > maxPageSize) {
      throw const AvacaProtocolException('work detail arrays are invalid');
    }
    return AvacaWorkDetailDto(
      workId: AvacaWorkId(_id(map['workId'])),
      code: _stringValue(map, 'code'),
      title: _stringValue(map, 'title'),
      description: _optionalString(map, 'description'),
      releaseDate: _optionalString(map, 'releaseDate'),
      performers: performers.map(_decodePerformer).toList(growable: false),
      media: media.map(_decodeMediaCard).toList(growable: false),
      artwork: _decodeArtwork(map['artwork']),
    );
  }

  Uint8List encodePlaybackSession(AvacaPlaybackSessionDto value) {
    if (value.playbackGrant.length != 32) {
      throw const AvacaProtocolException('playback grant must be 32 bytes');
    }
    return _encode({
      'playbackSessionId': _id(value.playbackSessionId),
      'resourceId': _id(value.resourceId),
      'playbackGrant': base64UrlEncode(value.playbackGrant).replaceAll('=', ''),
      'contentLength': value.contentLength,
      'mimeType': value.mimeType,
      'durationMs': value.durationMs,
      'expiresAtMs': value.expiresAtMs,
    });
  }

  AvacaPlaybackSessionDto decodePlaybackSession(List<int> payload) {
    final map = _map(payload);
    final encoded = _stringValue(map, 'playbackGrant');
    late final Uint8List grant;
    try {
      grant = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(encoded)),
      );
    } on FormatException {
      throw const AvacaProtocolException('playback grant encoding is invalid');
    }
    if (grant.length != 32) {
      throw const AvacaProtocolException('playback grant length is invalid');
    }
    final length = _int(map, 'contentLength');
    if (length < 0) {
      throw const AvacaProtocolException('content length is invalid');
    }
    return AvacaPlaybackSessionDto(
      playbackSessionId: _id(map['playbackSessionId']),
      resourceId: _id(map['resourceId']),
      playbackGrant: grant,
      contentLength: length,
      mimeType: _optionalString(map, 'mimeType'),
      durationMs: _optionalNonNegativeInt(map, 'durationMs'),
      expiresAtMs: _optionalNonNegativeInt(map, 'expiresAtMs'),
    );
  }

  Uint8List encodeResourceOpenRequest(AvacaResourceOpenRequestDto value) {
    if (value.playbackGrant.length != 32) {
      throw const AvacaProtocolException('playback grant must be 32 bytes');
    }
    return _encode({
      'playbackSessionId': _id(value.playbackSessionId),
      'resourceId': _id(value.resourceId),
      'playbackGrant': base64UrlEncode(value.playbackGrant).replaceAll('=', ''),
    });
  }

  Uint8List encodeAssetOpenRequest(AvacaAssetOpenRequestDto value) {
    if (value.revision < 0 ||
        value.offset < 0 ||
        value.length <= 0 ||
        value.length > maxBinaryRangeBytes) {
      throw const AvacaProtocolException('asset range is invalid');
    }
    return _encode({
      'assetId': _id(value.assetId),
      'revision': value.revision,
      'offset': value.offset,
      'length': value.length,
    });
  }

  AvacaAssetOpenRequestDto decodeAssetOpenRequest(List<int> payload) {
    final map = _map(payload);
    final revision = _int(map, 'revision');
    final offset = _int(map, 'offset');
    final length = _int(map, 'length');
    if (revision < 0 ||
        offset < 0 ||
        length <= 0 ||
        length > maxBinaryRangeBytes) {
      throw const AvacaProtocolException('asset range is invalid');
    }
    return AvacaAssetOpenRequestDto(
      assetId: _id(map['assetId']),
      revision: revision,
      offset: offset,
      length: length,
    );
  }

  Uint8List encodeAssetOpened(AvacaAssetOpenedDto value) {
    if (value.revision < 0 ||
        value.offset < 0 ||
        value.bytes.length > maxBinaryRangeBytes) {
      throw const AvacaProtocolException('asset response is invalid');
    }
    return _encode({
      'assetId': _id(value.assetId),
      'revision': value.revision,
      'offset': value.offset,
      'bytes': base64UrlEncode(value.bytes).replaceAll('=', ''),
      'eof': value.eof,
      'mimeType': value.mimeType,
    });
  }

  AvacaAssetOpenedDto decodeAssetOpened(List<int> payload) {
    final map = _map(payload);
    final revision = _int(map, 'revision');
    final offset = _int(map, 'offset');
    final bytes = _decodeBase64Bytes(
      map,
      'bytes',
      error: 'asset bytes are invalid',
    );
    if (revision < 0 || offset < 0) {
      throw const AvacaProtocolException('asset response is invalid');
    }
    return AvacaAssetOpenedDto(
      assetId: _id(map['assetId']),
      revision: revision,
      offset: offset,
      bytes: bytes,
      eof: _bool(map, 'eof'),
      mimeType: _optionalString(map, 'mimeType'),
    );
  }

  AvacaResourceOpenRequestDto decodeResourceOpenRequest(List<int> payload) {
    final map = _map(payload);
    final encoded = _stringValue(map, 'playbackGrant');
    late final Uint8List grant;
    try {
      grant = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(encoded)),
      );
    } on FormatException {
      throw const AvacaProtocolException('playback grant encoding is invalid');
    }
    if (grant.length != 32) {
      throw const AvacaProtocolException('playback grant length is invalid');
    }
    return AvacaResourceOpenRequestDto(
      playbackSessionId: _id(map['playbackSessionId']),
      resourceId: _id(map['resourceId']),
      playbackGrant: grant,
    );
  }

  Uint8List encodeResourceOpened(AvacaResourceOpenedDto value) => _encode({
    'resourceHandle': _id(value.resourceHandle),
    'contentLength': value.contentLength,
    'mimeType': value.mimeType,
  });

  AvacaResourceOpenedDto decodeResourceOpened(List<int> payload) {
    final map = _map(payload);
    final length = _int(map, 'contentLength');
    if (length < 0) {
      throw const AvacaProtocolException('resource content length is invalid');
    }
    final handle = map['resourceHandle'] ?? map['resourceId'];
    return AvacaResourceOpenedDto(
      resourceHandle: _id(handle),
      contentLength: length,
      mimeType: _optionalString(map, 'mimeType'),
    );
  }

  Uint8List encodeResourceChunk(AvacaResourceChunkDto value) {
    if (value.offset < 0 || value.bytes.length > maxBinaryRangeBytes) {
      throw const AvacaProtocolException('resource chunk range is invalid');
    }
    return _encode({
      'offset': value.offset,
      'bytes': base64UrlEncode(value.bytes).replaceAll('=', ''),
      'eof': value.eof,
    });
  }

  AvacaResourceChunkDto decodeResourceChunk(List<int> payload) {
    final map = _map(payload);
    final bytes = _decodeBase64Bytes(
      map,
      'bytes',
      error: 'resource chunk bytes are invalid',
    );
    return AvacaResourceChunkDto(
      offset: _int(map, 'offset'),
      bytes: bytes,
      eof: _bool(map, 'eof'),
    );
  }

  Uint8List encodeError(AvacaErrorDto value) => _encode({
    'failureCode': _string(value.failureCode),
    'retryable': value.retryable,
    'requestId': value.requestId,
  });

  AvacaErrorDto decodeError(List<int> payload) {
    final map = _map(payload);
    return AvacaErrorDto(
      failureCode: _stringValue(map, 'failureCode'),
      retryable: _bool(map, 'retryable'),
      requestId: _int(map, 'requestId'),
    );
  }

  Uint8List encodeIdRequest(String id) => _encode({'id': _id(id)});

  String decodeIdRequest(List<int> payload) {
    final map = _map(payload);
    return _id(map['id']);
  }

  Uint8List encodeRangeRequest({
    String? resourceId,
    String? resourceHandle,
    required int offset,
    required int length,
  }) {
    final handle = resourceHandle ?? resourceId;
    if (handle == null) {
      throw const AvacaProtocolException('resource handle is missing');
    }
    if (offset < 0 || length < 0 || length > maxBinaryRangeBytes) {
      throw const AvacaProtocolException('resource range is invalid');
    }
    return _encode({
      'resourceHandle': _id(handle),
      'offset': offset,
      'length': length,
    });
  }

  ({String resourceId, String resourceHandle, int offset, int length})
  decodeRangeRequest(List<int> payload) {
    final map = _map(payload);
    final offset = _int(map, 'offset');
    final length = _int(map, 'length');
    if (offset < 0 || length < 0 || length > maxBinaryRangeBytes) {
      throw const AvacaProtocolException('resource range is invalid');
    }
    final handle = map['resourceHandle'] ?? map['resourceId'];
    final id = _id(handle);
    return (resourceId: id, resourceHandle: id, offset: offset, length: length);
  }

  Uint8List encodeCancelReadRequest(AvacaCancelReadDto value) {
    if (value.targetRequestId <= 0) {
      throw const AvacaProtocolException('cancel target request id is invalid');
    }
    return _encode({'targetRequestId': value.targetRequestId});
  }

  AvacaCancelReadDto decodeCancelReadRequest(List<int> payload) {
    final targetRequestId = _int(_map(payload), 'targetRequestId');
    if (targetRequestId <= 0) {
      throw const AvacaProtocolException('cancel target request id is invalid');
    }
    return AvacaCancelReadDto(targetRequestId: targetRequestId);
  }

  Uint8List encodeCancelReadResult(AvacaCancelReadResultDto value) {
    if (value.targetRequestId <= 0) {
      throw const AvacaProtocolException('cancel target request id is invalid');
    }
    return _encode({
      'targetRequestId': value.targetRequestId,
      'cancelled': value.cancelled,
    });
  }

  AvacaCancelReadResultDto decodeCancelReadResult(List<int> payload) {
    final map = _map(payload);
    final targetRequestId = _int(map, 'targetRequestId');
    if (targetRequestId <= 0) {
      throw const AvacaProtocolException('cancel target request id is invalid');
    }
    return AvacaCancelReadResultDto(
      targetRequestId: targetRequestId,
      cancelled: _bool(map, 'cancelled'),
    );
  }

  Map<String, Object?> _encodeMediaCardMap(AvacaMediaCardDto value) => {
    'mediaId': _id(value.mediaId.value),
    'workId': _id(value.workId.value),
    'code': _string(value.code),
    'title': _string(value.title),
    'durationMs': value.durationMs,
    'availability': value.availability.name,
    'artwork': _encodeArtwork(value.artwork),
  };

  Map<String, Object?> _encodeWorkCardMap(AvacaWorkCardDto value) => {
    'workId': _id(value.workId.value),
    'code': _string(value.code),
    'title': _string(value.title),
    'cover': _encodeArtwork(value.cover),
  };

  AvacaWorkCardDto _decodeWorkCard(Object? value) {
    final map = _asMap(value, 'work card');
    return AvacaWorkCardDto(
      workId: AvacaWorkId(_id(map['workId'])),
      code: _stringValue(map, 'code'),
      title: _stringValue(map, 'title'),
      cover: _decodeArtwork(map['cover']),
    );
  }

  AvacaMediaCardDto _decodeMediaCard(Object? value) {
    final map = _asMap(value, 'media card');
    final duration = _optionalNonNegativeInt(map, 'durationMs');
    final availability = _stringValue(map, 'availability');
    final parsed = AvacaMediaAvailability.values.where(
      (candidate) => candidate.name == availability,
    );
    if (parsed.length != 1) {
      throw const AvacaProtocolException('media availability is invalid');
    }
    return AvacaMediaCardDto(
      mediaId: AvacaMediaId(_id(map['mediaId'])),
      workId: AvacaWorkId(_id(map['workId'])),
      code: _stringValue(map, 'code'),
      title: _stringValue(map, 'title'),
      durationMs: duration,
      availability: parsed.single,
      artwork: _decodeArtwork(map['artwork']),
    );
  }

  AvacaPerformerDto _decodePerformer(Object? value) {
    final map = _asMap(value, 'performer');
    return AvacaPerformerDto(
      actressId: AvacaActressId(_id(map['actressId'])),
      displayName: _stringValue(map, 'displayName'),
    );
  }

  Map<String, Object?>? _encodeArtwork(AvacaAssetRefDto? value) => value == null
      ? null
      : <String, Object?>{
          'assetId': _id(value.assetId),
          'revision': value.revision,
        };

  AvacaAssetRefDto? _decodeArtwork(Object? value) {
    if (value == null) return null;
    final map = _asMap(value, 'artwork');
    return AvacaAssetRefDto(
      assetId: _id(map['assetId']),
      revision: _int(map, 'revision'),
    );
  }

  Uint8List _encode(Map<String, Object?> value) {
    late final String encoded;
    try {
      encoded = jsonEncode(value);
    } on Object {
      throw const AvacaProtocolException(
        'application DTO could not be encoded',
      );
    }
    final bytes = Uint8List.fromList(utf8.encode(encoded));
    if (bytes.length > maxPayloadBytes) {
      throw const AvacaProtocolException('application DTO exceeds frame limit');
    }
    return bytes;
  }

  Map<String, Object?> _map(List<int> payload) {
    if (payload.length > maxPayloadBytes) {
      throw const AvacaProtocolException(
        'application payload exceeds frame limit',
      );
    }
    late final Object? value;
    try {
      value = jsonDecode(utf8.decode(payload));
    } on Object {
      throw const AvacaProtocolException(
        'application payload is not valid JSON',
      );
    }
    return _asMap(value, 'application payload');
  }

  Map<String, Object?> _asMap(Object? value, String name) {
    if (value is! Map) {
      throw AvacaProtocolException('$name is not an object');
    }
    return value.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  String _id(Object? value) {
    if (value is! String || !_validString(value) || value.length > 256) {
      throw const AvacaProtocolException('opaque identifier is invalid');
    }
    return value;
  }

  String _string(String value) {
    if (!_validString(value)) {
      throw const AvacaProtocolException('DTO string is invalid');
    }
    return value;
  }

  bool _validString(String value) =>
      value.isNotEmpty &&
      utf8.encode(value).length <= maxStringBytes &&
      !value.contains('\u0000');

  String _stringValue(Map<String, Object?> map, String key) =>
      _string(map[key] is String ? map[key] as String : '');

  Uint8List _decodeBase64Bytes(
    Map<String, Object?> map,
    String key, {
    required String error,
  }) {
    final value = map[key];
    if (value is! String ||
        value.isEmpty ||
        value.contains('\u0000') ||
        utf8.encode(value).length > maxPayloadBytes) {
      throw AvacaProtocolException(error);
    }
    try {
      final bytes = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(value)),
      );
      if (bytes.length > maxBinaryRangeBytes) {
        throw AvacaProtocolException(error);
      }
      return bytes;
    } on AvacaProtocolException {
      rethrow;
    } on FormatException {
      throw AvacaProtocolException(error);
    }
  }

  String? _optionalString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    return _stringValue(map, key);
  }

  int _int(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! int) {
      throw AvacaProtocolException('$key is not an integer');
    }
    return value;
  }

  int _boundedInt(
    Map<String, Object?> map,
    String key, {
    required int min,
    required int max,
  }) {
    final value = _int(map, key);
    if (value < min || value > max) {
      throw AvacaProtocolException('$key is outside its configured bound');
    }
    return value;
  }

  int? _optionalNonNegativeInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! int || value < 0) {
      throw AvacaProtocolException('$key is invalid');
    }
    return value;
  }

  bool _bool(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! bool) {
      throw AvacaProtocolException('$key is not a boolean');
    }
    return value;
  }
}
