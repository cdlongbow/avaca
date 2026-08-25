import 'dart:convert';

import 'package:avaca/models/scrape_exclusion_policy.dart';
import 'package:avaca/models/scrape_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips an immutable policy snapshot', () {
    final original = ScrapePolicySnapshot.v2(
      rules: ScrapeRules.builtin,
      excludedPrefixes: const ['FC2'],
      managedFamilyModes: const {'OFJE': ManagedFamilyMode.reviewPrior},
      exactAllows: const [ScrapeExactAllowRule(code: 'OFJE-605')],
      autoExcludeDerivedWorks: false,
      exactDenies: const [ScrapeExactDenyRule(code: 'FC2-001')],
    );

    final decoded = ScrapePolicySnapshot.fromEncoded(
      encoded: original.encode(),
      excludedPrefixes: const [],
      managedFamilyModes: const {},
      exactAllows: const [],
    );

    expect(decoded.snapshotDigest, original.snapshotDigest);
    expect(decoded.excludedPrefixes, ['FC2']);
    expect(decoded.managedFamily('OFJE')?.mode, ManagedFamilyMode.reviewPrior);
    expect(decoded.exactAllows.single.normalizedCode, 'OFJE-605');
    expect(decoded.autoExcludeDerivedWorks, isFalse);
    expect(decoded.exactDenies.single.normalizedCode, 'FC2-001');
  });

  test('rejects a tampered snapshot and uses the new-job fallback', () {
    final original = ScrapePolicySnapshot.v2(
      rules: ScrapeRules.builtin,
      excludedPrefixes: const ['FC2'],
      managedFamilyModes: const {},
      exactAllows: const [],
    );
    final tampered = jsonDecode(original.encode()) as Map<String, dynamic>;
    tampered['excludedPrefixes'] = ['CHANGED'];

    final decoded = ScrapePolicySnapshot.fromEncoded(
      encoded: jsonEncode(tampered),
      excludedPrefixes: const ['FALLBACK'],
      managedFamilyModes: const {},
      exactAllows: const [],
    );

    expect(decoded.excludedPrefixes, ['FALLBACK']);
    expect(decoded.snapshotDigest, isNot(original.snapshotDigest));
  });

  test('obsolete classifier snapshots fall back to current V2 options', () {
    final snapshot = ScrapePolicySnapshot.v2(
      rules: ScrapeRules.builtin,
      excludedPrefixes: const ['FC2'],
      managedFamilyModes: const {'OFJE': ManagedFamilyMode.excludeAll},
      exactAllows: const [],
    );
    final payload = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
    payload['classifierVersion'] = 'semantic-0';

    final recovered = ScrapePolicySnapshot.fromEncoded(
      encoded: jsonEncode(payload),
      excludedPrefixes: const ['JAV'],
      managedFamilyModes: const {'OFJE': ManagedFamilyMode.evidenceOnly},
      exactAllows: const [],
    );

    expect(recovered.excludedPrefixes, ['JAV']);
    expect(
      recovered.managedFamily('OFJE')?.mode,
      ManagedFamilyMode.evidenceOnly,
    );
  });
}
