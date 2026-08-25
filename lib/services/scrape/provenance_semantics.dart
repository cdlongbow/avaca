/// Shared, deliberately narrow semantic propositions used by source parsers
/// and the provenance evaluator.
///
/// These helpers only return a positive proposition when the surrounding
/// wording is strong enough to support a derived-work decision.  A bare
/// `BEST`, `ベスト`, `新作`, or `コレクション` is intentionally not enough.
final class ScrapeProvenanceSemantics {
  const ScrapeProvenanceSemantics._();

  static String normalize(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final normalized = switch (rune) {
        >= 0xFF01 && <= 0xFF5E => rune - 0xFEE0,
        0x3000 => 0x20,
        _ => rune,
      };
      buffer.writeCharCode(normalized);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  static String? explicitCompilationLabel(String value) {
    final text = normalize(value);
    final match = RegExp(
      r'ベスト\s*[・･]\s*(?:総集編|総集篇|総集成)|総集編|総集篇|総集成|オムニバス|アンソロジー|作品集|選集|傑作選|名場面集|名作集',
      caseSensitive: false,
    ).firstMatch(text);
    return match?.group(0);
  }

  /// Returns a title/metadata proposition that identifies a prior-work
  /// collection, or null when the text only contains a safe standalone token.
  static String? strongReuseProposition(Iterable<String> values) {
    final text = normalize(values.join(' '));
    if (text.isEmpty) return null;
    final patterns = <RegExp>[
      RegExp(
        r'(?:\d+\s*(?:時間|分|hours?|minutes?|h|min)\s*(?:best|ベスト)|(?:best|ベスト)\s*\d+\s*(?:時間|分|hours?|minutes?|h|min)|(?:best|ベスト)\s*\d+\s+\d+\s*(?:時間|分|hours?|minutes?|h|min))',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:best|ベスト)\s*\d+\s*(?:人|本|作品|タイトル)|\d+\s*(?:人|本|作品|タイトル)[^\s]{0,6}(?:best|ベスト)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:女優|actress)\s*(?:best|ベスト)|(?:best|ベスト)\s*(?:女優|actress)',
        caseSensitive: false,
      ),
      RegExp(r'\b[a-z][a-z0-9._-]{1,}\s*(?:best|ベスト)\b', caseSensitive: false),
      RegExp(r'[ぁ-んァ-ン一-龯]{2,12}\s*(?:best|ベスト)', caseSensitive: false),
      RegExp(
        r'(?:best|ベスト)\s*(?:of|collection)|(?:complete|コンプリート)\s*(?:best|ベスト)|(?:best|ベスト)\s*(?:complete|コンプリート)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:永久\s*)?保存版\s*(?:best|ベスト)|(?:best|ベスト)\s*(?:永久\s*)?保存版|(?:厳選|傑作)\s*(?:best|ベスト)|(?:best|ベスト)\s*(?:厳選|傑作)',
        caseSensitive: false,
      ),
      RegExp(
        r'全\s*\d+\s*(?:作品|タイトル|本)|全出演作品|全作品|出演作品(?:全部|すべて|全て)|\d+\s*(?:タイトル|作品|本)\s*(?:全部入り|収録)|デビュー(?:作)?から現在まで|デビュー作から|歴代作品|過去作品|既存作品|再収録|厳選収録',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) return match.group(0);
    }
    return null;
  }

  static bool containsReliableOriginal(String value) {
    return RegExp(
      r'全編\s*(?:新撮|撮り下ろし)|完全\s*(?:新撮|撮り下ろし)|新撮|撮り下ろし',
      caseSensitive: false,
    ).hasMatch(normalize(value));
  }

  static bool containsOldMaterialWithNewBonus(String value) {
    final text = normalize(value);
    final hasNewBonus = RegExp(
      r'未公開|新作(?:映像|カット|特典)|bonus',
      caseSensitive: false,
    ).hasMatch(text);
    final hasOldMaterial = RegExp(
      r'過去作品|既存作品|再収録|収録作品|収録タイトル|best|ベスト|old|previous',
      caseSensitive: false,
    ).hasMatch(text);
    return hasNewBonus && hasOldMaterial;
  }
}
