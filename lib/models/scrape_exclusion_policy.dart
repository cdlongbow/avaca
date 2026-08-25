import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'scrape_rules.dart';

/// The three policy outcomes are deliberately separate from transport and
/// parser failures.  A review decision is still a successful scrape.
enum ScrapeFinalAction { keep, keepReview, exclude }

/// Diagnostic provenance classes. Unknown evidence is intentionally mapped to
/// [ScrapeFinalAction.keepReview] by the evaluator.
enum ScrapeProvenanceClass {
  originalSolo,
  originalCostar,
  derivedBundle,
  derivedOmnibus,
  derivedExtract,
  derivedSplit,
  derivedReissue,
  derivedRemaster,
  derivedReedit,
  mixedOldNew,
  unknown,
}

enum ScrapeProvenanceVerdict { keep, exclude, keepUncertain }

enum ScrapeEvidenceLevel { none, review, strong }

enum ScrapeEvidenceStrength { weak, medium, strong }

enum ScrapeEvidencePolarity {
  supportsCompilation,
  supportsOriginalWork,
  neutral,
}

enum ScrapeEvidenceKind {
  explicitCompilation,
  omnibus,
  anthologyCollection,
  bestOfPriorWorks,
  completePriorWorks,
  includedPriorWorks,
  extractedFromPriorWork,
  splitFromPriorWork,
  packageEdition,
  reissue,
  remaster,
  reedit,
  mixedOldNew,
  independentSegments,
  genuineCoPerformance,
  priorWorkCollection,
  editedPresentation,
  viewpointSelection,
  highVolumePresentation,
  explicitOriginalWork,
}

enum ManagedFamilyMode { evidenceOnly, reviewPrior, excludeAll }

enum ScrapePolicyOrigin { builtin, remote, user }

extension ManagedFamilyModeCodec on ManagedFamilyMode {
  String get storageValue => switch (this) {
    ManagedFamilyMode.evidenceOnly => 'evidenceOnly',
    ManagedFamilyMode.reviewPrior => 'reviewPrior',
    ManagedFamilyMode.excludeAll => 'excludeAll',
  };

  static ManagedFamilyMode parse(Object? value) {
    return switch (value?.toString()) {
      'excludeAll' => ManagedFamilyMode.excludeAll,
      'reviewPrior' => ManagedFamilyMode.reviewPrior,
      _ => ManagedFamilyMode.evidenceOnly,
    };
  }
}

extension ScrapePolicyOriginCodec on ScrapePolicyOrigin {
  String get storageValue => switch (this) {
    ScrapePolicyOrigin.builtin => 'builtin',
    ScrapePolicyOrigin.remote => 'remote',
    ScrapePolicyOrigin.user => 'user',
  };

  static ScrapePolicyOrigin parse(Object? value) {
    return switch (value?.toString()) {
      'remote' => ScrapePolicyOrigin.remote,
      'user' => ScrapePolicyOrigin.user,
      _ => ScrapePolicyOrigin.builtin,
    };
  }
}

class ScrapeManagedFamilyPolicy {
  const ScrapeManagedFamilyPolicy({
    required this.family,
    required this.mode,
    required this.origin,
  });

  final String family;
  final ManagedFamilyMode mode;
  final ScrapePolicyOrigin origin;

  Map<String, Object?> toJson() => {
    'family': family,
    'mode': mode.storageValue,
    'origin': origin.storageValue,
  };

  factory ScrapeManagedFamilyPolicy.fromJson(Object? source) {
    if (source is! Map) {
      throw const FormatException('Managed family policy must be an object.');
    }
    final map = Map<String, Object?>.from(source);
    final family = map['family']?.toString().trim().toUpperCase() ?? '';
    if (family.isEmpty || family.length > 32) {
      throw const FormatException('Managed family policy has an invalid key.');
    }
    return ScrapeManagedFamilyPolicy(
      family: family,
      mode: ManagedFamilyModeCodec.parse(map['mode']),
      origin: ScrapePolicyOriginCodec.parse(map['origin']),
    );
  }
}

class ScrapeExactAllowRule {
  const ScrapeExactAllowRule({
    required this.code,
    this.source,
    this.includeSpecialEditions = false,
  });

  final String code;
  final String? source;
  final bool includeSpecialEditions;

  String get normalizedCode => normalizeScrapePolicyCode(code);

  bool matches(String candidateCode, {String? sourceId}) {
    final expectedSource = source?.trim().toLowerCase();
    if (expectedSource != null &&
        expectedSource.isNotEmpty &&
        expectedSource != sourceId?.trim().toLowerCase()) {
      return false;
    }
    return normalizedCode.isNotEmpty &&
        normalizedCode == normalizeScrapePolicyCode(candidateCode);
  }

  Map<String, Object?> toJson() => {
    'code': code,
    if (source != null && source!.trim().isNotEmpty) 'source': source,
    'includeSpecialEditions': includeSpecialEditions,
  };

  factory ScrapeExactAllowRule.fromJson(Object? source) {
    if (source is! Map) {
      throw const FormatException('Exact allow rule must be an object.');
    }
    final map = Map<String, Object?>.from(source);
    final code = map['code']?.toString().trim() ?? '';
    if (code.isEmpty || code.length > 80) {
      throw const FormatException('Exact allow rule has an invalid code.');
    }
    final sourceId = map['source']?.toString().trim();
    return ScrapeExactAllowRule(
      code: code,
      source: sourceId == null || sourceId.isEmpty ? null : sourceId,
      includeSpecialEditions: map['includeSpecialEditions'] == true,
    );
  }
}

class ScrapeExactDenyRule {
  const ScrapeExactDenyRule({required this.code, this.source});

  final String code;
  final String? source;

  String get normalizedCode => normalizeScrapePolicyCode(code);

  bool matches(String candidateCode, {String? sourceId}) {
    final expectedSource = source?.trim().toLowerCase();
    if (expectedSource != null &&
        expectedSource.isNotEmpty &&
        expectedSource != sourceId?.trim().toLowerCase()) {
      return false;
    }
    return normalizedCode.isNotEmpty &&
        normalizedCode == normalizeScrapePolicyCode(candidateCode);
  }

  Map<String, Object?> toJson() => {
    'code': code,
    if (source != null && source!.trim().isNotEmpty) 'source': source,
  };

  factory ScrapeExactDenyRule.fromJson(Object? source) {
    if (source is! Map) {
      throw const FormatException('Exact deny rule must be an object.');
    }
    final map = Map<String, Object?>.from(source);
    final code = map['code']?.toString().trim() ?? '';
    if (code.isEmpty || code.length > 80) {
      throw const FormatException('Exact deny rule has an invalid code.');
    }
    final sourceId = map['source']?.toString().trim();
    return ScrapeExactDenyRule(
      code: code,
      source: sourceId == null || sourceId.isEmpty ? null : sourceId,
    );
  }
}

/// Immutable policy materialized when a job is created.
class ScrapePolicySnapshot {
  ScrapePolicySnapshot._({
    required this.schemaVersion,
    required this.policyVersion,
    required this.rulesVersion,
    required this.classifierVersion,
    required this.rulesBundleDigest,
    required this.snapshotDigest,
    required this.autoExcludeDerivedWorks,
    required List<String> excludedPrefixes,
    required List<ScrapeManagedFamilyPolicy> managedFamilies,
    required List<ScrapeExactAllowRule> exactAllows,
    required List<ScrapeExactDenyRule> exactDenies,
  }) : excludedPrefixes = List.unmodifiable(excludedPrefixes),
       managedFamilies = List.unmodifiable(managedFamilies),
       exactAllows = List.unmodifiable(exactAllows),
       exactDenies = List.unmodifiable(exactDenies);

  static const currentSchemaVersion = 3;
  static const currentPolicyVersion = 'provenance-v3';
  static const currentClassifierVersion = 'provenance-1';

  final int schemaVersion;
  final String policyVersion;
  final String rulesVersion;
  final String classifierVersion;
  final String rulesBundleDigest;
  final String snapshotDigest;
  final bool autoExcludeDerivedWorks;
  final List<String> excludedPrefixes;
  final List<ScrapeManagedFamilyPolicy> managedFamilies;
  final List<ScrapeExactAllowRule> exactAllows;
  final List<ScrapeExactDenyRule> exactDenies;

  ScrapeManagedFamilyPolicy? managedFamily(String family) {
    final normalized = family.trim().toUpperCase();
    for (final policy in managedFamilies) {
      if (policy.family == normalized) return policy;
    }
    return null;
  }

  static ScrapePolicySnapshot v2({
    required ScrapeRules rules,
    required List<String> excludedPrefixes,
    required Map<String, ManagedFamilyMode> managedFamilyModes,
    required List<ScrapeExactAllowRule> exactAllows,
    bool autoExcludeDerivedWorks = true,
    List<ScrapeExactDenyRule> exactDenies = const [],
  }) {
    final managed = <String, ScrapeManagedFamilyPolicy>{};
    for (final entry in rules.managedFamilyRecommendations.entries) {
      final family = entry.key.trim().toUpperCase();
      if (family.isEmpty) continue;
      managed[family] = ScrapeManagedFamilyPolicy(
        family: family,
        mode: ManagedFamilyModeCodec.parse(entry.value),
        origin: ScrapePolicyOrigin.builtin,
      );
    }
    for (final entry in managedFamilyModes.entries) {
      final family = entry.key.trim().toUpperCase();
      if (family.isEmpty) continue;
      managed[family] = ScrapeManagedFamilyPolicy(
        family: family,
        mode: entry.value,
        origin: ScrapePolicyOrigin.user,
      );
    }
    if (!managed.containsKey('OFJE')) {
      managed['OFJE'] = const ScrapeManagedFamilyPolicy(
        family: 'OFJE',
        mode: ManagedFamilyMode.reviewPrior,
        origin: ScrapePolicyOrigin.builtin,
      );
    }
    final normalizedPrefixes = excludedPrefixes
        .map(normalizeScrapePolicyCode)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final managedList = managed.values.toList(growable: false)
      ..sort((left, right) => left.family.compareTo(right.family));
    final allowList = exactAllows
        .where((rule) => rule.normalizedCode.isNotEmpty)
        .toList(growable: false);
    final denyList = exactDenies
        .where((rule) => rule.normalizedCode.isNotEmpty)
        .toList(growable: false);
    final bundle = {
      'rules': rules.toJson(),
      'classifierVersion': currentClassifierVersion,
    };
    final bundleDigest = _digest(bundle);
    final payload = {
      'schemaVersion': currentSchemaVersion,
      'policyVersion': currentPolicyVersion,
      'rulesVersion': rules.rulesVersion,
      'classifierVersion': currentClassifierVersion,
      'rulesBundleDigest': bundleDigest,
      'autoExcludeDerivedWorks': autoExcludeDerivedWorks,
      'excludedPrefixes': normalizedPrefixes,
      'managedFamilies': managedList.map((item) => item.toJson()).toList(),
      'exactAllows': allowList.map((item) => item.toJson()).toList(),
      'exactDenies': denyList.map((item) => item.toJson()).toList(),
    };
    return ScrapePolicySnapshot._(
      schemaVersion: currentSchemaVersion,
      policyVersion: currentPolicyVersion,
      rulesVersion: rules.rulesVersion,
      classifierVersion: currentClassifierVersion,
      rulesBundleDigest: bundleDigest,
      snapshotDigest: _digest(payload),
      autoExcludeDerivedWorks: autoExcludeDerivedWorks,
      excludedPrefixes: normalizedPrefixes,
      managedFamilies: managedList,
      exactAllows: allowList,
      exactDenies: denyList,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'policyVersion': policyVersion,
    'rulesVersion': rulesVersion,
    'classifierVersion': classifierVersion,
    'rulesBundleDigest': rulesBundleDigest,
    'snapshotDigest': snapshotDigest,
    'autoExcludeDerivedWorks': autoExcludeDerivedWorks,
    'excludedPrefixes': excludedPrefixes,
    'managedFamilies': managedFamilies.map((item) => item.toJson()).toList(),
    'exactAllows': exactAllows.map((item) => item.toJson()).toList(),
    'exactDenies': exactDenies.map((item) => item.toJson()).toList(),
  };

  String encode() => jsonEncode(toJson());

  factory ScrapePolicySnapshot.fromEncoded({
    required String? encoded,
    required List<String> excludedPrefixes,
    required Map<String, ManagedFamilyMode> managedFamilyModes,
    required List<ScrapeExactAllowRule> exactAllows,
    bool autoExcludeDerivedWorks = true,
    List<ScrapeExactDenyRule> exactDenies = const [],
  }) {
    ScrapePolicySnapshot fallback() => ScrapePolicySnapshot.v2(
      rules: ScrapeRules.builtin,
      excludedPrefixes: excludedPrefixes,
      managedFamilyModes: managedFamilyModes,
      exactAllows: exactAllows,
      autoExcludeDerivedWorks: autoExcludeDerivedWorks,
      exactDenies: exactDenies,
    );

    if (encoded == null || encoded.trim().isEmpty) {
      return fallback();
    }
    try {
      final raw = jsonDecode(encoded);
      if (raw is! Map) throw const FormatException('Invalid policy snapshot.');
      final map = Map<String, Object?>.from(raw);
      final schema = _int(map['schemaVersion']);
      final version = map['policyVersion']?.toString();
      if (schema != currentSchemaVersion || version != currentPolicyVersion) {
        return fallback();
      }
      final prefixes = _strings(map['excludedPrefixes']);
      final automaticExclusion = map['autoExcludeDerivedWorks'] is bool
          ? map['autoExcludeDerivedWorks'] as bool
          : autoExcludeDerivedWorks;
      final managed = <ScrapeManagedFamilyPolicy>[];
      if (map['managedFamilies'] is List) {
        for (final item in map['managedFamilies'] as List) {
          try {
            managed.add(ScrapeManagedFamilyPolicy.fromJson(item));
          } on FormatException {
            // Ignore one malformed optional policy entry without losing the
            // rest of a valid job snapshot.
          }
        }
      }
      final allows = <ScrapeExactAllowRule>[];
      if (map['exactAllows'] is List) {
        for (final item in map['exactAllows'] as List) {
          try {
            allows.add(ScrapeExactAllowRule.fromJson(item));
          } on FormatException {
            // See the managed-family compatibility comment above.
          }
        }
      }
      final denies = <ScrapeExactDenyRule>[];
      if (map['exactDenies'] is List) {
        for (final item in map['exactDenies'] as List) {
          try {
            denies.add(ScrapeExactDenyRule.fromJson(item));
          } on FormatException {
            // Ignore malformed optional entries while preserving the job.
          }
        }
      }
      if (managed.isEmpty) {
        managed.add(
          const ScrapeManagedFamilyPolicy(
            family: 'OFJE',
            mode: ManagedFamilyMode.reviewPrior,
            origin: ScrapePolicyOrigin.builtin,
          ),
        );
      }
      final rulesVersion =
          map['rulesVersion']?.toString() ?? ScrapeRules.builtin.rulesVersion;
      final classifierVersion =
          map['classifierVersion']?.toString() ?? currentClassifierVersion;
      final rulesBundleDigest = map['rulesBundleDigest']?.toString() ?? '';
      final snapshotDigest = map['snapshotDigest']?.toString() ?? '';
      if (classifierVersion != currentClassifierVersion ||
          rulesBundleDigest.isEmpty ||
          snapshotDigest.isEmpty) {
        return fallback();
      }
      final snapshotPayload = {
        'schemaVersion': schema,
        'policyVersion': version,
        'rulesVersion': rulesVersion,
        'classifierVersion': classifierVersion,
        'rulesBundleDigest': rulesBundleDigest,
        'autoExcludeDerivedWorks': automaticExclusion,
        'excludedPrefixes': prefixes,
        'managedFamilies': managed.map((item) => item.toJson()).toList(),
        'exactAllows': allows.map((item) => item.toJson()).toList(),
        'exactDenies': denies.map((item) => item.toJson()).toList(),
      };
      if (_digest(snapshotPayload) != snapshotDigest) {
        return fallback();
      }
      final snapshot = ScrapePolicySnapshot._(
        schemaVersion: schema,
        policyVersion: version!,
        rulesVersion: rulesVersion,
        classifierVersion: classifierVersion,
        rulesBundleDigest: rulesBundleDigest,
        snapshotDigest: snapshotDigest,
        autoExcludeDerivedWorks: automaticExclusion,
        excludedPrefixes: prefixes,
        managedFamilies: managed,
        exactAllows: allows,
        exactDenies: denies,
      );
      return snapshot;
    } on Object {
      return fallback();
    }
  }
}

String normalizeScrapePolicyCode(String value) {
  return value.replaceAll(RegExp(r'\s+'), '').trim().toUpperCase();
}

String _digest(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<String>()
      .map(normalizeScrapePolicyCode)
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
}
