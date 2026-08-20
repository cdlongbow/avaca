import 'dart:typed_data';

import 'work_image_policy.dart';
import 'work_image_route_models.dart';
import 'work_image_route_resolver.dart';
import 'prefix_route_repository.dart';

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
  });

  final WorkImageNormalizationFamily family;
  final WorkImageRouteProbeResult? probeResult;
  final WorkImageVariant? probeVariant;
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
  }) async {
    final existing = _inFlight[prefix];
    if (existing != null) {
      return existing;
    }

    late final Future<WorkImageRouteDecision> operation;
    operation = _resolve(prefix: prefix, variant: variant, probe: probe);
    _inFlight[prefix] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_inFlight[prefix], operation)) {
        _inFlight.remove(prefix);
      }
    }
  }

  Future<WorkImageRouteDecision> _resolve({
    required String prefix,
    required WorkImageVariant variant,
    required WorkImageRouteProbe probe,
  }) async {
    await repository.ensureLoaded();
    final ruleAtStart = repository.ruleFor(prefix);
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
        );
        return WorkImageRouteDecision(
          family: family,
          probeResult: result,
          probeVariant: variant,
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
  ) async {
    if (ruleAtStart == null) {
      return;
    }
    for (final family in families) {
      await repository.recordDefinitiveFailure(prefix: prefix, family: family);
    }
  }
}
