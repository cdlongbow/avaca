import 'package:avaca_domain/avaca_domain.dart';
import 'package:avaca_scraper/avaca_scraper.dart';
import 'package:path/path.dart' as p;

/// The physical scan is authoritative.  Metadata is deliberately a separate
/// state machine so a file never disappears merely because a provider is
/// unavailable or a filename needs review.
enum ServerMetadataState {
  pending,
  resolved,
  manual,
  failed,
  stale;

  String get value => name;

  static ServerMetadataState fromValue(String? value) => values.firstWhere(
    (candidate) => candidate.name == value,
    orElse: () => ServerMetadataState.pending,
  );
}

enum ServerPhysicalParseStatus {
  recognized,
  ambiguous,
  unrecognized;

  String get value => name;

  static ServerPhysicalParseStatus fromValue(String? value) =>
      values.firstWhere(
        (candidate) => candidate.name == value,
        orElse: () => ServerPhysicalParseStatus.unrecognized,
      );
}

/// Conservative, pure filename grammar used by the non-destructive Server
/// scanner.  It is intentionally independent from the legacy importer and
/// never performs file moves, copies, deletes, or shortcut creation.
final class ServerFilenameParser {
  const ServerFilenameParser();

  static const int parserVersion = 2;
  static const Set<String> supportedExtensions = <String>{
    'avi',
    'flv',
    'm4v',
    'mkv',
    'mov',
    'mp4',
    'mpeg',
    'mpg',
    'ts',
    'webm',
    'wmv',
  };

  static final RegExp _codePattern = RegExp(
    r'(?:[A-Z]_[0-9]{3}[A-Z]{2,10}[0-9]{3,6}|'
    r'[0-9]?[A-Z]{2,10}-[0-9]{3,6}[A-Z]?|'
    r'[0-9]?[A-Z]{2,10}[0-9]{3,6})',
  );
  static final RegExp _tokenPattern = RegExp(r'[A-Z0-9]+');
  static final RegExp _partPattern = RegExp(r'^(?:CD|DISC|PART)([0-9]+)$');
  static final RegExp _versionPattern = RegExp(r'^(?:V|VER)[0-9]+$');
  static final RegExp _resolutionPattern = RegExp(
    r'^(?:FHD|UHD|8K|4K(?:[0-9]+)?|[0-9]{3,4}P)$',
  );

  ServerFilenameParseResult parse(String fileName) {
    final raw = p.basename(fileName).trim();
    final extensionWithDot = p.extension(raw).toLowerCase();
    final extension = extensionWithDot.startsWith('.')
        ? extensionWithDot.substring(1)
        : extensionWithDot;
    if (raw.isEmpty || !supportedExtensions.contains(extension)) {
      return _unrecognized(
        raw,
        extension,
        extension.isEmpty
            ? 'missing file extension'
            : 'unsupported video extension .$extension',
      );
    }
    final stem = raw.substring(0, raw.length - extensionWithDot.length);
    final normalizedStem = _normalizeAscii(stem).toUpperCase();
    final matches = _codePattern
        .allMatches(normalizedStem)
        .where((match) => _safeBoundary(normalizedStem, match))
        .toList(growable: false);
    final codes = <String>{
      for (final match in matches) _normalizeCode(match.group(0)!),
    };
    if (matches.isEmpty) {
      return _unrecognized(raw, extension, 'no conservative work code found');
    }
    if (codes.length > 1) {
      return _unrecognized(
        raw,
        extension,
        'multiple work codes found: ${codes.join(', ')}',
        status: ServerPhysicalParseStatus.ambiguous,
      );
    }
    final match = matches.reduce(
      (left, right) =>
          left.group(0)!.length >= right.group(0)!.length ? left : right,
    );
    final code = _normalizeCode(match.group(0)!);
    final suffix = normalizedStem.substring(match.end);
    final tokens = _tokenPattern
        .allMatches(suffix.substring(0, suffix.length.clamp(0, 96)))
        .map((item) => item.group(0)!)
        .take(8)
        .toList(growable: false);
    final variants = tokens.map(_variant).whereType<_ServerVariant>().toSet();
    if (variants.length > 1) {
      return _unrecognized(
        raw,
        extension,
        'conflicting variant tokens: ${variants.map((item) => item.token).join(', ')}',
        status: ServerPhysicalParseStatus.ambiguous,
      );
    }
    final partNumbers = <int>{};
    for (final token in tokens) {
      final partMatch = _partPattern.firstMatch(token);
      if (partMatch == null) continue;
      final number = int.tryParse(partMatch.group(1)!);
      if (number == null || number < 1 || number > 999) {
        return _unrecognized(
          raw,
          extension,
          'invalid multipart token $token',
          status: ServerPhysicalParseStatus.ambiguous,
        );
      }
      partNumbers.add(number);
    }
    if (partNumbers.length > 1) {
      return _unrecognized(
        raw,
        extension,
        'conflicting multipart tokens',
        status: ServerPhysicalParseStatus.ambiguous,
      );
    }
    final variant = variants.isEmpty ? null : variants.single;
    return ServerFilenameParseResult(
      rawFileName: raw,
      extension: extension,
      code: code,
      status: ServerPhysicalParseStatus.recognized,
      diagnostic: 'recognized by conservative filename grammar',
      variantToken: variant?.token,
      variantType: variant?.type,
      hasChineseSubtitles: variant?.hasChineseSubtitles,
      partNumber: partNumbers.isEmpty ? null : partNumbers.single,
      parserVersion: parserVersion,
      noiseTokens: tokens
          .where(
            (token) =>
                _versionPattern.hasMatch(token) ||
                _resolutionPattern.hasMatch(token),
          )
          .toList(growable: false),
    );
  }

  ServerFilenameParseResult applyManualCode(
    ServerFilenameParseResult previous,
    String editedCode,
  ) {
    final candidate = editedCode.trim();
    final parsed = parse('$candidate.${previous.extension}');
    if (!parsed.isRecognized) {
      return ServerFilenameParseResult(
        rawFileName: previous.rawFileName,
        extension: previous.extension,
        code: candidate.isEmpty ? null : candidate.toUpperCase(),
        status: ServerPhysicalParseStatus.unrecognized,
        diagnostic: 'manual code does not match the accepted grammar',
        variantToken: previous.variantToken,
        variantType: previous.variantType,
        hasChineseSubtitles: previous.hasChineseSubtitles,
        partNumber: previous.partNumber,
        parserVersion: parserVersion,
        noiseTokens: previous.noiseTokens,
      );
    }
    return ServerFilenameParseResult(
      rawFileName: previous.rawFileName,
      extension: previous.extension,
      code: parsed.code,
      status: ServerPhysicalParseStatus.recognized,
      diagnostic: 'manual code correction validated',
      variantToken: previous.variantToken,
      variantType: previous.variantType,
      hasChineseSubtitles: previous.hasChineseSubtitles,
      partNumber: previous.partNumber,
      parserVersion: parserVersion,
      noiseTokens: previous.noiseTokens,
    );
  }

  bool _safeBoundary(String value, RegExpMatch match) {
    bool isWord(String? character) {
      if (character == null) return false;
      final code = character.codeUnitAt(0);
      return (code >= 48 && code <= 57) || (code >= 65 && code <= 90);
    }

    final before = match.start == 0 ? null : value[match.start - 1];
    final after = match.end >= value.length ? null : value[match.end];
    return !isWord(before) && !isWord(after);
  }

  String _normalizeCode(String value) {
    final match = RegExp(
      r'^([0-9]?[A-Z]{2,10})(?:[-_]?)([0-9]{3,6})([A-Z]?)$',
    ).firstMatch(value);
    if (match == null) return value;
    final numeric = match.group(2)!.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return '${match.group(1)}-$numeric${match.group(3)}';
  }

  String _normalizeAscii(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune == 0x3000) {
        buffer.write(' ');
      } else if (rune >= 0xff01 && rune <= 0xff5e) {
        buffer.writeCharCode(rune - 0xfee0);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  _ServerVariant? _variant(String token) {
    const variants = <String, _ServerVariant>{
      'U': _ServerVariant('U', 'cracked', false),
      'C': _ServerVariant('C', 'no_uncensored', true),
      'UC': _ServerVariant('UC', 'cracked', true),
      'RU': _ServerVariant('RU', 'leak', false),
      'RUC': _ServerVariant('RUC', 'leak', true),
    };
    return variants[token];
  }

  ServerFilenameParseResult _unrecognized(
    String raw,
    String extension,
    String diagnostic, {
    ServerPhysicalParseStatus status = ServerPhysicalParseStatus.unrecognized,
  }) => ServerFilenameParseResult(
    rawFileName: raw,
    extension: extension,
    code: null,
    status: status,
    diagnostic: diagnostic,
    parserVersion: parserVersion,
  );
}

final class _ServerVariant {
  const _ServerVariant(this.token, this.type, this.hasChineseSubtitles);

  final String token;
  final String type;
  final bool hasChineseSubtitles;
}

/// A normalized filename observation.  It contains no permission to merge a
/// work identity; the metadata resolver may still require human confirmation.
final class ServerFilenameParseResult {
  const ServerFilenameParseResult({
    required this.rawFileName,
    required this.extension,
    required this.code,
    required this.status,
    required this.diagnostic,
    this.variantToken,
    this.variantType,
    this.hasChineseSubtitles,
    this.partNumber,
    this.parserVersion = 2,
    this.noiseTokens = const <String>[],
  });

  final String rawFileName;
  final String extension;
  final String? code;
  final ServerPhysicalParseStatus status;
  final String diagnostic;
  final String? variantToken;
  final String? variantType;
  final bool? hasChineseSubtitles;
  final int? partNumber;
  final int parserVersion;
  final List<String> noiseTokens;

  bool get isRecognized =>
      status == ServerPhysicalParseStatus.recognized && code != null;
}

final class ServerLibraryRoot {
  const ServerLibraryRoot({
    required this.rootId,
    required this.absolutePath,
    this.displayName,
    this.enabled = true,
  });

  final String rootId;
  final String absolutePath;
  final String? displayName;
  final bool enabled;
}

/// One row from the authoritative physical inventory.  [absolutePath] stays
/// inside the Server process and is never serialized into an application DTO.
final class ServerPhysicalMediaRecord {
  const ServerPhysicalMediaRecord({
    required this.mediaId,
    required this.rootId,
    required this.absolutePath,
    required this.relativePath,
    required this.fileName,
    required this.length,
    required this.modifiedAt,
    required this.parse,
    this.workId,
    this.mimeType = 'application/octet-stream',
    this.durationMs,
    this.isPresent = true,
  });

  final AvacaMediaId mediaId;
  final String rootId;
  final String absolutePath;
  final String relativePath;
  final String fileName;
  final int length;
  final DateTime modifiedAt;
  final ServerFilenameParseResult parse;
  final AvacaWorkId? workId;
  final String mimeType;
  final int? durationMs;
  final bool isPresent;
}

final class ServerWorkMetadataRecord {
  const ServerWorkMetadataRecord({
    required this.workId,
    required this.code,
    required this.title,
    required this.state,
    this.description,
    this.releaseDate,
    this.performers = const <ServerPerformerRecord>[],
    this.artwork,
    this.source,
    this.sourceUri,
    this.error,
  });

  final AvacaWorkId workId;
  final String code;
  final String title;
  final ServerMetadataState state;
  final String? description;
  final String? releaseDate;
  final List<ServerPerformerRecord> performers;
  final ServerArtworkRecord? artwork;
  final String? source;
  final String? sourceUri;
  final String? error;

  factory ServerWorkMetadataRecord.fromScrape(
    AvacaWorkMetadata metadata, {
    ServerMetadataState state = ServerMetadataState.resolved,
  }) {
    return ServerWorkMetadataRecord(
      workId: metadata.summary.workId,
      code: metadata.summary.code,
      title: metadata.summary.title,
      state: state,
      description: metadata.description,
      releaseDate: metadata.releaseDate,
      performers: metadata.performers
          .map(
            (performer) => ServerPerformerRecord(
              performerId: performer.performerId,
              externalId: performer.externalId,
              displayName: performer.displayName,
            ),
          )
          .toList(growable: false),
      artwork:
          metadata.artwork?.cachedPath == null ||
              metadata.artwork?.length == null
          ? null
          : ServerArtworkRecord(
              assetId:
                  metadata.artwork!.assetId ??
                  'asset.${metadata.artwork!.uri.hashCode.abs()}',
              revision: 0,
              absolutePath: metadata.artwork!.cachedPath!,
              mimeType:
                  metadata.artwork!.mimeType ?? 'application/octet-stream',
              length: metadata.artwork!.length!,
            ),
      source: metadata.source,
      sourceUri: metadata.sourceUri?.toString(),
    );
  }
}

final class ServerPerformerRecord {
  const ServerPerformerRecord({
    required this.performerId,
    required this.displayName,
    this.externalId,
  });

  final AvacaActressId performerId;
  final String? externalId;
  final String displayName;
}

/// Artwork paths are server-only.  The application layer receives only
/// [assetId] and [revision] and must use the bounded asset endpoint.
final class ServerArtworkRecord {
  const ServerArtworkRecord({
    required this.assetId,
    required this.revision,
    required this.absolutePath,
    required this.mimeType,
    required this.length,
  });

  final String assetId;
  final int revision;
  final String absolutePath;
  final String mimeType;
  final int length;
}

final class ServerAssetRecord {
  const ServerAssetRecord({
    required this.assetId,
    required this.revision,
    required this.absolutePath,
    required this.length,
    required this.mimeType,
  });

  final String assetId;
  final int revision;
  final String absolutePath;
  final int length;
  final String mimeType;
}

final class ServerReviewItem {
  const ServerReviewItem({
    required this.mediaId,
    required this.fileName,
    required this.relativePath,
    required this.parseStatus,
    required this.diagnostic,
    this.code,
    this.variantToken,
    this.metadataState = ServerMetadataState.pending,
    this.metadataError,
  });

  final AvacaMediaId mediaId;
  final String fileName;
  final String relativePath;
  final ServerPhysicalParseStatus parseStatus;
  final String diagnostic;
  final String? code;
  final String? variantToken;
  final ServerMetadataState metadataState;
  final String? metadataError;
}

/// Optional capabilities let the importer evolve without breaking existing
/// test fixtures and small Server compositions that only implement the old
/// work/media writer interface.
abstract interface class ServerPhysicalCatalogWriter {
  Future<void> upsertLibraryRoot(ServerLibraryRoot root);

  Future<void> upsertPhysicalMedia(ServerPhysicalMediaRecord media);

  Future<void> markMissingPhysicalMedia({
    required String rootId,
    required Set<String> seenMediaIds,
  });
}

abstract interface class ServerMetadataCatalogWriter {
  Future<void> upsertWorkMetadata(ServerWorkMetadataRecord metadata);
}

abstract interface class ServerMetadataFailureWriter {
  Future<void> markMetadataFailure({
    required AvacaMediaId mediaId,
    required String message,
  });
}

abstract interface class ServerReviewCatalogRepository {
  Future<List<ServerReviewItem>> listReviewItems({
    String? rootId,
    int limit = 100,
  });

  Future<void> applyManualCode({
    required AvacaMediaId mediaId,
    required String code,
  });
}

abstract interface class ServerManualCodeCatalog {
  Future<String?> findManualCode(AvacaMediaId mediaId);
}

abstract interface class ServerAssetCatalogRepository {
  Future<ServerAssetRecord?> findAsset(String assetId, int revision);
}
