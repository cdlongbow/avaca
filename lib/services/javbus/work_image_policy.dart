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

  WorkImageUrls urlsFor({
    required String code,
    String? studio,
    bool dmmLeadingOne = false,
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

    final paddedNumber = parts.number.padLeft(5, '0');
    final imageCode = '${dmmLeadingOne ? '1' : ''}${parts.prefix}$paddedNumber';
    final base =
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        '$imageCode/$imageCode';
    return WorkImageUrls(
      card: Uri.parse('${base}ps.jpg'),
      detail: Uri.parse('${base}pl.jpg'),
      source: WorkImageSource.dmm,
    );
  }

  ({String prefix, String number}) _parseCode(String code) {
    final match = RegExp(
      r'^([a-z0-9_]+)-?(\d+)$',
      caseSensitive: false,
    ).firstMatch(code.trim());
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
