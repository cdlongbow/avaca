import '../models/scrape_exclusion_policy.dart';
import '../models/scrape_source_settings.dart';
import 'javbus/prefix_exclusion.dart';
import 'scrape/scrape_models.dart';

class ScrapeEvidenceAtom {
  const ScrapeEvidenceAtom({
    required this.id,
    required this.surfaceId,
    required this.source,
    required this.field,
    required this.kind,
    required this.strength,
    required this.polarity,
    required this.ruleId,
    required this.observedText,
  });

  final String id;
  final String surfaceId;
  final ScrapeSourceId source;
  final String field;
  final ScrapeEvidenceKind kind;
  final ScrapeEvidenceStrength strength;
  final ScrapeEvidencePolarity polarity;
  final String ruleId;
  final String observedText;

  Map<String, Object?> toJson() => {
    'id': id,
    'surfaceId': surfaceId,
    'source': source.storageValue,
    'field': field,
    'kind': kind.name,
    'strength': strength.name,
    'polarity': polarity.name,
    'ruleId': ruleId,
    'observedText': observedText,
  };
}

class ScrapePolicyMatch {
  const ScrapePolicyMatch({
    required this.id,
    required this.type,
    required this.ruleId,
    required this.origin,
    this.matchedValue,
  });

  final String id;
  final String type;
  final String ruleId;
  final ScrapePolicyOrigin origin;
  final String? matchedValue;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'ruleId': ruleId,
    'origin': origin.storageValue,
    if (matchedValue != null) 'matchedValue': matchedValue,
  };
}

class ScrapePolicyDecision {
  const ScrapePolicyDecision({
    required this.finalAction,
    required this.evidenceLevel,
    required this.reasonCodes,
    required this.evidence,
    required this.policyMatches,
    required this.hasConflict,
    required this.snapshotDigest,
  });

  final ScrapeFinalAction finalAction;
  final ScrapeEvidenceLevel evidenceLevel;
  final List<String> reasonCodes;
  final List<ScrapeEvidenceAtom> evidence;
  final List<ScrapePolicyMatch> policyMatches;
  final bool hasConflict;
  final String snapshotDigest;

  bool get reviewRequired => finalAction == ScrapeFinalAction.keepReview;

  String get reason => reasonCodes.join(',');

  Map<String, Object?> toJson() => {
    'finalAction': finalAction.name,
    'evidenceLevel': evidenceLevel.name,
    'reasonCodes': reasonCodes,
    'evidence': evidence.map((item) => item.toJson()).toList(),
    'policyMatches': policyMatches.map((item) => item.toJson()).toList(),
    'hasConflict': hasConflict,
    'snapshotDigest': snapshotDigest,
    'reviewRequired': reviewRequired,
  };
}

/// Performs semantic work-level classification after source details have been
/// fetched and grouped.  Counts, performer identities and actress aliases are
/// intentionally absent from this evaluator.
class ScrapeExclusionPolicyEvaluator {
  ScrapeExclusionPolicyEvaluator(this.snapshot)
    : _excludedPrefixes = PrefixExclusion(snapshot.excludedPrefixes);

  final ScrapePolicySnapshot snapshot;
  final PrefixExclusion _excludedPrefixes;

  /// Prefixes are safe to reject before a detail request only when no exact
  /// allow rule could apply to the same code. Source-specific exact allows
  /// therefore also defer the decision until source details are available.
  bool canPreExcludeCode(String code) {
    final normalized = normalizeScrapePolicyCode(code);
    final hasExactAllow = snapshot.exactAllows.any(
      (rule) => rule.normalizedCode == normalized,
    );
    return !hasExactAllow && _excludedPrefixes.matches(code);
  }

  ScrapePolicyDecision evaluate({
    required String code,
    required List<ScrapeWorkDetails> details,
  }) {
    final surfaces = details.isEmpty
        ? <_PolicySurface>[
            _PolicySurface(
              id: 'unknown:$code',
              source: ScrapeSourceId.javbus,
              code: code,
              title: '',
              series: null,
            ),
          ]
        : [
            for (var index = 0; index < details.length; index++)
              _PolicySurface.fromDetails(details[index], index),
          ];
    final evidence = <ScrapeEvidenceAtom>[];
    final policyMatches = <ScrapePolicyMatch>[];
    var evidenceOrdinal = 0;

    void addEvidence({
      required _PolicySurface surface,
      required String field,
      required ScrapeEvidenceKind kind,
      required ScrapeEvidenceStrength strength,
      required ScrapeEvidencePolarity polarity,
      required String ruleId,
      required String observedText,
    }) {
      evidence.add(
        ScrapeEvidenceAtom(
          id: 'e${evidenceOrdinal++}',
          surfaceId: surface.id,
          source: surface.source,
          field: field,
          kind: kind,
          strength: strength,
          polarity: polarity,
          ruleId: ruleId,
          observedText: _excerpt(observedText),
        ),
      );
    }

    final exactRules = _exactAllowsFor(surfaces);
    if (exactRules.isNotEmpty) {
      for (final exactRule in exactRules) {
        policyMatches.add(
          ScrapePolicyMatch(
            id: 'm${policyMatches.length}',
            type: 'exactAllow',
            ruleId: 'exact_allow',
            origin: ScrapePolicyOrigin.user,
            matchedValue: exactRule.code,
          ),
        );
      }
      final allSurfacesAreCovered = surfaces.every(
        (surface) => exactRules.any(
          (exactRule) => exactRule.matches(
            surface.code,
            sourceId: surface.source.storageValue,
          ),
        ),
      );
      if (allSurfacesAreCovered) {
        return _decision(
          action: ScrapeFinalAction.keep,
          level: ScrapeEvidenceLevel.none,
          reasons: const ['exact_allow'],
          evidence: evidence,
          matches: policyMatches,
        );
      }
      return _decision(
        action: ScrapeFinalAction.keepReview,
        level: ScrapeEvidenceLevel.review,
        reasons: const ['exact_allow_scope_identity_uncertain'],
        evidence: evidence,
        matches: policyMatches,
      );
    }

    if (_excludedPrefixes.matches(code)) {
      policyMatches.add(
        _prefixMatch(
          id: 'm${policyMatches.length}',
          value: code,
          origin: ScrapePolicyOrigin.user,
        ),
      );
      return _decision(
        action: ScrapeFinalAction.exclude,
        level: ScrapeEvidenceLevel.none,
        reasons: const ['prefix_excluded'],
        evidence: evidence,
        matches: policyMatches,
      );
    }

    final family = _managedFamilyFor(code);
    if (family != null) {
      policyMatches.add(
        ScrapePolicyMatch(
          id: 'm${policyMatches.length}',
          type: 'managedFamily',
          ruleId: 'managed_family_${family.family}',
          origin: family.origin,
          matchedValue: family.family,
        ),
      );
    }

    for (final surface in surfaces) {
      _classifySurface(surface, addEvidence);
    }
    final strongCompilation = evidence.any(
      (item) =>
          item.strength == ScrapeEvidenceStrength.strong &&
          item.polarity == ScrapeEvidencePolarity.supportsCompilation,
    );
    final strongOriginal = evidence.any(
      (item) =>
          item.strength == ScrapeEvidenceStrength.strong &&
          item.polarity == ScrapeEvidencePolarity.supportsOriginalWork,
    );
    final hasReviewEvidence = evidence.any(
      (item) => item.strength != ScrapeEvidenceStrength.weak,
    );
    final hasConflict = strongCompilation && strongOriginal;

    if (family?.origin == ScrapePolicyOrigin.user &&
        family?.mode == ManagedFamilyMode.excludeAll) {
      return _decision(
        action: ScrapeFinalAction.exclude,
        level: ScrapeEvidenceLevel.none,
        reasons: const ['managed_family_exclude_all'],
        evidence: evidence,
        matches: policyMatches,
      );
    }
    if (hasConflict) {
      return _decision(
        action: ScrapeFinalAction.keepReview,
        level: ScrapeEvidenceLevel.strong,
        reasons: const ['source_evidence_conflict'],
        evidence: evidence,
        matches: policyMatches,
        hasConflict: true,
      );
    }
    if (strongCompilation) {
      return _decision(
        action: ScrapeFinalAction.exclude,
        level: ScrapeEvidenceLevel.strong,
        reasons: const ['strong_compilation_evidence'],
        evidence: evidence,
        matches: policyMatches,
      );
    }
    if (strongOriginal) {
      return _decision(
        action: family?.mode == ManagedFamilyMode.reviewPrior
            ? ScrapeFinalAction.keepReview
            : ScrapeFinalAction.keep,
        level: family?.mode == ManagedFamilyMode.reviewPrior
            ? ScrapeEvidenceLevel.review
            : ScrapeEvidenceLevel.strong,
        reasons: [
          'explicit_original_work',
          if (family?.mode == ManagedFamilyMode.reviewPrior)
            'managed_family_review_prior',
        ],
        evidence: evidence,
        matches: policyMatches,
      );
    }
    if (family?.mode == ManagedFamilyMode.reviewPrior || hasReviewEvidence) {
      return _decision(
        action: ScrapeFinalAction.keepReview,
        level: hasReviewEvidence
            ? ScrapeEvidenceLevel.review
            : ScrapeEvidenceLevel.none,
        reasons: [
          if (hasReviewEvidence) 'review_evidence',
          if (family?.mode == ManagedFamilyMode.reviewPrior)
            'managed_family_review_prior',
        ],
        evidence: evidence,
        matches: policyMatches,
      );
    }
    return _decision(
      action: ScrapeFinalAction.keep,
      level: evidence.isEmpty
          ? ScrapeEvidenceLevel.none
          : ScrapeEvidenceLevel.review,
      reasons: const ['default_keep'],
      evidence: evidence,
      matches: policyMatches,
    );
  }

  ScrapePolicyDecision _decision({
    required ScrapeFinalAction action,
    required ScrapeEvidenceLevel level,
    required List<String> reasons,
    required List<ScrapeEvidenceAtom> evidence,
    required List<ScrapePolicyMatch> matches,
    bool hasConflict = false,
  }) {
    return ScrapePolicyDecision(
      finalAction: action,
      evidenceLevel: level,
      reasonCodes: List.unmodifiable(reasons),
      evidence: List.unmodifiable(evidence),
      policyMatches: List.unmodifiable(matches),
      hasConflict: hasConflict,
      snapshotDigest: snapshot.snapshotDigest,
    );
  }

  ScrapePolicyMatch _prefixMatch({
    required String id,
    required String value,
    required ScrapePolicyOrigin origin,
  }) => ScrapePolicyMatch(
    id: id,
    type: 'prefixExclusion',
    ruleId: 'prefix_exclusion',
    origin: origin,
    matchedValue: value,
  );

  ScrapeManagedFamilyPolicy? _managedFamilyFor(String code) {
    final normalized = normalizeScrapePolicyCode(code);
    for (final policy in snapshot.managedFamilies) {
      if (normalized == policy.family ||
          normalized.startsWith('${policy.family}-') ||
          normalized.startsWith('${policy.family}_')) {
        return policy;
      }
    }
    return null;
  }

  List<ScrapeExactAllowRule> _exactAllowsFor(List<_PolicySurface> surfaces) {
    return snapshot.exactAllows
        .where(
          (rule) => surfaces.any(
            (surface) => rule.matches(
              surface.code,
              sourceId: surface.source.storageValue,
            ),
          ),
        )
        .toList(growable: false);
  }

  void _classifySurface(
    _PolicySurface surface,
    void Function({
      required _PolicySurface surface,
      required String field,
      required ScrapeEvidenceKind kind,
      required ScrapeEvidenceStrength strength,
      required ScrapeEvidencePolarity polarity,
      required String ruleId,
      required String observedText,
    })
    addEvidence,
  ) {
    final title = surface.title;
    final series = surface.series ?? '';
    final text = '$title $series'.trim();
    if (text.isEmpty) return;

    final strongCompilationPatterns =
        <({String pattern, String ruleId, ScrapeEvidenceKind kind})>[
          (
            pattern: r'総集編|総集成',
            ruleId: 'title_compilation',
            kind: ScrapeEvidenceKind.explicitCompilation,
          ),
          (
            pattern: r'オムニバス|作品集|アンソロジー|anthology|collection',
            ruleId: 'title_anthology',
            kind: ScrapeEvidenceKind.anthologyCollection,
          ),
          (
            pattern: r'選集|選輯',
            ruleId: 'title_selection_collection',
            kind: ScrapeEvidenceKind.explicitCompilation,
          ),
        ];
    for (final candidate in strongCompilationPatterns) {
      final match = RegExp(
        candidate.pattern,
        caseSensitive: false,
      ).firstMatch(text);
      if (match != null) {
        addEvidence(
          surface: surface,
          field: 'title',
          kind: candidate.kind,
          strength: ScrapeEvidenceStrength.strong,
          polarity: ScrapeEvidencePolarity.supportsCompilation,
          ruleId: candidate.ruleId,
          observedText: match.group(0)!,
        );
      }
    }

    final hasPriorWorkMarker = RegExp(
      r'(?:全出演作品|全単体(?:タイトル|作品)|最新\s*\d+\s*(?:タイトル|作品)|既存作品|過去作品|引退.*(?:best|ベスト)|best.*(?:of|作品|タイトル)|(?:作品|タイトル).*complete|complete.*(?:作品|タイトル))',
      caseSensitive: false,
    ).hasMatch(text);
    final bestOrComplete = RegExp(
      r'best|ベスト|complete|コンプリート',
      caseSensitive: false,
    ).firstMatch(text);
    if (hasPriorWorkMarker && bestOrComplete != null) {
      addEvidence(
        surface: surface,
        field: 'title',
        kind: text.contains('complete') || text.contains('コンプリート')
            ? ScrapeEvidenceKind.completePriorWorks
            : ScrapeEvidenceKind.bestOfPriorWorks,
        strength: ScrapeEvidenceStrength.strong,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'title_prior_work_collection',
        observedText: bestOrComplete.group(0)!,
      );
    }

    final original = RegExp(
      r'完全ノーカット|新撮|撮り下ろし|原生|新作',
      caseSensitive: false,
    ).firstMatch(text);
    if (original != null) {
      addEvidence(
        surface: surface,
        field: 'title',
        kind: ScrapeEvidenceKind.explicitOriginalWork,
        strength: ScrapeEvidenceStrength.strong,
        polarity: ScrapeEvidencePolarity.supportsOriginalWork,
        ruleId: 'title_original_work',
        observedText: original.group(0)!,
      );
    }

    final edited = RegExp(
      r'編集|マルチアングル編集',
      caseSensitive: false,
    ).firstMatch(text);
    if (edited != null) {
      addEvidence(
        surface: surface,
        field: 'title',
        kind: ScrapeEvidenceKind.editedPresentation,
        strength: ScrapeEvidenceStrength.medium,
        polarity: ScrapeEvidencePolarity.neutral,
        ruleId: 'title_edited_presentation',
        observedText: edited.group(0)!,
      );
    }

    final viewpoint = RegExp(
      r'選択型|視点選択型|視点',
      caseSensitive: false,
    ).firstMatch(text);
    if (viewpoint != null) {
      addEvidence(
        surface: surface,
        field: 'title',
        kind: ScrapeEvidenceKind.viewpointSelection,
        strength: ScrapeEvidenceStrength.weak,
        polarity: ScrapeEvidencePolarity.neutral,
        ruleId: 'title_viewpoint_presentation',
        observedText: viewpoint.group(0)!,
      );
    }

    final highVolume = RegExp(
      r'\d+\s*連発|\d+\s*名|厳選|calendar|カレンダー|SP',
      caseSensitive: false,
    ).firstMatch(text);
    if (highVolume != null &&
        !strongCompilationPatterns.any(
          (candidate) =>
              RegExp(candidate.pattern, caseSensitive: false).hasMatch(text),
        )) {
      addEvidence(
        surface: surface,
        field: 'title',
        kind: ScrapeEvidenceKind.highVolumePresentation,
        strength: ScrapeEvidenceStrength.medium,
        polarity: ScrapeEvidencePolarity.neutral,
        ruleId: 'title_high_volume_presentation',
        observedText: highVolume.group(0)!,
      );
    }
  }
}

class _PolicySurface {
  const _PolicySurface({
    required this.id,
    required this.source,
    required this.code,
    required this.title,
    required this.series,
  });

  final String id;
  final ScrapeSourceId source;
  final String code;
  final String title;
  final String? series;

  factory _PolicySurface.fromDetails(
    ScrapeWorkDetails details,
    int index,
  ) => _PolicySurface(
    id: '${details.source.storageValue}:$index:${details.sourceUri ?? details.code}',
    source: details.source,
    code: details.rawCode ?? details.code,
    title: details.title,
    series: details.series,
  );
}

String _excerpt(String value) {
  final normalized = value.trim();
  return normalized.length <= 120 ? normalized : normalized.substring(0, 120);
}
