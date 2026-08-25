/// Shared, deliberately narrow semantic propositions used by source parsers
/// and the provenance evaluator.
///
/// These helpers only return a positive proposition when the surrounding
/// wording is strong enough to support a derived-work decision.  A bare
/// `BEST`, `ベスト`, `新作`, or `コレクション` is intentionally not enough.
enum ScrapeNewMaterialScope { none, bonusOnly, wholeProduction }

final class ScrapeProvenanceSemantics {
  const ScrapeProvenanceSemantics._();

  static final RegExp _wholeProductionPattern = RegExp(
    r'全編\s*(?:完全\s*)?(?:新撮|撮り下ろし)|完全\s*(?:ノーカット\s*)?(?:新撮|撮り下ろし)(?:\s*(?:新作|作品|映像))?|完全\s*(?:新撮|撮り下ろし)\s*(?:の\s*)?(?:大型共演|大共演)',
    caseSensitive: false,
  );

  static final RegExp _bonusOnlyNewMaterialPattern = RegExp(
    r'未公開|新作(?:映像|カット|特典)|撮り下ろし(?:\s*(?:特典|ボーナス|映像|カット))?|新撮(?:\s*(?:特典|ボーナス|映像|カット))?|bonus',
    caseSensitive: false,
  );

  static final RegExp _bestWithBonusPattern = RegExp(
    r'(?:best(?!\s*(?:friend|partner|condition)\b)(?![a-z0-9])|ベスト(?![\s・･]*(?:フレンド|パートナー|コンディション)))[\s・･:：+＋,，、-]{0,8}(?:未公開|新作(?:映像|カット|特典)?|撮り下ろし|新撮|bonus)|(?:未公開|新作(?:映像|カット|特典)?|撮り下ろし|新撮|bonus)[^\n]{0,12}(?:best(?!\s*(?:friend|partner|condition)\b)(?![a-z0-9])|ベスト(?![\s・･]*(?:フレンド|パートナー|コンディション)))',
    caseSensitive: false,
  );

  static final RegExp _provenSharedProductionPattern = RegExp(
    r'全員\s*同時出演|同一シーンで共演|同一撮影企画|同一収録で全員共演|全編\s*(?:完全\s*)?(?:新撮|撮り下ろし)\s*(?:大共演|大型共演)|完全\s*(?:新撮|撮り下ろし)\s*の?\s*(?:大型共演|大共演)',
    caseSensitive: false,
  );

  static final RegExp _sharedProductionHintPattern = RegExp(
    r'共演|同時出演|同じ.*作品|同一.*作品|大共演|豪華共演|コラボ',
    caseSensitive: false,
  );

  static final RegExp _explicitPriorWorkStatementPattern = RegExp(
    r'(?:過去|既存|旧)(?:の)?作(?:品)?\s*(?:\d+\s*(?:本|作品|タイトル))?\s*(?:を|が)?\s*(?:再\s*)?(?:厳選|まとめて|すべて|全て)?\s*(?:収録|収録する|収録済み)|(?:old|previous)\s+(?:works?|titles?)\s+(?:included|collected|reissued|re-released)',
    caseSensitive: false,
  );

  static final RegExp _strongSplitPattern = RegExp(
    r'分割版|分割販売|元作品\s*(?:から|を)\s*分割|個別版|単独版|split\s+(?:edition|from\s+(?:a\s+)?(?:prior|original)\s+work)|(?:prior|original)\s+work\s+(?:split|divided)',
    caseSensitive: false,
  );

  static final RegExp _independentSegmentsPattern = RegExp(
    r'各女優\s*(?:それぞれ\s*)?別作品(?:を|から)?収録|出演者ごとの独立作品|それぞれ別作品から収録|各作品を個別(?:に)?収録|独立した\s*(?:\d+|○)?\s*作品をまとめて収録|独立(?:した)?作品を(?:まとめて)?収録',
    caseSensitive: false,
  );

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
  static ScrapeSemanticProposition? strongReuseProposition(
    Iterable<String> values,
  ) {
    final text = normalize(values.join(' '));
    if (text.isEmpty) return null;
    final patterns = <({RegExp pattern, String ruleId})>[
      (
        pattern: RegExp(
          r'(?:\d+\s*(?:時間|分|hours?|minutes?|h|min)\s*(?:best|ベスト)|(?:best|ベスト)\s*\d+\s*[\s!！・:：,，、-]{0,4}\s*\d+\s*(?:時間|分|hours?|minutes?|h|min)|(?:best|ベスト)[\s!！・:：,，、-]{0,4}\d+\s*(?:時間|分|hours?|minutes?|h|min)|(?:best|ベスト)\s*\d+\s+\d+\s*(?:時間|分|hours?|minutes?|h|min))',
          caseSensitive: false,
        ),
        ruleId: 'semantic_best_runtime_collection',
      ),
      (
        pattern: RegExp(
          r'(?:best|ベスト)\s*\d+\s*(?:人|作品|タイトル|本番|本(?!番)|選)|\d+\s*本番[^\s]{0,8}(?:best|ベスト)|\d+\s*(?:人|作品|タイトル|本(?!番))[^\s]{0,6}(?:best|ベスト)',
          caseSensitive: false,
        ),
        ruleId: 'semantic_best_cast_collection',
      ),
      (
        pattern: RegExp(
          r'(?:best|ベスト)\s*(?:of|collection)|(?:complete|コンプリート)\s*(?:best|ベスト)|(?:best|ベスト)\s*(?:complete|コンプリート)',
          caseSensitive: false,
        ),
        ruleId: 'semantic_best_collection',
      ),
      (
        pattern: RegExp(
          r'(?:永久\s*)?保存版\s*(?:best|ベスト)|(?:best|ベスト)\s*(?:永久\s*)?保存版|(?:厳選|傑作)\s*(?:best|ベスト)|(?:best|ベスト)\s*(?:厳選|傑作)',
          caseSensitive: false,
        ),
        ruleId: 'semantic_best_preserved_collection',
      ),
      (
        pattern: RegExp(
          r'全\s*\d+\s*(?:作品|タイトル|作)|全\s*\d+\s*本(?=\s*(?:収録|全部入り))|全出演作品|全作品|出演作品(?:全部|すべて|全て)|\d+\s*(?:タイトル|作品|本)\s*(?:を\s*)?(?:完全\s*)?(?:全部入り|収録)',
          caseSensitive: false,
        ),
        ruleId: 'semantic_work_count_collection',
      ),
      (
        pattern: RegExp(
          r'デビュー(?:作)?から(?:現在まで|最新作まで|全作品|全出演作品|\d+\s*(?:作品|タイトル|本)\s*(?:を)?収録|厳選収録)|歴代作品|過去作品|既存作品|再収録|厳選収録|名場面集',
          caseSensitive: false,
        ),
        ruleId: 'semantic_retrospective_range',
      ),
    ];
    for (final rule in patterns) {
      final pattern = rule.pattern;
      final match = pattern.firstMatch(text);
      if (match != null) {
        return ScrapeSemanticProposition(
          ruleId: rule.ruleId,
          observedText: match.group(0)!,
        );
      }
    }
    return null;
  }

  static ScrapeSemanticProposition? targetActressBestProposition(
    String value,
    Iterable<String> normalizedTargetNames,
  ) {
    final text = normalize(value);
    for (final name in normalizedTargetNames) {
      final normalizedName = normalize(name);
      if (normalizedName.isEmpty) continue;
      final escaped = RegExp.escape(normalizedName);
      final match = RegExp(
        '$escaped\\s*(?:\\d+\\s*(?:時間|分|hours?|minutes?|h|min)\\s*)?(?:best(?!\\s*(?:friend|partner|condition)\\b)(?![a-z0-9])|ベスト(?![\\s・･]*(?:フレンド|パートナー|コンディション))(?![ぁ-んァ-ン一-龯a-z0-9]))',
        caseSensitive: false,
      ).firstMatch(text);
      if (match != null) {
        return ScrapeSemanticProposition(
          ruleId: 'semantic_target_actress_best',
          observedText: match.group(0)!,
        );
      }
    }
    return null;
  }

  static bool containsReliableOriginal(String value) {
    return newMaterialScope(value) == ScrapeNewMaterialScope.wholeProduction;
  }

  static ScrapeNewMaterialScope newMaterialScope(String value) {
    final text = normalize(value);
    if (_wholeProductionPattern.hasMatch(text)) {
      return ScrapeNewMaterialScope.wholeProduction;
    }
    if (_bonusOnlyNewMaterialPattern.hasMatch(text)) {
      return ScrapeNewMaterialScope.bonusOnly;
    }
    return ScrapeNewMaterialScope.none;
  }

  static bool containsOldMaterialWithNewBonus(String value) {
    final text = normalize(value);
    return newMaterialScope(text) == ScrapeNewMaterialScope.bonusOnly &&
        containsStrongReuseEvidence(text);
  }

  static bool containsStrongReuseEvidence(String value) {
    final text = normalize(value);
    return explicitCompilationLabel(text) != null ||
        strongReuseProposition([text]) != null ||
        containsExplicitPriorWorkStatement(text) ||
        _bestWithBonusPattern.hasMatch(text);
  }

  static bool containsExplicitPriorWorkStatement(String value) {
    return _explicitPriorWorkStatementPattern.hasMatch(normalize(value));
  }

  static bool containsStrongSplitEvidence(String value) {
    return _strongSplitPattern.hasMatch(normalize(value));
  }

  static bool containsIndependentSegments(String value) {
    return _independentSegmentsPattern.hasMatch(normalize(value));
  }

  static bool containsProvenSharedProduction(String value) {
    return _provenSharedProductionPattern.hasMatch(normalize(value));
  }

  static bool containsSharedProductionHint(String value) {
    return _sharedProductionHintPattern.hasMatch(normalize(value));
  }
}

final class ScrapeSemanticProposition {
  const ScrapeSemanticProposition({
    required this.ruleId,
    required this.observedText,
  });

  final String ruleId;
  final String observedText;
}
