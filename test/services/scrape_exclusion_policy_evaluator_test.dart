import 'package:avaca/models/scrape_exclusion_policy.dart';
import 'package:avaca/models/scrape_rules.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/models/work.dart';
import 'package:avaca/services/scrape/scrape_classification_context.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/services/scrape_exclusion_policy_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps edited and viewpoint presentations for review-safe handling', () {
    final evaluator = _evaluator();

    expect(
      evaluator
          .evaluate(
            code: '3DSVR-485',
            details: [_details('3DSVR-485', 'マルチアングル編集')],
          )
          .finalAction,
      ScrapeFinalAction.keepReview,
    );
    expect(
      evaluator
          .evaluate(
            code: '3DSVR-531',
            details: [_details('3DSVR-531', 'マルチアングル選択型')],
          )
          .finalAction,
      ScrapeFinalAction.keep,
    );
    expect(
      evaluator
          .evaluate(
            code: '3DSVR-436',
            details: [_details('3DSVR-436', '同時多発×3視点選択型')],
          )
          .finalAction,
      ScrapeFinalAction.keep,
    );
  });

  test('excludes explicit compilation evidence', () {
    final decision = _evaluator().evaluate(
      code: '3DSVR-737',
      details: [_details('3DSVR-737', '総集編')],
    );

    expect(decision.finalAction, ScrapeFinalAction.exclude);
    expect(decision.evidenceLevel, ScrapeEvidenceLevel.strong);
    expect(decision.reasonCodes, contains('strong_compilation_evidence'));
  });

  test(
    'does not assign a family-specific verdict to OFJE or unknown families',
    () {
      final ofje = _evaluator().evaluate(
        code: 'OFJE-605',
        details: [_details('OFJE-605', '普通の単体作品')],
      );
      final unknownFamily = _evaluator().evaluate(
        code: 'MIZD-605',
        details: [_details('MIZD-605', '普通の單體作品')],
      );

      expect(ofje.finalAction, ScrapeFinalAction.keepReview);
      expect(ofje.reasonCodes, ['unknown_provenance']);
      expect(ofje.policyMatches, isEmpty);
      expect(unknownFamily.reasonCodes, ofje.reasonCodes);
      expect(unknownFamily.finalAction, ofje.finalAction);
    },
  );

  test(
    'allows an exact surface even when its title looks like a compilation',
    () {
      final decision = _evaluator(
        exactAllows: const [ScrapeExactAllowRule(code: 'OFJE-605')],
      ).evaluate(code: 'OFJE-605', details: [_details('OFJE-605', '総集編')]);

      expect(decision.finalAction, ScrapeFinalAction.keep);
      expect(decision.reasonCodes, ['exact_allow']);
    },
  );

  test('keeps explicit original work and excludes prior-work collections', () {
    final original = _evaluator().evaluate(
      code: 'MOON-001',
      details: [_details('MOON-001', '完全ノーカット撮り下ろし')],
    );
    final prior = _evaluator().evaluate(
      code: 'MOON-002',
      details: [_details('MOON-002', '全出演作品 BEST')],
    );

    expect(original.finalAction, ScrapeFinalAction.keep);
    expect(prior.finalAction, ScrapeFinalAction.exclude);
  });

  test('does not use performer count as a type predicate', () {
    final decision = _evaluator().evaluate(
      code: 'MIX-001',
      details: [_details('MIX-001', '単体作品', performerCount: 30)],
    );

    expect(decision.finalAction, ScrapeFinalAction.keepReview);
    expect(decision.verdict, ScrapeProvenanceVerdict.keepUncertain);
  });

  test('does not infer shared production from cast count', () {
    final decision = _evaluator().evaluate(
      code: 'MIX-CAST-001',
      details: [
        _details(
          'MIX-CAST-001',
          '多人作品',
          performers: const [
            WorkPerformer(name: '女優一'),
            WorkPerformer(name: '女優二'),
          ],
        ),
      ],
    );

    expect(decision.finalAction, ScrapeFinalAction.keepReview);
    expect(decision.provenanceClass, ScrapeProvenanceClass.unknown);
  });

  test('uses review when source surfaces conflict', () {
    final decision = _evaluator().evaluate(
      code: 'MIX-002',
      details: [
        _details('MIX-002', '総集編'),
        _details('MIX-002', '完全ノーカット撮り下ろし'),
      ],
    );

    expect(decision.finalAction, ScrapeFinalAction.keepReview);
    expect(decision.hasConflict, isTrue);
    expect(decision.reasonCodes, ['source_evidence_conflict']);
  });

  test(
    'requires high-confidence context around BEST and safe title tokens',
    () {
      for (final title in const [
        'BEST',
        'ベスト',
        '完全版',
        'マルチアングル',
        '4K COLLECTION',
        '新作',
      ]) {
        final decision = _evaluator().evaluate(
          code: 'SAFE-${title.hashCode}',
          details: [_details('SAFE-${title.hashCode}', title)],
        );
        expect(
          decision.finalAction,
          isNot(ScrapeFinalAction.exclude),
          reason: title,
        );
      }

      for (final title in const [
        '100本番BEST！8時間！',
        '制服限定BEST30 43時間',
        'BEST11人',
        'BEST COLLECTION',
      ]) {
        final decision = _evaluator().evaluate(
          code: 'DERIVED-${title.hashCode}',
          details: [_details('DERIVED-${title.hashCode}', title)],
        );
        expect(decision.finalAction, ScrapeFinalAction.exclude, reason: title);
      }
    },
  );

  test('covers the adversarial semantic safety matrix', () {
    for (final title in const [
      '全4本番',
      '全3本番ぶっ通しSEX',
      '全5本番完全新撮',
      'BEST',
      'ベスト',
      'BEST FRIEND',
      '彼女は僕のベストフレンド',
      '最高のベストコンディションSEX',
      'デビュー作から1年、さらに進化した彼女',
      'デビュー作から半年ぶりの再会',
      '大共演',
      '豪華大共演',
      '20人大共演',
      '共演スペシャル',
      'コラボ',
      'ストーリー作品',
      '完全版',
      '4K COLLECTION',
      'マルチアングル編集',
    ]) {
      final decision = _evaluator().evaluate(
        code: 'SAFE-${title.hashCode}',
        details: [_details('SAFE-${title.hashCode}', title)],
      );
      expect(
        decision.finalAction,
        isNot(ScrapeFinalAction.exclude),
        reason: title,
      );
    }
  });

  test('covers the high-confidence derived semantic matrix', () {
    for (final title in const [
      '8時間BEST',
      'BEST11人',
      '永久保存版 8時間ベスト',
      '制服限定BEST30 43時間',
      '100本番BEST！8時間！',
      'BEST COLLECTION',
      'COMPLETE BEST',
      '全12作品',
      '全12タイトル',
      '全12タイトル全部入り',
      '全4本収録',
      '12作品収録',
      '4タイトル全部入り',
      'デビュー作から現在まで',
      'デビュー作から全出演作品を収録',
      '過去作品を厳選収録',
      '総集編',
      '名場面集',
      'BEST・未公開新作映像収録',
      'BEST・撮り下ろし特典映像付き',
      '総集編＋新撮ボーナス映像',
      '過去作品収録＋新作カット',
      '全作品収録＋撮り下ろし映像',
      'COMPLETE BEST＋新撮特典',
    ]) {
      final decision = _evaluator().evaluate(
        code: 'DERIVED-MATRIX-${title.hashCode}',
        details: [_details('DERIVED-MATRIX-${title.hashCode}', title)],
      );
      expect(decision.finalAction, ScrapeFinalAction.exclude, reason: title);
      expect(decision.evidence, isNotEmpty, reason: title);
    }
  });

  test('uses explicit target identity for actress BEST semantics', () {
    final naganoContext = const ScrapeClassificationContext(
      targetActressName: '永野いち夏',
    );
    final aliasContext = const ScrapeClassificationContext(
      targetActressName: 'A',
      targetAliases: ['B'],
    );
    final genericNameContext = const ScrapeClassificationContext(
      targetActressName: '女優名',
    );

    expect(
      _evaluator()
          .evaluate(
            code: 'TARGET-NAGANO',
            details: [_details('TARGET-NAGANO', '永野いち夏 BEST')],
            classificationContext: naganoContext,
          )
          .finalAction,
      ScrapeFinalAction.exclude,
    );
    expect(
      _evaluator()
          .evaluate(
            code: 'TARGET-GENERIC-NAME',
            details: [_details('TARGET-GENERIC-NAME', '女優名 BEST')],
            classificationContext: genericNameContext,
          )
          .finalAction,
      ScrapeFinalAction.exclude,
    );
    expect(
      _evaluator()
          .evaluate(
            code: 'TARGET-NAGANO-RUNTIME',
            details: [_details('TARGET-NAGANO-RUNTIME', '永野いち夏 12時間BEST')],
            classificationContext: naganoContext,
          )
          .finalAction,
      ScrapeFinalAction.exclude,
    );
    expect(
      _evaluator()
          .evaluate(
            code: 'TARGET-AIKA-WRONG',
            details: [_details('TARGET-AIKA-WRONG', 'AIKA BEST')],
            classificationContext: naganoContext,
          )
          .finalAction,
      isNot(ScrapeFinalAction.exclude),
    );
    expect(
      _evaluator()
          .evaluate(
            code: 'TARGET-AIKA',
            details: [_details('TARGET-AIKA', 'AIKA BEST')],
            classificationContext: const ScrapeClassificationContext(
              targetActressName: 'AIKA',
            ),
          )
          .finalAction,
      ScrapeFinalAction.exclude,
    );
    expect(
      _evaluator()
          .evaluate(
            code: 'TARGET-ALIAS',
            details: [_details('TARGET-ALIAS', 'B 8時間BEST')],
            classificationContext: aliasContext,
          )
          .finalAction,
      ScrapeFinalAction.exclude,
    );
    expect(
      _evaluator()
          .evaluate(
            code: 'TARGET-SAFE-FRIEND',
            details: [_details('TARGET-SAFE-FRIEND', '彼女は僕のベストフレンド')],
            classificationContext: naganoContext,
          )
          .finalAction,
      ScrapeFinalAction.keepReview,
    );
  });

  test(
    'keeps proven shared new productions but not weak co-performance hints',
    () {
      final weak = _evaluator().evaluate(
        code: 'SHARED-HINT',
        details: [
          _details(
            'SHARED-HINT',
            '大共演',
            provenanceFacts: const ScrapeWorkProvenanceFacts(
              coPerformance: ScrapeCoPerformance.possibleSharedProduction,
            ),
          ),
        ],
      );
      final proven = _evaluator().evaluate(
        code: 'SHARED-PROVEN',
        details: [
          _details(
            'SHARED-PROVEN',
            '20人大共演・全員同時出演・全編撮り下ろし新作',
            provenanceFacts: const ScrapeWorkProvenanceFacts(
              coPerformance: ScrapeCoPerformance.sharedProduction,
            ),
          ),
        ],
      );
      final concreteLineage = _evaluator().evaluate(
        code: 'SHARED-LINEAGE',
        details: [
          _details(
            'SHARED-LINEAGE',
            '豪華大共演',
            provenanceFacts: const ScrapeWorkProvenanceFacts(
              includedWorks: ['OLD-001', 'OLD-002', 'OLD-003'],
              coPerformance: ScrapeCoPerformance.possibleSharedProduction,
            ),
          ),
        ],
      );
      final bestWithHint = _evaluator().evaluate(
        code: 'SHARED-BEST',
        details: [
          _details(
            'SHARED-BEST',
            '豪華共演BEST11人',
            provenanceFacts: const ScrapeWorkProvenanceFacts(
              coPerformance: ScrapeCoPerformance.possibleSharedProduction,
            ),
          ),
        ],
      );
      final concreteProvenShared = _evaluator().evaluate(
        code: 'SHARED-LINEAGE-PROVEN',
        details: [
          _details(
            'SHARED-LINEAGE-PROVEN',
            '豪華大共演',
            provenanceFacts: const ScrapeWorkProvenanceFacts(
              includedWorks: ['OLD-004', 'OLD-005'],
              coPerformance: ScrapeCoPerformance.sharedProduction,
            ),
          ),
        ],
      );

      expect(weak.finalAction, ScrapeFinalAction.keepReview);
      expect(weak.reasonCodes, contains('production_shared_hint'));
      expect(proven.finalAction, ScrapeFinalAction.keep);
      expect(proven.provenanceClass, ScrapeProvenanceClass.originalCostar);
      expect(concreteLineage.finalAction, ScrapeFinalAction.exclude);
      expect(concreteLineage.hasConflict, isFalse);
      expect(bestWithHint.finalAction, ScrapeFinalAction.exclude);
      expect(bestWithHint.hasConflict, isFalse);
      expect(concreteProvenShared.finalAction, ScrapeFinalAction.exclude);
      expect(concreteProvenShared.hasConflict, isFalse);
    },
  );

  test('excludes mixed old material with a new bonus but not new作 alone', () {
    final mixed = _evaluator().evaluate(
      code: 'MIXED-001',
      details: [_details('MIXED-001', '過去作品収録・新作映像収録')],
    );
    final newOnly = _evaluator().evaluate(
      code: 'NEW-001',
      details: [_details('NEW-001', '新作映像')],
    );
    final newBonusWithoutReuse = _evaluator().evaluate(
      code: 'NEW-002',
      details: [_details('NEW-002', '新作映像収録')],
    );
    final bestWithBonus = _evaluator().evaluate(
      code: 'MIXED-002',
      details: [_details('MIXED-002', 'BEST・未公開新作映像')],
    );

    expect(mixed.finalAction, ScrapeFinalAction.exclude);
    expect(newOnly.finalAction, ScrapeFinalAction.keepReview);
    expect(newBonusWithoutReuse.finalAction, ScrapeFinalAction.keepReview);
    expect(bestWithBonus.finalAction, ScrapeFinalAction.exclude);
  });

  test('a former prefix never excludes an otherwise unknown work', () {
    final decision = _evaluator().evaluate(
      code: 'FC2-001',
      details: [_details('FC2-001', '普通作品')],
    );

    expect(decision.finalAction, ScrapeFinalAction.keepReview);
    expect(decision.reasonCodes, ['unknown_provenance']);
  });

  test('unions source-scoped exact allows across all resolved surfaces', () {
    final decision =
        _evaluator(
          exactAllows: const [
            ScrapeExactAllowRule(code: 'MIX-003', source: 'javbus'),
            ScrapeExactAllowRule(code: 'MIX-003', source: 'avbase'),
          ],
        ).evaluate(
          code: 'MIX-003',
          details: [
            _details('MIX-003', '總集編', source: ScrapeSourceId.javbus),
            _details('MIX-003', '總集', source: ScrapeSourceId.avbase),
          ],
        );

    expect(decision.finalAction, ScrapeFinalAction.keep);
    expect(decision.reasonCodes, ['exact_allow']);
    expect(decision.policyMatches, hasLength(2));
  });

  test(
    'a later generic exact allow can cover an earlier source-specific match',
    () {
      final decision =
          _evaluator(
            exactAllows: const [
              ScrapeExactAllowRule(code: 'MIX-004', source: 'javbus'),
              ScrapeExactAllowRule(code: 'MIX-004'),
            ],
          ).evaluate(
            code: 'MIX-004',
            details: [
              _details('MIX-004', '總集', source: ScrapeSourceId.javbus),
              _details('MIX-004', '總集', source: ScrapeSourceId.avbase),
            ],
          );

      expect(decision.finalAction, ScrapeFinalAction.keep);
    },
  );

  test('classifies concrete lineage as a derived work', () {
    final decision = _evaluator().evaluate(
      code: 'COLL-001',
      details: [
        _details(
          'COLL-001',
          '作品集',
          provenanceFacts: const ScrapeWorkProvenanceFacts(
            includedWorks: ['OLD-001', 'OLD-002'],
          ),
        ),
      ],
    );

    expect(decision.finalAction, ScrapeFinalAction.exclude);
    expect(decision.provenanceClass, ScrapeProvenanceClass.derivedOmnibus);
    expect(decision.verdict, ScrapeProvenanceVerdict.exclude);
  });

  test('keeps a concrete shared co-performance', () {
    final decision = _evaluator().evaluate(
      code: 'COSTAR-001',
      details: [
        _details(
          'COSTAR-001',
          '共演新作',
          provenanceFacts: const ScrapeWorkProvenanceFacts(
            coPerformance: ScrapeCoPerformance.sharedProduction,
          ),
        ),
      ],
    );

    expect(decision.finalAction, ScrapeFinalAction.keep);
    expect(decision.provenanceClass, ScrapeProvenanceClass.originalCostar);
  });

  test(
    'disabling the automatic filter never turns strong lineage into exclude',
    () {
      final decision = _evaluator(autoExcludeDerivedWorks: false).evaluate(
        code: 'COLL-002',
        details: [
          _details(
            'COLL-002',
            '作品集',
            provenanceFacts: const ScrapeWorkProvenanceFacts(
              includedWorks: ['OLD-003'],
            ),
          ),
        ],
      );

      expect(decision.finalAction, ScrapeFinalAction.keepReview);
      expect(decision.reasonCodes, contains('derived_work_filter_disabled'));
    },
  );

  test('supports an exact manual deny rule', () {
    final decision = _evaluator(
      exactDenies: const [ScrapeExactDenyRule(code: 'MANUAL-001')],
    ).evaluate(code: 'MANUAL-001', details: [_details('MANUAL-001', '普通作品')]);

    expect(decision.finalAction, ScrapeFinalAction.exclude);
    expect(decision.reasonCodes, ['exact_deny']);
  });

  test('conflicting exact allow and deny rules fail open to review', () {
    final decision =
        _evaluator(
          exactAllows: const [ScrapeExactAllowRule(code: 'CONFLICT-001')],
          exactDenies: const [ScrapeExactDenyRule(code: 'CONFLICT-001')],
        ).evaluate(
          code: 'CONFLICT-001',
          details: [_details('CONFLICT-001', '普通作品')],
        );

    expect(decision.finalAction, ScrapeFinalAction.keepReview);
    expect(decision.reasonCodes, ['manual_override_conflict']);
    expect(decision.hasConflict, isTrue);
  });
}

ScrapeExclusionPolicyEvaluator _evaluator({
  List<ScrapeExactAllowRule> exactAllows = const [],
  List<ScrapeExactDenyRule> exactDenies = const [],
  bool autoExcludeDerivedWorks = true,
}) {
  return ScrapeExclusionPolicyEvaluator(
    ScrapePolicySnapshot.current(
      rules: ScrapeRules.builtin,
      exactAllows: exactAllows,
      exactDenies: exactDenies,
      autoExcludeDerivedWorks: autoExcludeDerivedWorks,
    ),
  );
}

ScrapeWorkDetails _details(
  String code,
  String title, {
  int? performerCount,
  ScrapeSourceId source = ScrapeSourceId.javbus,
  ScrapeWorkProvenanceFacts provenanceFacts = const ScrapeWorkProvenanceFacts(),
  List<WorkPerformer>? performers,
}) {
  return ScrapeWorkDetails(
    source: source,
    code: code,
    title: title,
    performerCount: performerCount,
    performers: performers,
    provenanceFacts: provenanceFacts,
  );
}
