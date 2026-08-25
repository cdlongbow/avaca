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

  test('treats OFJE as review-prior rather than compilation by code alone', () {
    final decision = _evaluator().evaluate(
      code: 'OFJE-605',
      details: [_details('OFJE-605', 'オール巨乳女優 100連発', performerCount: 100)],
    );

    expect(decision.finalAction, ScrapeFinalAction.keepReview);
    expect(decision.reasonCodes, contains('managed_family_review_prior'));
    expect(decision.reasonCodes, contains('review_evidence'));
  });

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

  test(
    'supports an explicit user family deny without relying on performer count',
    () {
      final decision =
          _evaluator(
            managedFamilyModes: const {'OFJE': ManagedFamilyMode.excludeAll},
          ).evaluate(
            code: 'OFJE-605',
            details: [_details('OFJE-605', '通常の単体作品', performerCount: 100)],
          );

      expect(decision.finalAction, ScrapeFinalAction.exclude);
      expect(decision.reasonCodes, ['managed_family_exclude_all']);
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

  test('prefixes are only hints and exact allow can still override them', () {
    final excluded = _evaluator(
      excludedPrefixes: const ['FC2'],
    ).evaluate(code: 'FC2-001', details: [_details('FC2-001', '普通作品')]);
    final allowed = _evaluator(
      excludedPrefixes: const ['FC2'],
      exactAllows: const [ScrapeExactAllowRule(code: 'FC2-001')],
    ).evaluate(code: 'FC2-001', details: [_details('FC2-001', '普通作品')]);

    expect(excluded.finalAction, ScrapeFinalAction.keepReview);
    expect(allowed.finalAction, ScrapeFinalAction.keep);
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
}

ScrapeExclusionPolicyEvaluator _evaluator({
  List<String> excludedPrefixes = const [],
  Map<String, ManagedFamilyMode> managedFamilyModes = const {},
  List<ScrapeExactAllowRule> exactAllows = const [],
  List<ScrapeExactDenyRule> exactDenies = const [],
  bool autoExcludeDerivedWorks = true,
}) {
  return ScrapeExclusionPolicyEvaluator(
    ScrapePolicySnapshot.v2(
      rules: ScrapeRules.builtin,
      excludedPrefixes: excludedPrefixes,
      managedFamilyModes: managedFamilyModes,
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
