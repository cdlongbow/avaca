import 'dart:math' as math;

enum LibraryParseStatus { recognized, ambiguous, unrecognized }

enum LibraryVariant {
  u('U', 'cracked', false),
  c('C', 'no_uncensored', true),
  uc('UC', 'cracked', true),
  ru('RU', 'leak', false),
  ruc('RUC', 'leak', true);

  const LibraryVariant(this.token, this.type, this.hasChineseSubtitles);

  final String token;
  final String type;
  final bool hasChineseSubtitles;

  static LibraryVariant? fromToken(String? value) {
    final normalized = value?.trim().toUpperCase();
    for (final variant in values) {
      if (variant.token == normalized) return variant;
    }
    return null;
  }
}

enum LibraryImportOperationState {
  planned,
  preflighting,
  staging,
  copying,
  verifying,
  portableCommitted,
  indexing,
  sourceCleanupPending,
  linking,
  succeeded,
  failed,
  cancelledBeforeCommit,
  repairRequired;

  String get value => switch (this) {
    planned => 'planned',
    preflighting => 'preflighting',
    staging => 'staging',
    copying => 'copying',
    verifying => 'verifying',
    portableCommitted => 'portable_committed',
    indexing => 'indexing',
    sourceCleanupPending => 'source_cleanup_pending',
    linking => 'linking',
    succeeded => 'succeeded',
    failed => 'failed',
    cancelledBeforeCommit => 'cancelled_before_commit',
    repairRequired => 'repair_required',
  };

  static LibraryImportOperationState fromValue(String? value) {
    return values.firstWhere(
      (item) => item.value == value,
      orElse: () => LibraryImportOperationState.repairRequired,
    );
  }
}

enum LibraryImportItemState {
  planned,
  preflighting,
  staging,
  copying,
  verifying,
  portableCommitted,
  indexing,
  sourceCleanupPending,
  linking,
  succeeded,
  failed,
  cancelledBeforeCommit,
  repairRequired;

  String get value => switch (this) {
    planned => 'planned',
    preflighting => 'preflighting',
    staging => 'staging',
    copying => 'copying',
    verifying => 'verifying',
    portableCommitted => 'portable_committed',
    indexing => 'indexing',
    sourceCleanupPending => 'source_cleanup_pending',
    linking => 'linking',
    succeeded => 'succeeded',
    failed => 'failed',
    cancelledBeforeCommit => 'cancelled_before_commit',
    repairRequired => 'repair_required',
  };

  static LibraryImportItemState fromValue(String? value) {
    return values.firstWhere(
      (item) => item.value == value,
      orElse: () => LibraryImportItemState.repairRequired,
    );
  }
}

/// RFC 4122 version-4 IDs are portable identities; SQLite integer IDs remain
/// local indexes and foreign keys only.
class PortableIdGenerator {
  PortableIdGenerator({math.Random? random})
    : _random = random ?? math.Random.secure();

  final math.Random _random;

  String next() {
    final bytes = List<int>.generate(
      16,
      (_) => _random.nextInt(256),
      growable: false,
    );
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final joined = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${joined.substring(0, 8)}-'
        '${joined.substring(8, 12)}-'
        '${joined.substring(12, 16)}-'
        '${joined.substring(16, 20)}-'
        '${joined.substring(20)}';
  }
}

class LibraryFilenameParseResult {
  const LibraryFilenameParseResult({
    required this.rawFileName,
    required this.extension,
    required this.code,
    required this.normalizedCode,
    required this.variantToken,
    required this.variantType,
    required this.hasChineseSubtitles,
    required this.partNumber,
    required this.partLabel,
    required this.status,
    required this.diagnostic,
    this.parserVersion = 1,
    this.noiseTokens = const <String>[],
  });

  final String rawFileName;
  final String extension;
  final String? code;
  final String? normalizedCode;
  final String? variantToken;
  final String? variantType;
  final bool? hasChineseSubtitles;
  final int? partNumber;
  final String? partLabel;
  final LibraryParseStatus status;
  final String diagnostic;
  final int parserVersion;
  final List<String> noiseTokens;

  bool get isImportable =>
      status == LibraryParseStatus.recognized && normalizedCode != null;

  LibraryFilenameParseResult copyWith({
    Object? code = _unset,
    Object? normalizedCode = _unset,
    LibraryParseStatus? status,
    String? diagnostic,
  }) {
    return LibraryFilenameParseResult(
      rawFileName: rawFileName,
      extension: extension,
      code: identical(code, _unset) ? this.code : code as String?,
      normalizedCode: identical(normalizedCode, _unset)
          ? this.normalizedCode
          : normalizedCode as String?,
      variantToken: variantToken,
      variantType: variantType,
      hasChineseSubtitles: hasChineseSubtitles,
      partNumber: partNumber,
      partLabel: partLabel,
      status: status ?? this.status,
      diagnostic: diagnostic ?? this.diagnostic,
      parserVersion: parserVersion,
      noiseTokens: noiseTokens,
    );
  }

  static const Object _unset = Object();

  Map<String, Object?> toJson() => <String, Object?>{
    'rawFileName': rawFileName,
    'extension': extension,
    'code': code,
    'normalizedCode': normalizedCode,
    'variant': variantToken,
    'variantType': variantType,
    'hasChineseSubtitles': hasChineseSubtitles,
    'partNumber': partNumber,
    'partLabel': partLabel,
    'status': status.name,
    'diagnostic': diagnostic,
    'parserVersion': parserVersion,
    'noiseTokens': noiseTokens,
  };
}

class LibraryScanEntry {
  const LibraryScanEntry({
    required this.sourcePath,
    required this.originalFileName,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.createdAt,
    required this.parseResult,
    this.selected = false,
  });

  final String sourcePath;
  final String originalFileName;
  final int sizeBytes;
  final DateTime? modifiedAt;
  final DateTime? createdAt;
  final LibraryFilenameParseResult parseResult;
  final bool selected;

  LibraryScanEntry copyWith({
    LibraryFilenameParseResult? parseResult,
    bool? selected,
  }) => LibraryScanEntry(
    sourcePath: sourcePath,
    originalFileName: originalFileName,
    sizeBytes: sizeBytes,
    modifiedAt: modifiedAt,
    createdAt: createdAt,
    parseResult: parseResult ?? this.parseResult,
    selected: selected ?? this.selected,
  );
}

class LibraryFileSnapshot {
  const LibraryFileSnapshot({
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.createdAt,
    required this.changedAt,
  });

  final String path;
  final int sizeBytes;
  final DateTime? modifiedAt;
  final DateTime? createdAt;
  final DateTime? changedAt;

  bool matches(LibraryFileSnapshot other) {
    return sizeBytes == other.sizeBytes &&
        modifiedAt?.toUtc() == other.modifiedAt?.toUtc() &&
        createdAt?.toUtc() == other.createdAt?.toUtc();
  }
}

class MediaProbeResult {
  const MediaProbeResult({
    required this.width,
    required this.height,
    required this.frameRateNumerator,
    required this.frameRateDenominator,
    required this.durationMs,
    required this.container,
    required this.codec,
    required this.backend,
    required this.backendVersion,
    required this.selectedStreamIndex,
    this.error,
  });

  final int? width;
  final int? height;
  final int? frameRateNumerator;
  final int? frameRateDenominator;
  final int? durationMs;
  final String? container;
  final String? codec;
  final String backend;
  final String backendVersion;
  final int? selectedStreamIndex;
  final String? error;

  bool get isUsable =>
      error == null &&
      width != null &&
      height != null &&
      width! > 0 &&
      height! > 0 &&
      frameRateNumerator != null &&
      frameRateDenominator != null &&
      frameRateNumerator! > 0 &&
      frameRateDenominator! > 0;

  double? get frameRate =>
      frameRateNumerator == null || frameRateDenominator == null
      ? null
      : frameRateNumerator! / frameRateDenominator!;

  String? get resolutionLabel => resolutionLabelFor(width, height);

  static String? resolutionLabelFor(int? width, int? height) {
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    // Resolution labels follow the conventional vertical dimension: a
    // 1920x1080 stream is 1080p and a portrait 1080x1920 stream is 1920p.
    return '${height}p';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'width': width,
    'height': height,
    'frameRateNumerator': frameRateNumerator,
    'frameRateDenominator': frameRateDenominator,
    'frameRate': frameRate,
    'durationMs': durationMs,
    'container': container,
    'codec': codec,
    'backend': backend,
    'backendVersion': backendVersion,
    'selectedStreamIndex': selectedStreamIndex,
    'error': error,
  };
}

class LibraryMediaRecord {
  const LibraryMediaRecord({
    required this.mediaId,
    required this.workId,
    required this.relativePath,
    required this.fileName,
    required this.originalFileName,
    required this.variant,
    required this.variantType,
    required this.hasChineseSubtitles,
    required this.partNumber,
    required this.partLabel,
    required this.width,
    required this.height,
    required this.resolutionLabel,
    required this.frameRateNumerator,
    required this.frameRateDenominator,
    required this.frameRateDecimal,
    required this.durationMs,
    required this.container,
    required this.codec,
    required this.fileSizeBytes,
    required this.sha256,
    required this.sourceFileCreatedAt,
    required this.importedAt,
    required this.probeBackend,
    required this.probeVersion,
    required this.parserVersion,
    this.importOperationId,
  });

  final String mediaId;
  final String workId;
  final String relativePath;
  final String fileName;
  final String originalFileName;
  final String? variant;
  final String? variantType;
  final bool? hasChineseSubtitles;
  final int? partNumber;
  final String? partLabel;
  final int? width;
  final int? height;
  final String? resolutionLabel;
  final int? frameRateNumerator;
  final int? frameRateDenominator;
  final double? frameRateDecimal;
  final int? durationMs;
  final String? container;
  final String? codec;
  final int fileSizeBytes;
  final String sha256;
  final DateTime? sourceFileCreatedAt;
  final DateTime importedAt;
  final String probeBackend;
  final String probeVersion;
  final int parserVersion;
  final String? importOperationId;

  Map<String, Object?> toJson() => <String, Object?>{
    'mediaId': mediaId,
    'workId': workId,
    'file': relativePath,
    'fileName': fileName,
    'originalFileName': originalFileName,
    'variant': variant,
    'variantType': variantType,
    'hasChineseSubtitles': hasChineseSubtitles,
    'part': partNumber,
    'partLabel': partLabel,
    'width': width,
    'height': height,
    'resolution': resolutionLabel,
    'frameRateNumerator': frameRateNumerator,
    'frameRateDenominator': frameRateDenominator,
    'frameRate': frameRateDecimal,
    'durationMs': durationMs,
    'container': container,
    'codec': codec,
    'fileSizeBytes': fileSizeBytes,
    'sha256': sha256,
    'sourceFileCreatedAt': sourceFileCreatedAt?.toUtc().toIso8601String(),
    'importedAt': importedAt.toUtc().toIso8601String(),
    'probeBackend': probeBackend,
    'probeVersion': probeVersion,
    'parserVersion': parserVersion,
    'importOperationId': importOperationId,
  };

  static LibraryMediaRecord fromJson(
    Object? value, {
    required String fallbackWorkId,
  }) {
    if (value is! Map) {
      throw const FormatException('media record must be an object');
    }
    final map = Map<Object?, Object?>.from(value);
    final mediaId = _requiredString(map['mediaId'], 'mediaId');
    final workId = _optionalString(map['workId']) ?? fallbackWorkId;
    final relativePath =
        _optionalString(map['file']) ??
        _requiredString(map['relativePath'], 'file');
    final original = _requiredString(
      map['originalFileName'],
      'originalFileName',
    );
    final importedAt = DateTime.tryParse(
      _optionalString(map['importedAt']) ?? '',
    );
    if (importedAt == null) {
      throw const FormatException('media importedAt is invalid');
    }
    return LibraryMediaRecord(
      mediaId: mediaId,
      workId: workId,
      relativePath: relativePath,
      fileName:
          _optionalString(map['fileName']) ?? relativePath.split('/').last,
      originalFileName: original,
      variant: _optionalString(map['variant']),
      variantType:
          _optionalString(map['variantType']) ??
          _optionalString(map['uncensoredType']),
      hasChineseSubtitles: _optionalBool(map['hasChineseSubtitles']),
      partNumber: _optionalInt(map['part'] ?? map['partNumber']),
      partLabel: _optionalString(map['partLabel']),
      width: _optionalInt(map['width']),
      height: _optionalInt(map['height']),
      resolutionLabel: _optionalString(map['resolution']),
      frameRateNumerator: _optionalInt(map['frameRateNumerator']),
      frameRateDenominator: _optionalInt(map['frameRateDenominator']),
      frameRateDecimal: _optionalDouble(map['frameRate']),
      durationMs: _optionalInt(map['durationMs']),
      container: _optionalString(map['container']),
      codec: _optionalString(map['codec']),
      fileSizeBytes: _optionalInt(map['fileSizeBytes']) ?? 0,
      sha256: _optionalString(map['sha256']) ?? '',
      sourceFileCreatedAt: _optionalDateTime(map['sourceFileCreatedAt']),
      importedAt: importedAt.toUtc(),
      probeBackend: _optionalString(map['probeBackend']) ?? 'info.json',
      probeVersion: _optionalString(map['probeVersion']) ?? 'unknown',
      parserVersion: _optionalInt(map['parserVersion']) ?? 1,
      importOperationId: _optionalString(map['importOperationId']),
    );
  }
}

class LibraryInfoDocument {
  const LibraryInfoDocument({
    required this.schemaVersion,
    required this.workId,
    required this.code,
    required this.metadata,
    required this.primaryActressId,
    required this.performers,
    required this.images,
    required this.media,
    required this.scrape,
    this.libraryRelativePath = '',
  });

  final int schemaVersion;
  final String workId;
  final String code;
  final Map<String, Object?> metadata;
  final String? primaryActressId;
  final List<Map<String, Object?>> performers;
  final Map<String, String?> images;
  final List<LibraryMediaRecord> media;
  final Map<String, Object?> scrape;
  final String libraryRelativePath;

  LibraryInfoDocument copyWith({String? libraryRelativePath}) =>
      LibraryInfoDocument(
        schemaVersion: schemaVersion,
        workId: workId,
        code: code,
        metadata: metadata,
        primaryActressId: primaryActressId,
        performers: performers,
        images: images,
        media: media,
        scrape: scrape,
        libraryRelativePath: libraryRelativePath ?? this.libraryRelativePath,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'workId': workId,
    'code': code,
    'metadata': metadata,
    'primaryActressId': primaryActressId,
    'performers': performers,
    'images': images,
    'media': media.map((item) => item.toJson()).toList(growable: false),
    'scrape': scrape,
    'libraryRelativePath': libraryRelativePath,
  };

  static LibraryInfoDocument fromJson(Object? value) {
    if (value is! Map || value['schemaVersion'] != 1) {
      throw const FormatException('unsupported info.json schema');
    }
    final workId = _requiredString(value['workId'], 'workId');
    final code = _requiredString(value['code'], 'code');
    final rawMetadata = value['metadata'];
    final rawPerformers = value['performers'];
    final rawImages = value['images'];
    final rawMedia = value['media'];
    if (rawMetadata is! Map ||
        rawPerformers is! List ||
        rawImages is! Map ||
        rawMedia is! List) {
      throw const FormatException('info.json has invalid collections');
    }
    final performers = rawPerformers
        .whereType<Map>()
        .map(
          (item) => <String, Object?>{
            'actressId': _optionalString(item['actressId']),
            'name': _optionalString(item['name']) ?? '',
            'sourceUri': _optionalString(item['sourceUri']),
          },
        )
        .toList(growable: false);
    final images = <String, String?>{};
    for (final entry in rawImages.entries) {
      if (entry.key is String &&
          (entry.value == null || entry.value is String)) {
        images[entry.key as String] = entry.value as String?;
      }
    }
    final media = rawMedia
        .map(
          (item) => LibraryMediaRecord.fromJson(item, fallbackWorkId: workId),
        )
        .toList(growable: false);
    return LibraryInfoDocument(
      schemaVersion: 1,
      workId: workId,
      code: code,
      metadata: Map<String, Object?>.from(
        rawMetadata.map((key, value) => MapEntry(key.toString(), value)),
      ),
      primaryActressId: _optionalString(value['primaryActressId']),
      performers: performers,
      images: images,
      media: media,
      scrape: value['scrape'] is Map
          ? Map<String, Object?>.from(
              (value['scrape'] as Map).map(
                (key, item) => MapEntry(key.toString(), item),
              ),
            )
          : const <String, Object?>{},
      libraryRelativePath: _optionalString(value['libraryRelativePath']) ?? '',
    );
  }
}

String _requiredString(Object? value, String field) {
  final result = _optionalString(value);
  if (result == null || result.isEmpty) {
    throw FormatException('$field is required');
  }
  return result;
}

String? _optionalString(Object? value) {
  if (value is! String) return null;
  final result = value.trim();
  return result.isEmpty ? null : result;
}

bool? _optionalBool(Object? value) => value is bool ? value : null;

int? _optionalInt(Object? value) => value is num ? value.toInt() : null;

double? _optionalDouble(Object? value) =>
    value is num ? value.toDouble() : null;

DateTime? _optionalDateTime(Object? value) {
  final raw = _optionalString(value);
  return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
}
