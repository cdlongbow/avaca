import 'package:avaca/models/scrape_exclusion_policy.dart';
import 'package:avaca/models/scrape_rules.dart';
import 'package:avaca/models/scrape_source_settings.dart';
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

    expect(decision.finalAction, ScrapeFinalAction.keep);
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

  test('prefix exclusion is explicit but exact allow can override it', () {
    final excluded = _evaluator(
      excludedPrefixes: const ['FC2'],
    ).evaluate(code: 'FC2-001', details: [_details('FC2-001', '普通作品')]);
    final allowed = _evaluator(
      excludedPrefixes: const ['FC2'],
      exactAllows: const [ScrapeExactAllowRule(code: 'FC2-001')],
    ).evaluate(code: 'FC2-001', details: [_details('FC2-001', '普通作品')]);

    expect(excluded.finalAction, ScrapeFinalAction.exclude);
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
}

ScrapeExclusionPolicyEvaluator _evaluator({
  List<String> excludedPrefixes = const [],
  Map<String, ManagedFamilyMode> managedFamilyModes = const {},
  List<ScrapeExactAllowRule> exactAllows = const [],
}) {
  return ScrapeExclusionPolicyEvaluator(
    ScrapePolicySnapshot.v2(
      rules: ScrapeRules.builtin,
      excludedPrefixes: excludedPrefixes,
      managedFamilyModes: managedFamilyModes,
      exactAllows: exactAllows,
    ),
  );
}

ScrapeWorkDetails _details(
  String code,
  String title, {
  int? performerCount,
  ScrapeSourceId source = ScrapeSourceId.javbus,
}) {
  return ScrapeWorkDetails(
    source: source,
    code: code,
    title: title,
    performerCount: performerCount,
  );
}
