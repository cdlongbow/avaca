import 'dart:async';
import 'dart:convert';

import '../../core/database.dart';
import '../scrape/work_code_canonicalizer.dart';
import 'work_image_route_models.dart';
import 'work_image_route_resolver.dart';

const workImagePrefixRouteSettingKey = 'work_image_prefix_route_rules';

enum PrefixRouteStoreLoadStatus {
  ready,
  corrupt,
  unsupportedVersion,
  readError,
}

enum PrefixRouteImportMode { merge, replace }

final class PrefixRouteRepositoryException implements Exception {
  const PrefixRouteRepositoryException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class PrefixRouteImportPreview {
  const PrefixRouteImportPreview({
    required this.document,
    required this.rulesOnly,
    required this.importedRuleCount,
    required this.newRuleCount,
    required this.newCandidateCount,
    required this.changedCandidateCount,
    required this.manualConflictCount,
  });

  final WorkImageRouteDocument document;
  final bool rulesOnly;
  final int importedRuleCount;
  final int newRuleCount;
  final int newCandidateCount;
  final int changedCandidateCount;
  final int manualConflictCount;
}

final class PrefixRouteImportResult {
  const PrefixRouteImportResult({
    required this.importedRuleCount,
    required this.newRuleCount,
    required this.newCandidateCount,
    required this.changedCandidateCount,
    required this.manualConflictCount,
  });

  final int importedRuleCount;
  final int newRuleCount;
  final int newCandidateCount;
  final int changedCandidateCount;
  final int manualConflictCount;
}

typedef _ReadPrefixRouteDocument = Future<String?> Function();
typedef _WritePrefixRouteDocument = Future<void> Function(String value);
typedef _RemovePrefixRouteDocument = Future<void> Function();

/// Persistent Prefix route state backed by the existing AppDatabase settings
/// table.  The repository is deliberately the only owner of read/modify/write
/// mutations so concurrent image workers cannot lose each other's statistics.
final class PrefixRouteRepository {
  PrefixRouteRepository._({
    required _ReadPrefixRouteDocument read,
    required _WritePrefixRouteDocument write,
    required _RemovePrefixRouteDocument remove,
  }) : _read = read,
       _write = write,
       _remove = remove;

  static final Expando<PrefixRouteRepository> _databaseRepositories =
      Expando<PrefixRouteRepository>('prefixRouteRepositories');

  factory PrefixRouteRepository.forDatabase(AppDatabase db) {
    final existing = _databaseRepositories[db];
    if (existing != null) return existing;

    final repository = PrefixRouteRepository._(
      read: () => db.getSetting(workImagePrefixRouteSettingKey),
      write: (value) => db.setSetting(workImagePrefixRouteSettingKey, value),
      remove: () => db.removeSetting(workImagePrefixRouteSettingKey),
    );
    _databaseRepositories[db] = repository;
    return repository;
  }

  factory PrefixRouteRepository.inMemory({String? initialJson}) {
    var raw = initialJson;
    return PrefixRouteRepository._(
      read: () async => raw,
      write: (value) async => raw = value,
      remove: () async => raw = null,
    );
  }

  final _ReadPrefixRouteDocument _read;
  final _WritePrefixRouteDocument _write;
  final _RemovePrefixRouteDocument _remove;

  WorkImageRouteDocument _document = WorkImageRouteDocument.empty();
  PrefixRouteStoreLoadStatus _loadStatus = PrefixRouteStoreLoadStatus.ready;
  String? _loadError;
  Future<void>? _loadFuture;
  Future<void> _writeTail = Future<void>.value();
  final Map<String, int> _prefixRevisions = <String, int>{};

  PrefixRouteStoreLoadStatus get loadStatus => _loadStatus;
  String? get loadError => _loadError;
  bool get isReady => _loadStatus == PrefixRouteStoreLoadStatus.ready;

  Future<void> ensureLoaded() {
    return _loadFuture ??= _loadInternal();
  }

  List<WorkImagePrefixRouteRule> get rules {
    final values = _document.routes.values.toList();
    return values..sort((a, b) => a.prefix.compareTo(b.prefix));
  }

  WorkImagePrefixRouteRule? ruleFor(String prefix) {
    return _document.routes[normalizeWorkImagePrefix(prefix)];
  }

  int revisionFor(String prefix) {
    final normalized = normalizeWorkImagePrefix(prefix) ?? prefix;
    return _prefixRevisions[normalized] ?? 0;
  }

  List<WorkImageNormalizationFamily> orderedFamiliesFor(String prefix) {
    final rule = ruleFor(prefix);
    final ordered = <WorkImageNormalizationFamily>[];

    void add(WorkImageNormalizationFamily? family) {
      if (family != null && !ordered.contains(family)) {
        ordered.add(family);
      }
    }

    add(rule?.manualOverride);
    add(rule?.preferredFamily);
    final candidates = [...?rule?.candidates]..sort(compareWorkImageCandidates);
    for (final candidate in candidates) {
      add(candidate.family);
    }
    for (final family in workImageDefaultProbeOrder) {
      add(family);
    }
    return List.unmodifiable(ordered);
  }

  Future<void> recordSuccess({
    required String prefix,
    required WorkImageNormalizationFamily family,
    DateTime? at,
    Iterable<WorkImageNormalizationFamily> definitiveFailures = const [],
    int? expectedRevision,
  }) {
    final normalized = _requirePrefix(prefix);
    final timestamp = (at ?? DateTime.now()).toUtc();
    return _enqueue(() async {
      await _ensureLoadedForMutation();
      if (!isReady) return;
      if (expectedRevision != null &&
          revisionFor(normalized) != expectedRevision) {
        return;
      }

      final existing = _document.routes[normalized];
      final candidates =
          <WorkImageNormalizationFamily, WorkImageRouteCandidate>{
            for (final candidate in existing?.candidates ?? const [])
              candidate.family: candidate,
          };
      for (final failedFamily in definitiveFailures) {
        final candidate =
            candidates[failedFamily] ??
            WorkImageRouteCandidate(family: failedFamily);
        candidates[failedFamily] = candidate.withFailure(timestamp);
      }
      final winning =
          candidates[family] ?? WorkImageRouteCandidate(family: family);
      candidates[family] = winning.withSuccess(timestamp);
      final now = timestamp;
      final nextRule = WorkImagePrefixRouteRule(
        prefix: normalized,
        candidates: candidates.values,
        manualOverride: existing?.manualOverride,
        preferredFamily: family,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      await _persist(_replaceRule(normalized, nextRule));
    });
  }

  Future<void> recordDefinitiveFailure({
    required String prefix,
    required WorkImageNormalizationFamily family,
    DateTime? at,
  }) {
    final normalized = _requirePrefix(prefix);
    final timestamp = (at ?? DateTime.now()).toUtc();
    return _enqueue(() async {
      await _ensureLoadedForMutation();
      if (!isReady) return;
      final existing = _document.routes[normalized];
      // An unknown Prefix must not be persisted just because every candidate
      // failed.  A rule exists only after a validated success, or an explicit
      // Settings manual override.
      if (existing == null) return;
      final candidates =
          <WorkImageNormalizationFamily, WorkImageRouteCandidate>{
            for (final candidate in existing.candidates)
              candidate.family: candidate,
          };
      final candidate =
          candidates[family] ?? WorkImageRouteCandidate(family: family);
      candidates[family] = candidate.withFailure(timestamp);
      final nextRule = WorkImagePrefixRouteRule(
        prefix: normalized,
        candidates: candidates.values,
        manualOverride: existing.manualOverride,
        preferredFamily: existing.preferredFamily,
        createdAt: existing.createdAt ?? timestamp,
        updatedAt: timestamp,
      );
      await _persist(_replaceRule(normalized, nextRule));
    });
  }

  Future<void> setManualOverride({
    required String prefix,
    required WorkImageNormalizationFamily? family,
    DateTime? at,
  }) {
    final normalized = _requirePrefix(prefix);
    final timestamp = (at ?? DateTime.now()).toUtc();
    return _enqueue(() async {
      await _ensureLoadedForMutation();
      _requireReadyForExplicitMutation();
      final existing = _document.routes[normalized];
      final candidates =
          <WorkImageNormalizationFamily, WorkImageRouteCandidate>{
            for (final candidate in existing?.candidates ?? const [])
              candidate.family: candidate,
          };
      if (family != null) {
        candidates.putIfAbsent(
          family,
          () => WorkImageRouteCandidate(family: family),
        );
      }
      if (family == null && candidates.isEmpty) {
        await _persist(_removeRule(normalized));
        return;
      }
      final nextRule = WorkImagePrefixRouteRule(
        prefix: normalized,
        candidates: candidates.values,
        manualOverride: family,
        preferredFamily: existing?.preferredFamily,
        createdAt: existing?.createdAt ?? timestamp,
        updatedAt: timestamp,
      );
      await _persist(_replaceRule(normalized, nextRule));
    });
  }

  Future<void> clearManualOverride(String prefix) {
    return setManualOverride(prefix: prefix, family: null);
  }

  Future<void> forget(String prefix) {
    final normalized = _requirePrefix(prefix);
    return _enqueue(() async {
      await _ensureLoadedForMutation();
      _requireReadyForExplicitMutation();
      _bumpRevision(normalized);
      await _persist(_removeRule(normalized));
    });
  }

  /// Removes learned candidates and statistics but keeps manual overrides.
  Future<void> clearAutomaticLearning() {
    return _enqueue(() async {
      await _ensureLoadedForMutation();
      _requireReadyForExplicitMutation();
      final nextRoutes = <String, WorkImagePrefixRouteRule>{};
      final now = DateTime.now().toUtc();
      for (final rule in _document.routes.values) {
        final manual = rule.manualOverride;
        if (manual == null) {
          _bumpRevision(rule.prefix);
          continue;
        }
        nextRoutes[rule.prefix] = WorkImagePrefixRouteRule(
          prefix: rule.prefix,
          candidates: [WorkImageRouteCandidate(family: manual)],
          manualOverride: manual,
          preferredFamily: null,
          createdAt: rule.createdAt ?? now,
          updatedAt: now,
        );
        _bumpRevision(rule.prefix);
      }
      await _persist(_document.copyWith(routes: nextRoutes));
    });
  }

  /// Clears one Prefix's learned candidates while keeping its manual
  /// override, if any.  This is used by the Prefix detail UI so a user can
  /// reset automatic learning without losing an explicit choice.
  Future<void> clearAutomaticLearningFor(String prefix) {
    final normalized = _requirePrefix(prefix);
    return _enqueue(() async {
      await _ensureLoadedForMutation();
      _requireReadyForExplicitMutation();
      final existing = _document.routes[normalized];
      if (existing == null) return;
      final manual = existing.manualOverride;
      if (manual == null) {
        _bumpRevision(normalized);
        await _persist(_removeRule(normalized));
        return;
      }
      await _persist(
        _replaceRule(
          normalized,
          WorkImagePrefixRouteRule(
            prefix: normalized,
            candidates: [WorkImageRouteCandidate(family: manual)],
            manualOverride: manual,
            createdAt: existing.createdAt,
            updatedAt: DateTime.now().toUtc(),
          ),
        ),
      );
    });
  }

  Future<String> exportJson({bool includeStatistics = false}) async {
    await ensureLoaded();
    return PrefixRouteDocumentCodec.encode(
      _document,
      includeStatistics: includeStatistics,
    );
  }

  PrefixRouteImportPreview previewImport(String rawJson) {
    final imported = PrefixRouteDocumentCodec._decode(rawJson);
    final current = _document.routes;
    var newRules = 0;
    var newCandidates = 0;
    var changedCandidates = 0;
    var manualConflicts = 0;
    for (final entry in imported.document.routes.entries) {
      final existing = current[entry.key];
      if (existing == null) {
        newRules++;
        newCandidates += entry.value.candidates.length;
        continue;
      }
      if (existing.manualOverride != null &&
          entry.value.manualOverride != null &&
          existing.manualOverride != entry.value.manualOverride) {
        manualConflicts++;
      }
      for (final candidate in entry.value.candidates) {
        final local = existing.candidateFor(candidate.family);
        if (local == null) {
          newCandidates++;
        } else if (local.successCount != candidate.successCount ||
            local.failureCount != candidate.failureCount) {
          changedCandidates++;
        }
      }
    }
    return PrefixRouteImportPreview(
      document: imported.document,
      rulesOnly: imported.rulesOnly,
      importedRuleCount: imported.document.routes.length,
      newRuleCount: newRules,
      newCandidateCount: newCandidates,
      changedCandidateCount: changedCandidates,
      manualConflictCount: manualConflicts,
    );
  }

  Future<PrefixRouteImportResult> importJson(
    String rawJson, {
    PrefixRouteImportMode mode = PrefixRouteImportMode.merge,
  }) async {
    // Decode before entering the mutation queue: invalid input has zero writes.
    final imported = PrefixRouteDocumentCodec._decode(rawJson);
    return _enqueue(() async {
      await _ensureLoadedForMutation();
      if (mode == PrefixRouteImportMode.merge) {
        _requireReadyForExplicitMutation();
      }
      final result = _summarizeImport(imported.document);
      final next = mode == PrefixRouteImportMode.replace
          ? imported.document
          : _merge(imported.document);
      await _persist(
        next,
        allowCorruptRecovery: mode == PrefixRouteImportMode.replace,
      );
      return result;
    });
  }

  Future<void> resetAll() {
    return _enqueue(() async {
      await _ensureLoadedForMutation();
      _requireReadyForExplicitMutation();
      _document = WorkImageRouteDocument.empty();
      _loadStatus = PrefixRouteStoreLoadStatus.ready;
      _loadError = null;
      _prefixRevisions.clear();
      await _remove();
    });
  }

  Future<void> _loadInternal() async {
    try {
      final raw = await _read();
      if (raw == null || raw.trim().isEmpty) {
        _document = WorkImageRouteDocument.empty();
        _loadStatus = PrefixRouteStoreLoadStatus.ready;
        return;
      }
      final decoded = PrefixRouteDocumentCodec._decode(raw);
      _document = decoded.document;
      _loadStatus = PrefixRouteStoreLoadStatus.ready;
      _loadError = null;
    } on PrefixRouteRepositoryException catch (error) {
      _document = WorkImageRouteDocument.empty();
      _loadStatus = error.code == 'unsupported_schema'
          ? PrefixRouteStoreLoadStatus.unsupportedVersion
          : PrefixRouteStoreLoadStatus.corrupt;
      _loadError = error.message;
    } on Object catch (error) {
      _document = WorkImageRouteDocument.empty();
      _loadStatus = PrefixRouteStoreLoadStatus.readError;
      _loadError = error.toString();
    }
  }

  Future<void> _ensureLoadedForMutation() => ensureLoaded();

  void _requireReadyForExplicitMutation() {
    if (isReady) return;
    throw PrefixRouteRepositoryException(
      'store_unavailable',
      'Stored Prefix route data must be reset or replaced before it can be edited.',
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final current = _writeTail.then((_) => operation());
    _writeTail = current.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return current;
  }

  Future<void> _persist(
    WorkImageRouteDocument next, {
    bool allowCorruptRecovery = false,
  }) async {
    if (!isReady && !allowCorruptRecovery) return;
    final encoded = PrefixRouteDocumentCodec.encode(
      next,
      includeStatistics: true,
    );
    await _write(encoded);
    _document = next;
    _loadStatus = PrefixRouteStoreLoadStatus.ready;
    _loadError = null;
  }

  WorkImageRouteDocument _replaceRule(
    String prefix,
    WorkImagePrefixRouteRule rule,
  ) {
    final routes = <String, WorkImagePrefixRouteRule>{..._document.routes};
    routes[prefix] = rule;
    _bumpRevision(prefix);
    return _document.copyWith(routes: routes);
  }

  WorkImageRouteDocument _removeRule(String prefix) {
    final routes = <String, WorkImagePrefixRouteRule>{..._document.routes}
      ..remove(prefix);
    return _document.copyWith(routes: routes);
  }

  void _bumpRevision(String prefix) {
    _prefixRevisions[prefix] = revisionFor(prefix) + 1;
  }

  WorkImagePrefixRouteRule? _mergeRule(
    WorkImagePrefixRouteRule local,
    WorkImagePrefixRouteRule imported,
  ) {
    final candidates = <WorkImageNormalizationFamily, WorkImageRouteCandidate>{
      for (final candidate in local.candidates) candidate.family: candidate,
    };
    for (final candidate in imported.candidates) {
      // Existing local stats are the source of truth.  Imported statistics
      // seed only a genuinely new family.
      candidates.putIfAbsent(candidate.family, () => candidate);
    }
    final manual = local.manualOverride ?? imported.manualOverride;
    final preferred = local.preferredFamily ?? imported.preferredFamily;
    return WorkImagePrefixRouteRule(
      prefix: local.prefix,
      candidates: candidates.values,
      manualOverride: manual,
      preferredFamily: preferred,
      createdAt: local.createdAt ?? imported.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  WorkImageRouteDocument _merge(WorkImageRouteDocument imported) {
    final routes = <String, WorkImagePrefixRouteRule>{..._document.routes};
    for (final entry in imported.routes.entries) {
      final local = routes[entry.key];
      routes[entry.key] = local == null
          ? entry.value
          : _mergeRule(local, entry.value)!;
      _bumpRevision(entry.key);
    }
    return _document.copyWith(routes: routes);
  }

  PrefixRouteImportResult _summarizeImport(WorkImageRouteDocument imported) {
    var newRules = 0;
    var newCandidates = 0;
    var changedCandidates = 0;
    var manualConflicts = 0;
    for (final entry in imported.routes.entries) {
      final existing = _document.routes[entry.key];
      if (existing == null) {
        newRules++;
        newCandidates += entry.value.candidates.length;
        continue;
      }
      if (existing.manualOverride != null &&
          entry.value.manualOverride != null &&
          existing.manualOverride != entry.value.manualOverride) {
        manualConflicts++;
      }
      for (final candidate in entry.value.candidates) {
        final local = existing.candidateFor(candidate.family);
        if (local == null) {
          newCandidates++;
        } else if (local.successCount != candidate.successCount ||
            local.failureCount != candidate.failureCount) {
          changedCandidates++;
        }
      }
    }
    return PrefixRouteImportResult(
      importedRuleCount: imported.routes.length,
      newRuleCount: newRules,
      newCandidateCount: newCandidates,
      changedCandidateCount: changedCandidates,
      manualConflictCount: manualConflicts,
    );
  }

  String _requirePrefix(String value) {
    final prefix = normalizeWorkImagePrefix(value);
    if (prefix == null) {
      throw const PrefixRouteRepositoryException(
        'invalid_prefix',
        'The Prefix is not valid.',
      );
    }
    return prefix;
  }
}

final class _DecodedPrefixRouteDocument {
  const _DecodedPrefixRouteDocument({
    required this.document,
    required this.rulesOnly,
  });

  final WorkImageRouteDocument document;
  final bool rulesOnly;
}

final class PrefixRouteDocumentCodec {
  const PrefixRouteDocumentCodec._();

  static String encode(
    WorkImageRouteDocument document, {
    required bool includeStatistics,
  }) {
    final routes = <String, Object?>{};
    final keys = document.routes.keys.toList()..sort();
    for (final prefix in keys) {
      final rule = document.routes[prefix]!;
      final candidates = [...rule.candidates]
        ..sort(
          (a, b) => workImageDefaultProbeOrder
              .indexOf(a.family)
              .compareTo(workImageDefaultProbeOrder.indexOf(b.family)),
        );
      routes[prefix] = <String, Object?>{
        'manualFamily': rule.manualOverride?.name,
        'preferredFamily': rule.preferredFamily?.name,
        'candidates': [
          for (final candidate in candidates)
            <String, Object?>{
              'family': candidate.family.name,
              if (includeStatistics) ...{
                'successCount': candidate.successCount,
                'failureCount': candidate.failureCount,
                'lastSuccessAt': candidate.lastSuccessAt
                    ?.toUtc()
                    .toIso8601String(),
                'lastFailureAt': candidate.lastFailureAt
                    ?.toUtc()
                    .toIso8601String(),
              },
            },
        ],
        if (includeStatistics && rule.createdAt != null)
          'createdAt': rule.createdAt!.toUtc().toIso8601String(),
        if (includeStatistics && rule.updatedAt != null)
          'updatedAt': rule.updatedAt!.toUtc().toIso8601String(),
      };
    }
    return const JsonEncoder.withIndent('  ').convert({
      'kind': 'avaca.workImagePrefixRoutes',
      'schemaVersion': WorkImageRouteDocument.currentSchemaVersion,
      'exportMode': includeStatistics ? 'full' : 'rulesOnly',
      'routes': routes,
    });
  }

  static _DecodedPrefixRouteDocument _decode(String rawJson) {
    dynamic decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on Object catch (error) {
      throw PrefixRouteRepositoryException(
        'invalid_json',
        'The Prefix route file is not valid JSON: $error',
      );
    }
    if (decoded is! Map) {
      throw const PrefixRouteRepositoryException(
        'invalid_document',
        'The Prefix route file must contain a JSON object.',
      );
    }
    final map = Map<String, dynamic>.from(decoded);
    const allowedDocumentFields = {
      'kind',
      'schemaVersion',
      'exportMode',
      'routes',
    };
    if (map.keys.any((key) => !allowedDocumentFields.contains(key))) {
      throw const PrefixRouteRepositoryException(
        'invalid_fields',
        'The Prefix route document contains an unknown field.',
      );
    }
    final schemaVersion = map['schemaVersion'];
    if (schemaVersion != WorkImageRouteDocument.currentSchemaVersion) {
      throw const PrefixRouteRepositoryException(
        'unsupported_schema',
        'The Prefix route file uses an unsupported schema version.',
      );
    }
    final kind = map['kind'];
    if (kind != null && kind != 'avaca.workImagePrefixRoutes') {
      throw const PrefixRouteRepositoryException(
        'invalid_document',
        'The file is not an AVACA Prefix route document.',
      );
    }
    final exportMode = map['exportMode'];
    if (exportMode != null &&
        exportMode != 'full' &&
        exportMode != 'rulesOnly') {
      throw const PrefixRouteRepositoryException(
        'invalid_document',
        'The Prefix route export mode is invalid.',
      );
    }
    final routesValue = map['routes'];
    if (routesValue is! Map || routesValue.length > 10000) {
      throw const PrefixRouteRepositoryException(
        'invalid_routes',
        'The Prefix route document contains an invalid routes map.',
      );
    }
    final routes = <String, WorkImagePrefixRouteRule>{};
    var detectedRulesOnly = exportMode == 'rulesOnly';
    for (final entry in routesValue.entries) {
      final rawPrefix = entry.key?.toString();
      final prefix = normalizeWorkImagePrefix(rawPrefix);
      if (prefix == null) {
        throw const PrefixRouteRepositoryException(
          'invalid_prefix',
          'The Prefix route document contains an invalid Prefix.',
        );
      }
      if (routes.containsKey(prefix)) {
        throw const PrefixRouteRepositoryException(
          'duplicate_prefix',
          'The Prefix route document contains duplicate Prefixes.',
        );
      }
      final route = _decodeRule(prefix, entry.value, exportMode);
      detectedRulesOnly = detectedRulesOnly || route.rulesOnly;
      routes[prefix] = route.rule;
    }
    return _DecodedPrefixRouteDocument(
      document: WorkImageRouteDocument(
        schemaVersion: WorkImageRouteDocument.currentSchemaVersion,
        routes: routes,
      ),
      rulesOnly: detectedRulesOnly,
    );
  }

  static _DecodedRule _decodeRule(
    String prefix,
    dynamic raw,
    String? exportMode,
  ) {
    WorkImageNormalizationFamily? manual;
    WorkImageNormalizationFamily? preferred;
    DateTime? createdAt;
    DateTime? updatedAt;
    final candidates = <WorkImageRouteCandidate>[];
    var rulesOnly = exportMode == 'rulesOnly';

    if (raw is List) {
      for (final value in raw) {
        final family = _decodeFamily(value);
        if (candidates.any((candidate) => candidate.family == family)) {
          throw const PrefixRouteRepositoryException(
            'duplicate_family',
            'The Prefix route document contains duplicate families.',
          );
        }
        candidates.add(WorkImageRouteCandidate(family: family));
      }
      rulesOnly = true;
    } else if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      const allowed = {
        'manualFamily',
        'preferredFamily',
        'candidates',
        'createdAt',
        'updatedAt',
      };
      if (map.keys.any((key) => !allowed.contains(key))) {
        throw const PrefixRouteRepositoryException(
          'invalid_fields',
          'The Prefix route document contains an unknown field.',
        );
      }
      manual = _decodeNullableFamily(map['manualFamily']);
      preferred = _decodeNullableFamily(map['preferredFamily']);
      createdAt = _decodeTime(map['createdAt']);
      updatedAt = _decodeTime(map['updatedAt']);
      final values = map['candidates'];
      if (values is! List ||
          values.length > workImageDefaultProbeOrder.length) {
        throw const PrefixRouteRepositoryException(
          'invalid_candidates',
          'The Prefix route document contains invalid candidates.',
        );
      }
      for (final value in values) {
        final decodedCandidate = _decodeCandidate(value, exportMode);
        rulesOnly = rulesOnly || decodedCandidate.rulesOnly;
        if (candidates.any(
          (candidate) => candidate.family == decodedCandidate.candidate.family,
        )) {
          throw const PrefixRouteRepositoryException(
            'duplicate_family',
            'The Prefix route document contains duplicate families.',
          );
        }
        candidates.add(decodedCandidate.candidate);
      }
    } else {
      throw const PrefixRouteRepositoryException(
        'invalid_route',
        'The Prefix route document contains an invalid rule.',
      );
    }

    if (manual != null &&
        candidates.every((candidate) => candidate.family != manual)) {
      candidates.add(WorkImageRouteCandidate(family: manual));
    }
    if (preferred != null &&
        candidates.every((candidate) => candidate.family != preferred)) {
      throw const PrefixRouteRepositoryException(
        'invalid_preferred_family',
        'The preferred family is not present in the candidate list.',
      );
    }
    if (candidates.isEmpty) {
      throw const PrefixRouteRepositoryException(
        'empty_route',
        'A Prefix route must contain at least one candidate.',
      );
    }
    return _DecodedRule(
      rule: WorkImagePrefixRouteRule(
        prefix: prefix,
        candidates: candidates,
        manualOverride: manual,
        preferredFamily: preferred,
        createdAt: createdAt,
        updatedAt: updatedAt,
      ),
      rulesOnly: rulesOnly,
    );
  }

  static _DecodedCandidate _decodeCandidate(dynamic raw, String? exportMode) {
    if (raw is String) {
      return _DecodedCandidate(
        candidate: WorkImageRouteCandidate(family: _decodeFamily(raw)),
        rulesOnly: true,
      );
    }
    if (raw is! Map) {
      throw const PrefixRouteRepositoryException(
        'invalid_candidate',
        'The Prefix route document contains an invalid candidate.',
      );
    }
    final map = Map<String, dynamic>.from(raw);
    const allowed = {
      'family',
      'successCount',
      'failureCount',
      'lastSuccessAt',
      'lastFailureAt',
    };
    if (map.keys.any((key) => !allowed.contains(key)) ||
        map['family'] is! String) {
      throw const PrefixRouteRepositoryException(
        'invalid_candidate',
        'The Prefix route candidate fields are invalid.',
      );
    }
    final successCount = _decodeCount(map['successCount']);
    final failureCount = _decodeCount(map['failureCount']);
    final lastSuccessAt = _decodeTime(map['lastSuccessAt']);
    final lastFailureAt = _decodeTime(map['lastFailureAt']);
    final hasStatistics = map.keys.any(
      (key) =>
          key == 'successCount' ||
          key == 'failureCount' ||
          key == 'lastSuccessAt' ||
          key == 'lastFailureAt',
    );
    if (!hasStatistics && exportMode == 'full') {
      throw const PrefixRouteRepositoryException(
        'invalid_candidate',
        'A full Prefix route candidate is missing statistics.',
      );
    }
    return _DecodedCandidate(
      candidate: WorkImageRouteCandidate(
        family: _decodeFamily(map['family']),
        successCount: successCount,
        failureCount: failureCount,
        lastSuccessAt: lastSuccessAt,
        lastFailureAt: lastFailureAt,
      ),
      rulesOnly: !hasStatistics,
    );
  }

  static WorkImageNormalizationFamily _decodeFamily(dynamic raw) {
    final family = workImageNormalizationFamilyFromName(raw?.toString());
    if (family == null) {
      throw const PrefixRouteRepositoryException(
        'invalid_family',
        'The Prefix route document contains an unknown image family.',
      );
    }
    return family;
  }

  static WorkImageNormalizationFamily? _decodeNullableFamily(dynamic raw) {
    if (raw == null) return null;
    return _decodeFamily(raw);
  }

  static int _decodeCount(dynamic raw) {
    if (raw == null) return 0;
    if (raw is! int || raw < 0 || raw > 0x7fffffff) {
      throw const PrefixRouteRepositoryException(
        'invalid_statistics',
        'The Prefix route statistics are invalid.',
      );
    }
    return raw;
  }

  static DateTime? _decodeTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is! String) {
      throw const PrefixRouteRepositoryException(
        'invalid_timestamp',
        'The Prefix route timestamp is invalid.',
      );
    }
    try {
      return DateTime.parse(raw).toUtc();
    } on FormatException {
      throw const PrefixRouteRepositoryException(
        'invalid_timestamp',
        'The Prefix route timestamp is invalid.',
      );
    }
  }
}

final class _DecodedRule {
  const _DecodedRule({required this.rule, required this.rulesOnly});

  final WorkImagePrefixRouteRule rule;
  final bool rulesOnly;
}

final class _DecodedCandidate {
  const _DecodedCandidate({required this.candidate, required this.rulesOnly});

  final WorkImageRouteCandidate candidate;
  final bool rulesOnly;
}
