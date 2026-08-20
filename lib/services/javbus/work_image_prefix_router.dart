import 'dart:typed_data';

import 'work_image_policy.dart';
import 'work_image_route_models.dart';
import 'work_image_route_resolver.dart';
import 'prefix_route_repository.dart';
import '../scrape/work_code_canonicalizer.dart';

enum WorkImageRouteProbeFailureKind {
  definitiveMiss,
  transientNetwork,
  policyViolation,
}

final class WorkImageRouteProbeException implements Exception {
  const WorkImageRouteProbeException({
    required this.uri,
    required this.kind,
    this.statusCode,
    this.cause,
    this.recordFailure = true,
  });

  final Uri uri;
  final WorkImageRouteProbeFailureKind kind;
  final int? statusCode;
  final Object? cause;
  final bool recordFailure;

  @override
  String toString() => 'Image route probe failed (${kind.name}): $uri';
}

final class WorkImageRouteResolutionException implements Exception {
  const WorkImageRouteResolutionException({
    required this.prefix,
    required this.attemptedFamilies,
    this.lastUri,
  });

  final String prefix;
  final List<WorkImageNormalizationFamily> attemptedFamilies;
  final Uri? lastUri;

  @override
  String toString() =>
      'No valid image route was found for $prefix after trying '
      '${attemptedFamilies.map((family) => family.name).join(', ')}';
}

final class WorkImageRouteProbeResult {
  const WorkImageRouteProbeResult({
    required this.bytes,
    required this.sourceUri,
  });

  final Uint8List bytes;
  final Uri sourceUri;
}

final class WorkImageRouteDecision {
  const WorkImageRouteDecision({
    required this.family,
    this.probeResult,
    this.probeVariant,
    this.probeWorkCode,
    this.revisionToken,
  });

  final WorkImageNormalizationFamily family;
  final WorkImageRouteProbeResult? probeResult;
  final WorkImageVariant? probeVariant;
  final String? probeWorkCode;
  final PrefixRouteRevisionToken? revisionToken;
}

typedef WorkImageRouteProbe =
    Future<WorkImageRouteProbeResult> Function(
      WorkImageNormalizationFamily family,
    );

/// Resolves one Prefix at a time while allowing unrelated Prefixes to probe in
/// parallel.  The returned probe result is reusable when the waiting caller
/// asks for the same card/detail variant; otherwise only the learned family is
/// shared and the caller requests its own variant once.
final class WorkImagePrefixRouter {
  WorkImagePrefixRouter({required this.repository});

  final PrefixRouteRepository repository;
  final Map<String, Future<WorkImageRouteDecision>> _inFlight = {};

  Future<WorkImageRouteDecision> resolve({
    required String prefix,
    required WorkImageVariant variant,
    required WorkImageRouteProbe probe,
    String? probeWorkCode,
  }) async {
    final normalizedPrefix = normalizeWorkImagePrefix(prefix) ?? prefix;
    final existing = _inFlight[normalizedPrefix];
    if (existing != null) {
      return existing;
    }

    late final Future<WorkImageRouteDecision> operation;
    operation = _resolve(
      prefix: normalizedPrefix,
      variant: variant,
      probe: probe,
      probeWorkCode: probeWorkCode,
    );
    _inFlight[normalizedPrefix] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_inFlight[normalizedPrefix], operation)) {
        _inFlight.remove(normalizedPrefix);
      }
    }
  }

  Future<WorkImageRouteDecision> _resolve({
    required String prefix,
    required WorkImageVariant variant,
    required WorkImageRouteProbe probe,
    String? probeWorkCode,
  }) async {
    await repository.ensureLoaded();
    final ruleAtStart = repository.ruleFor(prefix);
    final revisionTokenAtStart = repository.revisionTokenFor(prefix);
    final attempted = <WorkImageNormalizationFamily>[];
    final definitiveFailures = <WorkImageNormalizationFamily>[];
    WorkImageRouteProbeException? lastFailure;

    for (final family in repository.orderedFamiliesFor(prefix)) {
      attempted.add(family);
      try {
        final result = await probe(family);
        await repository.recordSuccess(
          prefix: prefix,
          family: family,
          definitiveFailures: definitiveFailures,
          expectedRevisionToken: revisionTokenAtStart,
        );
        return WorkImageRouteDecision(
          family: family,
          probeResult: result,
          probeVariant: variant,
          probeWorkCode: probeWorkCode,
          revisionToken: repository.revisionTokenFor(prefix),
        );
      } on WorkImageRouteProbeException catch (error) {
        lastFailure = error;
        if (error.kind != WorkImageRouteProbeFailureKind.definitiveMiss) {
          // A timeout/socket/429/5xx must never cause a second family to be
          // requested.  Definite misses that occurred before it are still
          // safe to record for an already-known Prefix.
          await _recordKnownDefinitiveFailures(
            prefix,
            ruleAtStart,
            definitiveFailures,
            revisionTokenAtStart,
          );
          rethrow;
        }
        if (error.recordFailure) {
          definitiveFailures.add(family);
        }
      }
    }

    // Unknown Prefixes intentionally remain absent after an all-miss probe.
    // For an existing rule, retain its history and add only the attempted
    // definitive misses.
    await _recordKnownDefinitiveFailures(
      prefix,
      ruleAtStart,
      definitiveFailures,
      revisionTokenAtStart,
    );
    throw WorkImageRouteResolutionException(
      prefix: prefix,
      attemptedFamilies: List.unmodifiable(attempted),
      lastUri: lastFailure?.uri,
    );
  }

  Future<void> _recordKnownDefinitiveFailures(
    String prefix,
    WorkImagePrefixRouteRule? ruleAtStart,
    Iterable<WorkImageNormalizationFamily> families,
    PrefixRouteRevisionToken expectedRevisionToken,
  ) async {
    if (ruleAtStart == null) {
      return;
    }
    await repository.recordDefinitiveFailures(
      prefix: prefix,
      families: families,
      expectedRevisionToken: expectedRevisionToken,
    );
  }
}
