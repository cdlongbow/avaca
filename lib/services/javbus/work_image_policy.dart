import 'work_code.dart';
import '../scrape/work_code_canonicalizer.dart';

enum WorkImageSource { dmm, mgstage }

enum WorkImageVariant { card, detail }

class WorkImageUrls {
  const WorkImageUrls({
    required this.card,
    required this.detail,
    required this.source,
  });

  final Uri card;
  final Uri detail;
  final WorkImageSource source;

  Uri forVariant(WorkImageVariant variant) {
    return variant == WorkImageVariant.card ? card : detail;
  }
}

class WorkImagePolicy {
  const WorkImagePolicy();

  /// Returns the local filename used for a work image.
  ///
  /// Keep this aligned with the DMM image code so a work such as START-489
  /// is stored as start00489ps.jpg (card) or start00489pl.jpg (detail).
  String fileNameFor({
    required String code,
    required WorkImageVariant variant,
  }) {
    final imageCode = _localImageCode(code);
    final suffix = variant == WorkImageVariant.card ? 'ps' : 'pl';
    return '$imageCode$suffix.jpg';
  }

  WorkImageUrls urlsFor({
    required String code,
    String? studio,
    bool dmmLeadingOne = false,
    bool dmmTrailingV = false,
    bool dmmTrailingH2 = false,
  }) {
    final parts = _parseCode(code);
    if (_isPrestige(studio)) {
      final normalizedCode = '${parts.prefix}-${parts.number}';
      final base =
          'https://image.mgstage.com/images/prestige/'
          '${parts.prefix}/${parts.number}';
      return WorkImageUrls(
        card: Uri.parse('$base/pf_e_$normalizedCode.jpg'),
        detail: Uri.parse('$base/pb_e_$normalizedCode.jpg'),
        source: WorkImageSource.mgstage,
      );
    }

    final imageCode = _dmmImageCode(
      parts,
      dmmLeadingOne: dmmLeadingOne,
      dmmTrailingV: dmmTrailingV,
      dmmTrailingH2: dmmTrailingH2,
    );
    final base =
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        '$imageCode/$imageCode';
    return WorkImageUrls(
      card: Uri.parse('${base}ps.jpg'),
      detail: Uri.parse('${base}pl.jpg'),
      source: WorkImageSource.dmm,
    );
  }

  String _dmmImageCode(
    ({String prefix, String number}) parts, {
    bool dmmLeadingOne = false,
    bool dmmTrailingV = false,
    bool dmmTrailingH2 = false,
  }) {
    final paddedNumber = parts.number.padLeft(5, '0');
    final suffix = dmmTrailingH2
        ? 'h2'
        : dmmTrailingV
        ? 'v'
        : '';
    return parts.prefix == 'rebd'
        ? 'h_346${parts.prefix}$paddedNumber'
        : '${dmmLeadingOne ? '1' : ''}${parts.prefix}$paddedNumber$suffix';
  }

  String _localImageCode(String code) {
    try {
      return _dmmImageCode(_parseCode(code));
    } on FormatException {
      final normalized = canonicalizeJavBusWorkCode(code)
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      return normalized.isEmpty ? 'work' : normalized;
    }
  }

  ({String prefix, String number}) _parseCode(String code) {
    final match = RegExp(
      r'^([a-z0-9_]+)-?(\d+)$',
      caseSensitive: false,
    ).firstMatch(canonicalizeWorkCode(canonicalizeJavBusWorkCode(code)) ?? '');
    if (match == null) {
      throw FormatException('Unsupported work code: $code');
    }
    return (prefix: match.group(1)!.toLowerCase(), number: match.group(2)!);
  }

  bool _isPrestige(String? studio) {
    final normalized = studio?.trim().toLowerCase();
    return normalized == 'プレステージ' || normalized == 'prestige';
  }
}
