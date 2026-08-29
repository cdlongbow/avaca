import 'package:path/path.dart' as path;

import 'library_models.dart';

/// Conservative filename parser for destructive-import input.
///
/// This parser intentionally does not call the legacy work-code canonicalizer:
/// a filename is an observation, not permission to merge two Work identities.
class LibraryFilenameParser {
  const LibraryFilenameParser();

  static const int parserVersion = 1;
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
  static final RegExp _suffixTokenPattern = RegExp(r'[A-Z0-9]+');
  static final RegExp _partPattern = RegExp(r'^(?:CD|DISC|PART)([0-9]+)$');
  static final RegExp _versionPattern = RegExp(r'^(?:V|VER)[0-9]+$');
  static final RegExp _resolutionNoisePattern = RegExp(
    r'^(?:FHD|UHD|4K|8K|[0-9]{3,4}P)$',
  );

  LibraryFilenameParseResult parse(String fileName) {
    final raw = path.basename(fileName).trim();
    final extensionWithDot = path.extension(raw).toLowerCase();
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
        .where((match) => _hasSafeBoundaries(normalizedStem, match))
        .toList(growable: false);
    final distinctCodes = <String>{
      for (final match in matches) _normalizeCode(match.group(0)!),
    };
    if (matches.isEmpty) {
      return _unrecognized(raw, extension, 'no conservative work code found');
    }
    if (distinctCodes.length > 1) {
      return _unrecognized(
        raw,
        extension,
        'multiple work codes found: ${distinctCodes.join(', ')}',
        status: LibraryParseStatus.ambiguous,
      );
    }

    final match = matches.reduce(
      (left, right) =>
          left.group(0)!.length >= right.group(0)!.length ? left : right,
    );
    final code = _normalizeCode(match.group(0)!);
    final prefixNoise = _noiseTokens(normalizedStem.substring(0, match.start));
    final suffix = normalizedStem.substring(match.end);
    final suffixTokens = _suffixTokenPattern
        .allMatches(suffix.substring(0, suffix.length.clamp(0, 96)))
        .map((item) => item.group(0)!)
        .take(8)
        .toList(growable: false);
    final variants = suffixTokens
        .map(LibraryVariant.fromToken)
        .whereType<LibraryVariant>()
        .toList(growable: false);
    final uniqueVariants = variants.toSet();
    if (uniqueVariants.length > 1) {
      return _unrecognized(
        raw,
        extension,
        'conflicting variant tokens: ${uniqueVariants.map((item) => item.token).join(', ')}',
        status: LibraryParseStatus.ambiguous,
      );
    }

    final partNumbers = <int>{};
    final partLabels = <String>{};
    final noise = <String>[];
    for (final token in suffixTokens) {
      final partMatch = _partPattern.firstMatch(token);
      if (partMatch != null) {
        final partNumber = int.tryParse(partMatch.group(1)!);
        if (partNumber == null || partNumber < 1 || partNumber > 999) {
          return _unrecognized(
            raw,
            extension,
            'invalid multipart token $token',
            status: LibraryParseStatus.ambiguous,
          );
        }
        partNumbers.add(partNumber);
        partLabels.add(token);
      } else if (_versionPattern.hasMatch(token) ||
          _resolutionNoisePattern.hasMatch(token)) {
        noise.add(token);
      }
    }
    if (partNumbers.length > 1) {
      return _unrecognized(
        raw,
        extension,
        'conflicting multipart tokens: ${partLabels.join(', ')}',
        status: LibraryParseStatus.ambiguous,
      );
    }

    final variant = uniqueVariants.firstOrNull;
    return LibraryFilenameParseResult(
      rawFileName: raw,
      extension: extension,
      code: code,
      normalizedCode: code,
      variantToken: variant?.token,
      variantType: variant?.type,
      hasChineseSubtitles: variant?.hasChineseSubtitles,
      partNumber: partNumbers.firstOrNull,
      partLabel: partLabels.firstOrNull,
      status: LibraryParseStatus.recognized,
      diagnostic: 'recognized by conservative filename grammar',
      parserVersion: parserVersion,
      noiseTokens: List.unmodifiable([...prefixNoise, ...noise]),
    );
  }

  LibraryFilenameParseResult applyManualCode(
    LibraryFilenameParseResult previous,
    String editedCode,
  ) {
    final candidate = editedCode.trim();
    final parsed = parse('$candidate.${previous.extension}');
    if (!parsed.isImportable ||
        parsed.normalizedCode != candidate.toUpperCase()) {
      return previous.copyWith(
        code: candidate.isEmpty ? null : candidate.toUpperCase(),
        normalizedCode: null,
        status: LibraryParseStatus.unrecognized,
        diagnostic: 'manual code does not match the accepted grammar',
      );
    }
    return LibraryFilenameParseResult(
      rawFileName: previous.rawFileName,
      extension: previous.extension,
      code: parsed.code,
      normalizedCode: parsed.normalizedCode,
      variantToken: previous.variantToken,
      variantType: previous.variantType,
      hasChineseSubtitles: previous.hasChineseSubtitles,
      partNumber: previous.partNumber,
      partLabel: previous.partLabel,
      status: LibraryParseStatus.recognized,
      diagnostic: 'manual code correction validated',
      parserVersion: parserVersion,
      noiseTokens: previous.noiseTokens,
    );
  }

  bool _hasSafeBoundaries(String value, RegExpMatch match) {
    final before = match.start == 0 ? null : value[match.start - 1];
    final after = match.end >= value.length ? null : value[match.end];
    bool isWord(String? character) {
      if (character == null) return false;
      final codeUnit = character.codeUnitAt(0);
      return (codeUnit >= 48 && codeUnit <= 57) ||
          (codeUnit >= 65 && codeUnit <= 90) ||
          character == '_';
    }

    return !isWord(before) && !isWord(after);
  }

  String _normalizeCode(String raw) {
    final value = raw.trim().toUpperCase();
    if (value.contains('-') || value.contains('_')) return value;
    final compact = RegExp(
      r'^([0-9]?[A-Z]{2,10})([0-9]{3,6})([A-Z]?)$',
    ).firstMatch(value);
    if (compact == null) return value;
    final numeric = compact.group(2)!.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return '${compact.group(1)}-$numeric${compact.group(3)}';
  }

  List<String> _noiseTokens(String value) {
    return _suffixTokenPattern
        .allMatches(value)
        .map((match) => match.group(0)!)
        .where(
          (token) =>
              _versionPattern.hasMatch(token) ||
              _resolutionNoisePattern.hasMatch(token),
        )
        .toList(growable: false);
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

  LibraryFilenameParseResult _unrecognized(
    String raw,
    String extension,
    String diagnostic, {
    LibraryParseStatus status = LibraryParseStatus.unrecognized,
  }) {
    return LibraryFilenameParseResult(
      rawFileName: raw,
      extension: extension,
      code: null,
      normalizedCode: null,
      variantToken: null,
      variantType: null,
      hasChineseSubtitles: null,
      partNumber: null,
      partLabel: null,
      status: status,
      diagnostic: diagnostic,
      parserVersion: parserVersion,
    );
  }
}
