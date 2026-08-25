import '../models/scrape_exclusion_policy.dart';
import '../models/scrape_source_settings.dart';
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
    required this.provenanceClass,
    required this.evidenceLevel,
    required this.reasonCodes,
    required this.evidence,
    required this.policyMatches,
    required this.hasConflict,
    required this.snapshotDigest,
  });

  final ScrapeFinalAction finalAction;
  final ScrapeProvenanceClass provenanceClass;
  final ScrapeEvidenceLevel evidenceLevel;
  final List<String> reasonCodes;
  final List<ScrapeEvidenceAtom> evidence;
  final List<ScrapePolicyMatch> policyMatches;
  final bool hasConflict;
  final String snapshotDigest;

  bool get reviewRequired => finalAction == ScrapeFinalAction.keepReview;

  ScrapeProvenanceVerdict get verdict => switch (finalAction) {
    ScrapeFinalAction.keep => ScrapeProvenanceVerdict.keep,
    ScrapeFinalAction.exclude => ScrapeProvenanceVerdict.exclude,
    ScrapeFinalAction.keepReview => ScrapeProvenanceVerdict.keepUncertain,
  };

  String get reason => reasonCodes.join(',');

  Map<String, Object?> toJson() => {
    'finalAction': finalAction.name,
    'provenanceClass': provenanceClass.name,
    'evidenceLevel': evidenceLevel.name,
    'reasonCodes': reasonCodes,
    'evidence': evidence.map((item) => item.toJson()).toList(),
    'policyMatches': policyMatches.map((item) => item.toJson()).toList(),
    'hasConflict': hasConflict,
    'snapshotDigest': snapshotDigest,
    'reviewRequired': reviewRequired,
  };
}

/// Classifies work provenance from concrete lineage and production facts.
///
/// Prefixes and performer counts are intentionally not part of the automatic
/// decision. If the available facts cannot establish reuse, the evaluator
/// returns [ScrapeFinalAction.keepReview].
class ScrapeExclusionPolicyEvaluator {
  ScrapeExclusionPolicyEvaluator(this.snapshot);

  final ScrapePolicySnapshot snapshot;

  /// Automatic exclusion is detail/evidence based. There is no safe
  /// pre-detail prefix exclusion path anymore.
  bool canPreExcludeCode(String code) => false;

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
              details: null,
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
    final automaticClass = _classForEvidence(evidence, surfaces);

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

    var automaticAction = ScrapeFinalAction.keepReview;
    var automaticReasons = <String>[];
    var automaticLevel = ScrapeEvidenceLevel.none;
    if (hasConflict) {
      automaticReasons = ['source_evidence_conflict'];
      automaticLevel = ScrapeEvidenceLevel.strong;
    } else if (strongCompilation) {
      automaticAction = snapshot.autoExcludeDerivedWorks
          ? ScrapeFinalAction.exclude
          : ScrapeFinalAction.keepReview;
      automaticReasons = [
        if (snapshot.autoExcludeDerivedWorks)
          'strong_compilation_evidence'
        else
          'derived_work_filter_disabled',
      ];
      automaticLevel = ScrapeEvidenceLevel.strong;
    } else if (strongOriginal) {
      automaticAction = ScrapeFinalAction.keep;
      automaticReasons = const ['explicit_original_work'];
      automaticLevel = ScrapeEvidenceLevel.strong;
    } else if (evidence.any(
      (item) => item.kind == ScrapeEvidenceKind.viewpointSelection,
    )) {
      automaticAction = ScrapeFinalAction.keep;
      automaticReasons = const ['safe_presentation_context'];
      automaticLevel = ScrapeEvidenceLevel.none;
    } else if (family?.mode == ManagedFamilyMode.reviewPrior ||
        hasReviewEvidence) {
      automaticReasons = [
        if (hasReviewEvidence) 'review_evidence',
        if (!hasReviewEvidence && family?.mode == ManagedFamilyMode.reviewPrior)
          'review_evidence',
        if (family?.mode == ManagedFamilyMode.reviewPrior)
          'managed_family_review_prior',
      ];
      automaticLevel = hasReviewEvidence
          ? ScrapeEvidenceLevel.review
          : ScrapeEvidenceLevel.none;
    } else {
      automaticReasons = const ['unknown_provenance'];
    }

    // Legacy managed-family exclusion is retained only as an explicit user
    // rule. It is never inferred from a family/prefix by itself.
    if (family?.origin == ScrapePolicyOrigin.user &&
        family?.mode == ManagedFamilyMode.excludeAll) {
      automaticAction = ScrapeFinalAction.exclude;
      automaticReasons = const ['managed_family_exclude_all'];
      automaticLevel = ScrapeEvidenceLevel.none;
    }

    final exactAllows = _exactAllowsFor(surfaces);
    final exactDenies = _exactDeniesFor(surfaces);
    for (final exactRule in exactAllows) {
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
    for (final exactRule in exactDenies) {
      policyMatches.add(
        ScrapePolicyMatch(
          id: 'm${policyMatches.length}',
          type: 'exactDeny',
          ruleId: 'exact_deny',
          origin: ScrapePolicyOrigin.user,
          matchedValue: exactRule.code,
        ),
      );
    }

    // Explicit manual rules are deliberately applied after automatic
    // classification. Conflicting manual rules fail open to review.
    final allSurfacesAllowed =
        exactAllows.isNotEmpty &&
        surfaces.every(
          (surface) => exactAllows.any(
            (rule) => rule.matches(
              surface.code,
              sourceId: surface.source.storageValue,
            ),
          ),
        );
    final allSurfacesDenied =
        exactDenies.isNotEmpty &&
        surfaces.every(
          (surface) => exactDenies.any(
            (rule) => rule.matches(
              surface.code,
              sourceId: surface.source.storageValue,
            ),
          ),
        );
    if (allSurfacesAllowed && allSurfacesDenied) {
      return _decision(
        action: ScrapeFinalAction.keepReview,
        classValue: ScrapeProvenanceClass.unknown,
        level: ScrapeEvidenceLevel.strong,
        reasons: const ['manual_override_conflict'],
        evidence: evidence,
        matches: policyMatches,
        hasConflict: true,
      );
    }
    if (allSurfacesAllowed) {
      return _decision(
        action: ScrapeFinalAction.keep,
        classValue: automaticClass,
        level: automaticLevel,
        reasons: const ['exact_allow'],
        evidence: evidence,
        matches: policyMatches,
      );
    }
    if (allSurfacesDenied) {
      return _decision(
        action: ScrapeFinalAction.exclude,
        classValue: automaticClass,
        level: automaticLevel,
        reasons: const ['exact_deny'],
        evidence: evidence,
        matches: policyMatches,
      );
    }
    if (exactAllows.isNotEmpty || exactDenies.isNotEmpty) {
      automaticAction = ScrapeFinalAction.keepReview;
      automaticReasons = const ['manual_rule_scope_uncertain'];
      automaticLevel = ScrapeEvidenceLevel.review;
    }

    return _decision(
      action: automaticAction,
      classValue: automaticClass,
      level: automaticLevel,
      reasons: automaticReasons,
      evidence: evidence,
      matches: policyMatches,
      hasConflict: hasConflict,
    );
  }

  ScrapePolicyDecision _decision({
    required ScrapeFinalAction action,
    required ScrapeProvenanceClass classValue,
    required ScrapeEvidenceLevel level,
    required List<String> reasons,
    required List<ScrapeEvidenceAtom> evidence,
    required List<ScrapePolicyMatch> matches,
    bool hasConflict = false,
  }) {
    return ScrapePolicyDecision(
      finalAction: action,
      provenanceClass: classValue,
      evidenceLevel: level,
      reasonCodes: List.unmodifiable(reasons),
      evidence: List.unmodifiable(evidence),
      policyMatches: List.unmodifiable(matches),
      hasConflict: hasConflict,
      snapshotDigest: snapshot.snapshotDigest,
    );
  }

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

  List<ScrapeExactDenyRule> _exactDeniesFor(List<_PolicySurface> surfaces) {
    return snapshot.exactDenies
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
    final details = surface.details;
    if (details == null) return;
    final facts = details.provenanceFacts;
    final includedWorks = [
      ...details.includedWorks,
      ...facts.includedWorks,
    ].where((value) => value.trim().isNotEmpty).toSet();
    final parentWorks = [
      ...details.parentWorks,
      ...facts.parentWorks,
    ].where((value) => value.trim().isNotEmpty).toSet();
    final genres = [...details.genres, ...facts.genres, ...facts.tags];
    final text = [
      details.title,
      details.series ?? '',
      details.description ?? '',
      facts.description ?? '',
      ...genres,
    ].join(' ').trim();

    void strong({
      required ScrapeEvidenceKind kind,
      required ScrapeEvidencePolarity polarity,
      required String ruleId,
      required String observedText,
      String field = 'provenance',
    }) {
      addEvidence(
        surface: surface,
        field: field,
        kind: kind,
        strength: ScrapeEvidenceStrength.strong,
        polarity: polarity,
        ruleId: ruleId,
        observedText: observedText,
      );
    }

    if (includedWorks.isNotEmpty || facts.containsPriorWorks == true) {
      strong(
        kind: ScrapeEvidenceKind.includedPriorWorks,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_includes_prior_works',
        observedText: includedWorks.isEmpty
            ? 'source says prior works are included'
            : includedWorks.join(', '),
      );
    }
    if (parentWorks.isNotEmpty || facts.extractedFromPriorWork == true) {
      strong(
        kind: ScrapeEvidenceKind.extractedFromPriorWork,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_parent_work',
        observedText: parentWorks.isEmpty
            ? 'source says extracted from a parent work'
            : parentWorks.join(', '),
      );
    }
    if (facts.splitFromPriorWork == true) {
      strong(
        kind: ScrapeEvidenceKind.splitFromPriorWork,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_split_from_prior_work',
        observedText: 'split or individual-performer edition',
      );
    }
    if (facts.packageOfIndependentWorks == true) {
      strong(
        kind: ScrapeEvidenceKind.packageEdition,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_independent_package',
        observedText: 'independent works packaged together',
      );
    }
    if (facts.oldMaterialWithNewBonus == true) {
      strong(
        kind: ScrapeEvidenceKind.mixedOldNew,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_old_material_bonus',
        observedText: 'old material with new bonus footage',
      );
    }
    if (facts.reissue == true) {
      strong(
        kind: ScrapeEvidenceKind.reissue,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_reissue',
        observedText: 'reissue or revival of an existing work',
      );
    }
    if (facts.remaster == true) {
      strong(
        kind: ScrapeEvidenceKind.remaster,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_remaster',
        observedText: 'remaster of an existing work',
      );
    }
    if (facts.reedited == true) {
      strong(
        kind: ScrapeEvidenceKind.reedit,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_reedit',
        observedText: 're-edit of an existing work',
      );
    }
    if (facts.coPerformance == ScrapeCoPerformance.independentSegments ||
        details.coPerformance == ScrapeCoPerformance.independentSegments) {
      strong(
        kind: ScrapeEvidenceKind.independentSegments,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'production_independent_segments',
        observedText: 'independent performer segments',
      );
    }

    final compilation = RegExp(
      r'総集編|総集篇|総集成|オムニバス|アンソロジー|作品集|選集|傑作選|名場面',
      caseSensitive: false,
    ).firstMatch(text);
    if (compilation != null) {
      strong(
        kind: compilation.group(0)!.contains('オムニバス')
            ? ScrapeEvidenceKind.omnibus
            : ScrapeEvidenceKind.explicitCompilation,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'semantic_compilation_label',
        observedText: compilation.group(0)!,
        field: 'title_or_metadata',
      );
    }

    final priorMarker = RegExp(
      r'全\s*\d+\s*(?:作品|タイトル)|全出演作品|全作品|出演作品|\d+\s*タイトル全部入り|\d+\s*本収録|過去作品|既存作品|収録作品|収録タイトル|厳選収録|best\s*(?:of|collection)|ベスト.*(?:作品|タイトル|収録)|(?:作品|タイトル).*ベスト',
      caseSensitive: false,
    ).firstMatch(text);
    final bestMarker = RegExp(
      r'best|ベスト|コンプリート|complete',
      caseSensitive: false,
    ).firstMatch(text);
    if (priorMarker != null && bestMarker != null) {
      strong(
        kind: bestMarker.group(0)!.toLowerCase().contains('complete')
            ? ScrapeEvidenceKind.completePriorWorks
            : ScrapeEvidenceKind.bestOfPriorWorks,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'semantic_prior_work_collection',
        observedText: '${priorMarker.group(0)} ${bestMarker.group(0)}',
        field: 'title_or_metadata',
      );
    }

    final reissue = RegExp(
      r'再発売|復刻|リマスター|再編集|再収録|reissue|remaster|re-?edit',
      caseSensitive: false,
    ).firstMatch(text);
    if (reissue != null) {
      final value = reissue.group(0)!;
      final kind =
          value.contains('リマスター') || value.toLowerCase().contains('remaster')
          ? ScrapeEvidenceKind.remaster
          : value.contains('再編集') || value.toLowerCase().contains('edit')
          ? ScrapeEvidenceKind.reedit
          : ScrapeEvidenceKind.reissue;
      strong(
        kind: kind,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'semantic_reuse_proposition',
        observedText: value,
        field: 'title_or_metadata',
      );
    }

    final oldBonus =
        RegExp(r'未公開|bonus', caseSensitive: false).hasMatch(text) &&
        RegExp(r'過去|既存|収録|再収録|old', caseSensitive: false).hasMatch(text);
    if (oldBonus) {
      strong(
        kind: ScrapeEvidenceKind.mixedOldNew,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'semantic_old_material_bonus',
        observedText: 'old material plus bonus footage',
        field: 'title_or_metadata',
      );
    }

    if (facts.explicitOriginalProduction == true) {
      strong(
        kind: ScrapeEvidenceKind.explicitOriginalWork,
        polarity: ScrapeEvidencePolarity.supportsOriginalWork,
        ruleId: 'source_explicit_original_production',
        observedText: 'source says this is a new production',
      );
    }
    final original = RegExp(
      r'新撮|撮り下ろし|新作',
      caseSensitive: false,
    ).firstMatch(text);
    if (original != null) {
      strong(
        kind: ScrapeEvidenceKind.explicitOriginalWork,
        polarity: ScrapeEvidencePolarity.supportsOriginalWork,
        ruleId: 'semantic_original_production',
        observedText: original.group(0)!,
        field: 'title_or_metadata',
      );
    }
    if (facts.coPerformance == ScrapeCoPerformance.sharedProduction ||
        details.coPerformance == ScrapeCoPerformance.sharedProduction) {
      strong(
        kind: ScrapeEvidenceKind.genuineCoPerformance,
        polarity: ScrapeEvidencePolarity.supportsOriginalWork,
        ruleId: 'production_shared_co_performance',
        observedText: 'performers participate in one shared production',
      );
    }

    // Unsafe words are recorded as context only; they never independently
    // cause EXCLUDE.
    final neutral = RegExp(
      r'編集|マルチアングル|完全版|COMPLETE|4K|8K|ノーカット|未公開|周年|スペシャル|復活|コレクション',
      caseSensitive: false,
    ).firstMatch(text);
    final viewpoint = RegExp(
      r'選択型|視点選択|同時多発.*視点',
      caseSensitive: false,
    ).firstMatch(text);
    if (viewpoint != null) {
      addEvidence(
        surface: surface,
        field: 'title_or_metadata',
        kind: ScrapeEvidenceKind.viewpointSelection,
        strength: ScrapeEvidenceStrength.weak,
        polarity: ScrapeEvidencePolarity.neutral,
        ruleId: 'semantic_safe_viewpoint_context',
        observedText: viewpoint.group(0)!,
      );
    }
    if (neutral != null) {
      addEvidence(
        surface: surface,
        field: 'title_or_metadata',
        kind: ScrapeEvidenceKind.editedPresentation,
        strength: ScrapeEvidenceStrength.weak,
        polarity: ScrapeEvidencePolarity.neutral,
        ruleId: 'semantic_unsafe_standalone_context',
        observedText: neutral.group(0)!,
      );
    }
  }

  ScrapeProvenanceClass _classForEvidence(
    List<ScrapeEvidenceAtom> evidence,
    List<_PolicySurface> surfaces,
  ) {
    final kinds = evidence
        .where(
          (item) => item.polarity == ScrapeEvidencePolarity.supportsCompilation,
        )
        .map((item) => item.kind)
        .toSet();
    if (kinds.contains(ScrapeEvidenceKind.splitFromPriorWork)) {
      return ScrapeProvenanceClass.derivedSplit;
    }
    if (kinds.contains(ScrapeEvidenceKind.extractedFromPriorWork)) {
      return ScrapeProvenanceClass.derivedExtract;
    }
    if (kinds.contains(ScrapeEvidenceKind.reissue)) {
      return ScrapeProvenanceClass.derivedReissue;
    }
    if (kinds.contains(ScrapeEvidenceKind.remaster)) {
      return ScrapeProvenanceClass.derivedRemaster;
    }
    if (kinds.contains(ScrapeEvidenceKind.reedit)) {
      return ScrapeProvenanceClass.derivedReedit;
    }
    if (kinds.contains(ScrapeEvidenceKind.mixedOldNew)) {
      return ScrapeProvenanceClass.mixedOldNew;
    }
    if (kinds.isNotEmpty) {
      return kinds.contains(ScrapeEvidenceKind.independentSegments)
          ? ScrapeProvenanceClass.derivedBundle
          : ScrapeProvenanceClass.derivedOmnibus;
    }
    final hasOriginal = evidence.any(
      (item) => item.polarity == ScrapeEvidencePolarity.supportsOriginalWork,
    );
    final hasCoPerformance = evidence.any(
      (item) => item.kind == ScrapeEvidenceKind.genuineCoPerformance,
    );
    if (hasOriginal) {
      final multi =
          surfaces.any(
            (surface) => (surface.details?.performers?.length ?? 0) > 1,
          ) ||
          hasCoPerformance;
      return multi
          ? ScrapeProvenanceClass.originalCostar
          : ScrapeProvenanceClass.originalSolo;
    }
    return ScrapeProvenanceClass.unknown;
  }
}

class _PolicySurface {
  const _PolicySurface({
    required this.id,
    required this.source,
    required this.code,
    required this.details,
  });

  final String id;
  final ScrapeSourceId source;
  final String code;
  final ScrapeWorkDetails? details;

  factory _PolicySurface.fromDetails(
    ScrapeWorkDetails details,
    int index,
  ) => _PolicySurface(
    id: '${details.source.storageValue}:$index:${details.sourceUri ?? details.code}',
    source: details.source,
    code: details.rawCode ?? details.code,
    details: details,
  );
}

String _excerpt(String value) {
  final normalized = value.trim();
  return normalized.length <= 120 ? normalized : normalized.substring(0, 120);
}
