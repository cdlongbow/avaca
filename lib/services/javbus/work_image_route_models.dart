import 'work_image_route_resolver.dart';

enum WorkImageRouteCandidateStatus { untested, healthy, degraded, failed }

enum WorkImagePrefixRouteStatus {
  verified,
  hasExceptions,
  pendingValidation,
  probeFailed,
}

final class WorkImageRouteCandidate {
  const WorkImageRouteCandidate({
    required this.family,
    this.successCount = 0,
    this.failureCount = 0,
    this.lastSuccessAt,
    this.lastFailureAt,
  }) : assert(successCount >= 0),
       assert(failureCount >= 0);

  final WorkImageNormalizationFamily family;
  final int successCount;
  final int failureCount;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;

  WorkImageRouteCandidateStatus get status {
    if (successCount == 0 && failureCount == 0) {
      return WorkImageRouteCandidateStatus.untested;
    }
    final failureIsLatest =
        lastFailureAt != null &&
        (lastSuccessAt == null || lastFailureAt!.isAfter(lastSuccessAt!));
    if (failureIsLatest) {
      return successCount > 0
          ? WorkImageRouteCandidateStatus.degraded
          : WorkImageRouteCandidateStatus.failed;
    }
    return successCount > 0
        ? WorkImageRouteCandidateStatus.healthy
        : WorkImageRouteCandidateStatus.failed;
  }

  WorkImageRouteCandidate copyWith({
    int? successCount,
    int? failureCount,
    DateTime? lastSuccessAt,
    DateTime? lastFailureAt,
  }) {
    return WorkImageRouteCandidate(
      family: family,
      successCount: successCount ?? this.successCount,
      failureCount: failureCount ?? this.failureCount,
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      lastFailureAt: lastFailureAt ?? this.lastFailureAt,
    );
  }

  WorkImageRouteCandidate withSuccess(DateTime at) {
    return WorkImageRouteCandidate(
      family: family,
      successCount: successCount + 1,
      failureCount: failureCount,
      lastSuccessAt: at,
      lastFailureAt: lastFailureAt,
    );
  }

  WorkImageRouteCandidate withFailure(DateTime at) {
    return WorkImageRouteCandidate(
      family: family,
      successCount: successCount,
      failureCount: failureCount + 1,
      lastSuccessAt: lastSuccessAt,
      lastFailureAt: at,
    );
  }
}

final class WorkImagePrefixRouteRule {
  WorkImagePrefixRouteRule({
    required this.prefix,
    Iterable<WorkImageRouteCandidate> candidates = const [],
    this.manualOverride,
    this.preferredFamily,
    this.createdAt,
    this.updatedAt,
  }) : candidates = List.unmodifiable(
         candidates.toList()..sort(compareWorkImageCandidates),
       );

  final String prefix;
  final List<WorkImageRouteCandidate> candidates;
  final WorkImageNormalizationFamily? manualOverride;
  final WorkImageNormalizationFamily? preferredFamily;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  WorkImageRouteCandidate? candidateFor(WorkImageNormalizationFamily family) {
    for (final candidate in candidates) {
      if (candidate.family == family) return candidate;
    }
    return null;
  }

  WorkImageRouteCandidate? get preferredCandidate {
    final family = preferredFamily;
    return family == null ? null : candidateFor(family);
  }

  WorkImageRouteCandidate? get effectiveCandidate {
    final family = manualOverride ?? preferredFamily;
    return family == null ? null : candidateFor(family);
  }

  WorkImagePrefixRouteStatus get status {
    final candidate = effectiveCandidate;
    if (candidate == null) {
      return WorkImagePrefixRouteStatus.probeFailed;
    }
    return switch (candidate.status) {
      WorkImageRouteCandidateStatus.healthy =>
        WorkImagePrefixRouteStatus.verified,
      WorkImageRouteCandidateStatus.degraded =>
        WorkImagePrefixRouteStatus.hasExceptions,
      WorkImageRouteCandidateStatus.untested =>
        WorkImagePrefixRouteStatus.pendingValidation,
      WorkImageRouteCandidateStatus.failed =>
        WorkImagePrefixRouteStatus.probeFailed,
    };
  }

  WorkImagePrefixRouteRule copyWith({
    Iterable<WorkImageRouteCandidate>? candidates,
    WorkImageNormalizationFamily? preferredFamily,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WorkImagePrefixRouteRule(
      prefix: prefix,
      candidates: candidates ?? this.candidates,
      manualOverride: manualOverride,
      preferredFamily: preferredFamily ?? this.preferredFamily,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  WorkImagePrefixRouteRule withManualOverride(
    WorkImageNormalizationFamily? family,
  ) {
    return WorkImagePrefixRouteRule(
      prefix: prefix,
      candidates: candidates,
      manualOverride: family,
      preferredFamily: preferredFamily,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

final class WorkImageRouteDocument {
  const WorkImageRouteDocument({
    required this.schemaVersion,
    required this.routes,
  });

  static const currentSchemaVersion = 1;

  factory WorkImageRouteDocument.empty() {
    return const WorkImageRouteDocument(
      schemaVersion: currentSchemaVersion,
      routes: <String, WorkImagePrefixRouteRule>{},
    );
  }

  final int schemaVersion;
  final Map<String, WorkImagePrefixRouteRule> routes;

  WorkImageRouteDocument copyWith({
    Map<String, WorkImagePrefixRouteRule>? routes,
  }) {
    return WorkImageRouteDocument(
      schemaVersion: schemaVersion,
      routes: Map.unmodifiable(routes ?? this.routes),
    );
  }
}

int compareWorkImageCandidates(
  WorkImageRouteCandidate left,
  WorkImageRouteCandidate right,
) {
  final leftSuccess = left.lastSuccessAt;
  final rightSuccess = right.lastSuccessAt;
  if (leftSuccess != null || rightSuccess != null) {
    final byTime = (rightSuccess ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(leftSuccess ?? DateTime.fromMillisecondsSinceEpoch(0));
    if (byTime != 0) return byTime;
  }
  final bySuccess = right.successCount.compareTo(left.successCount);
  if (bySuccess != 0) return bySuccess;
  final byFailure = left.failureCount.compareTo(right.failureCount);
  if (byFailure != 0) return byFailure;
  return workImageDefaultProbeOrder
      .indexOf(left.family)
      .compareTo(workImageDefaultProbeOrder.indexOf(right.family));
}
