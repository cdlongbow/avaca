import 'package:avaca/models/scrape_exclusion_policy.dart';
import 'package:avaca/models/scrape_rules.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/models/work.dart';
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
      details: [_details('MOON-001', '完全ノーカット新作')],
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
      details: [_details('MIX-002', '総集編'), _details('MIX-002', '完全ノーカット新作')],
    );

    expect(decision.finalAction, ScrapeFinalAction.keepReview);
    expect(decision.hasConflict, isTrue);
    expect(decision.reasonCodes, ['source_evidence_conflict']);
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
