import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../core/database.dart';
import '../models/scrape_source_settings.dart';
import '../models/scrape_exclusion_policy.dart';
import '../models/scrape_rules.dart';
import '../models/scraped_actress_details.dart';
import '../models/work_scrape_options.dart';
import 'avbase/avbase_models.dart';
import 'javbus/javbus_client.dart';
import 'javbus/javbus_scrape_source.dart';
import 'javbus/javbus_verification.dart';
import 'javbus/prefix_route_repository.dart';
import 'javbus/work_image_downloader.dart';
import 'javbus/work_image_policy.dart';
import 'safe_image.dart';
import 'scrape/scrape_image_downloader.dart';
import 'scrape/scrape_models.dart';
import 'scrape_run_observer.dart';
import 'scrape/scrape_source.dart';
import 'scrape/scrape_source_registry.dart';
import 'scrape/work_identity.dart';
import 'scrape_exclusion_policy_evaluator.dart';

abstract interface class ActressImageDownloader {
  Future<String> download(Uri uri, String targetPath);
}

class HttpActressImageDownloader implements ActressImageDownloader {
  HttpActressImageDownloader({
    BinaryTransport? transport,
    JavBusBinarySession? authenticatedTransport,
  }) : assert(transport == null || authenticatedTransport == null),
       _authenticatedTransport = authenticatedTransport,
       _transport = authenticatedTransport == null
           ? transport ??
                 HttpBinaryTransport(
                   allowedHosts: const {'www.javbus.com'},
                   maxBytes: 5 * 1024 * 1024,
                 )
           : null;

  final BinaryTransport? _transport;
  final JavBusBinarySession? _authenticatedTransport;

  @override
  Future<String> download(Uri uri, String targetPath) async {
    final response =
        await (_authenticatedTransport?.getBinary(uri) ?? _transport!.get(uri));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WorksScrapeException('Actress image request failed: $uri');
    }
    final bytes = Uint8List.fromList(response.bodyBytes);
    if (!isSafeDecodableImage(bytes)) {
      throw WorksScrapeException('Actress image is invalid: $uri');
    }
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  void close() {
    final transport = _transport;
    if (transport is HttpBinaryTransport) {
      transport.close();
    }
  }
}

enum ActressImageSyncStatus {
  notRequested,
  replaced,
  unavailable,
  downloadFailed,
  databaseFailed,
}

class WorksScrapeCancellationToken {
  bool _cancelled = false;
  bool _paused = false;

  /// A pause is a cooperative stop for the current run; it is not a
  /// terminal cancellation. The coordinator will create a fresh token when
  /// the paused job is resumed.
  bool get isPauseRequested => _paused;
  bool get isCancelRequested => _cancelled;
  bool get isCancelled => isCancelRequested;
  bool get isPaused => isPauseRequested;
  bool get shouldStop => isCancelRequested || isPauseRequested;

  void cancel() {
    _cancelled = true;
    _paused = false;
  }

  void pause() {
    if (!_cancelled) _paused = true;
  }

  void resume() {
    if (!_cancelled) _paused = false;
  }
}

enum WorksScrapePhase {
  collectingSources,
  syncingActress,
  fetchingDetails,
  resolvingWorks,
  savingWorks,
  downloadingImages,
  completed,
}

enum WorksScrapeFailureStage { fetchingDetails, resolvingWorks, savingWorks }

enum WorksScrapeFailureReason {
  detailsUnavailable,
  detailCodeMismatch,
  invalidCode,
  databaseSaveFailed,
}

final class WorksScrapeFailure {
  const WorksScrapeFailure({
    required this.code,
    required this.stage,
    required this.reason,
    this.source,
    this.error,
  });

  final String code;
  final WorksScrapeFailureStage stage;
  final WorksScrapeFailureReason reason;
  final ScrapeSourceId? source;
  final Object? error;
}

final class WorksScrapeImageFailure {
  const WorksScrapeImageFailure({required this.code, required this.variants});

  final String code;
  final List<WorkImageVariant> variants;
}

final class WorksScrapeSourceProgress {
  const WorksScrapeSourceProgress({
    required this.phase,
    required this.current,
    required this.total,
    this.totalKnown = false,
    this.workCode,
    this.discovered = 0,
  });

  final WorksScrapePhase phase;
  final int current;
  final int total;
  final bool totalKnown;
  final String? workCode;
  final int discovered;

  bool get hasKnownTotal => totalKnown;
}

class WorksScrapeProgress {
  const WorksScrapeProgress({
    required this.current,
    required this.total,
    required this.saved,
    required this.excluded,
    required this.failed,
    this.totalKnown = false,
    this.phase = WorksScrapePhase.savingWorks,
    this.source,
    this.workCode,
    this.sourceProgress = const {},
    this.detailsSource,
    this.worksSources = const [],
    this.rawDiscovered = 0,
    this.duplicateCount = 0,
    this.detailCompleted = 0,
    this.detailTotal = 0,
    this.supplementalEvidenceCompleted = 0,
    this.supplementalEvidenceTotal = 0,
    this.review = 0,
  });

  final WorksScrapePhase phase;
  final int current;
  final int total;
  final int saved;
  final int excluded;
  final int failed;
  final bool totalKnown;
  final ScrapeSourceId? source;
  final String? workCode;
  final Map<ScrapeSourceId, WorksScrapeSourceProgress> sourceProgress;

  bool get hasKnownTotal => totalKnown;

  /// The source currently responsible for actress profile synchronization.
  ///
  /// This is presentation metadata. It keeps a details-only source from being
  /// rendered as a work source when the same source run result has no works.
  final ScrapeSourceId? detailsSource;

  /// Sources that participate in the aggregate work pipeline.
  ///
  /// The list is intentionally source-oriented so adding another works source
  /// only adds another row to the dialog.
  final List<ScrapeSourceId> worksSources;
  final int rawDiscovered;
  final int duplicateCount;
  final int detailCompleted;
  final int detailTotal;
  final int supplementalEvidenceCompleted;
  final int supplementalEvidenceTotal;
  final int review;

  int get confidentKeep => saved > review ? saved - review : 0;
}

class WorksScrapeResult {
  const WorksScrapeResult({
    required this.saved,
    required this.excluded,
    required this.failed,
    required this.cancelled,
    this.review = 0,
    this.actressImageStatus = ActressImageSyncStatus.notRequested,
    this.partialSuccess = false,
    this.sourceResults = const {},
    this.failedWorks = const [],
    this.imageFailures = const [],
    this.detailsSource,
    this.worksSources = const [],
  });

  final int saved;
  final int excluded;
  final int failed;
  final bool cancelled;
  final int review;
  final ActressImageSyncStatus actressImageStatus;
  final bool partialSuccess;
  final Map<ScrapeSourceId, ScrapeSourceRunResult> sourceResults;
  final List<WorksScrapeFailure> failedWorks;
  final List<WorksScrapeImageFailure> imageFailures;

  /// The source that supplied actress details, separate from work sources.
  final ScrapeSourceId? detailsSource;

  /// Work sources whose results were merged into the aggregate counters.
  final List<ScrapeSourceId> worksSources;

  int get confidentKeep => saved > review ? saved - review : 0;
}

class WorksScrapeException implements Exception {
  const WorksScrapeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WorksScrapeService {
  WorksScrapeService({
    required this.db,
    JavBusClient? client,
    Map<ScrapeSourceId, ScrapeSource>? sources,
    WorkImageDownloader? workImageDownloader,
    ActressImageDownloader? actressImageDownloader,
    this.imageUriDownloader,
    String? imageDirectory,
    this.javBusDetailDelay = const Duration(milliseconds: 600),
  }) : sources = sources ?? _singleJavBusSource(client),
       workImageDownloader =
           workImageDownloader ??
           WorkImageDownloader(
             routeRepository: PrefixRouteRepository.forDatabase(db),
           ),
       actressImageDownloader =
           actressImageDownloader ?? HttpActressImageDownloader(),
       imageDirectory = imageDirectory ?? path.join(db.imgDir, 'scraped');

  final AppDatabase db;
  final Map<ScrapeSourceId, ScrapeSource> sources;
  final WorkImageDownloader workImageDownloader;
  final ActressImageDownloader actressImageDownloader;
  final ScrapeImageUriDownloader? imageUriDownloader;
  final String imageDirectory;
  final Duration javBusDetailDelay;
  ScrapeRunObserver? _observer;
  final Map<ScrapeSourceId, WorksScrapeSourceProgress> _sourceProgress = {};
  ScrapeSourceId? _detailsSource;
  List<ScrapeSourceId> _worksSources = const [];
  int _rawDiscovered = 0;
  int _duplicateCount = 0;
  int _detailCompleted = 0;
  int _detailTotal = 0;
  int _uniqueTotal = 0;
  int _supplementalEvidenceCompleted = 0;
  int _supplementalEvidenceTotal = 0;

  static Map<ScrapeSourceId, ScrapeSource> _singleJavBusSource(
    JavBusClient? client,
  ) {
    if (client == null) {
      throw ArgumentError('Either client or sources must be supplied.');
    }
    return {ScrapeSourceId.javbus: JavBusScrapeSource(client)};
  }

  void close() {
    final closed = <ScrapeSource>{};
    for (final source in sources.values) {
      if (closed.add(source)) {
        source.close();
      }
    }
    workImageDownloader.close();
    final imageDownloader = imageUriDownloader;
    imageDownloader?.close();
    final downloader = actressImageDownloader;
    if (downloader is HttpActressImageDownloader) {
      downloader.close();
    }
  }

  Future<WorksScrapeResult> scrape({
    required int actressId,
    required String actressName,
    List<String> aliases = const [],
    required WorkScrapeOptions options,
    ScrapeSourceSettings? sourceSettings,
    WorksScrapeCancellationToken? cancellationToken,
    void Function(WorksScrapeProgress progress)? onProgress,
    ScrapeRunObserver? observer,
    ScrapePolicySnapshot? policySnapshot,
  }) async {
    _observer = observer;
    _sourceProgress.clear();
    _detailsSource = null;
    _worksSources = const [];
    _rawDiscovered = 0;
    _duplicateCount = 0;
    _detailCompleted = 0;
    _detailTotal = 0;
    _uniqueTotal = 0;
    _supplementalEvidenceCompleted = 0;
    _supplementalEvidenceTotal = 0;
    final name = actressName.trim();
    if (name.isEmpty) {
      throw const WorksScrapeException('Actress name is empty.');
    }
    _notify(
      onProgress,
      0,
      0,
      0,
      0,
      0,
      phase: WorksScrapePhase.collectingSources,
    );
    final settings = sourceSettings ?? const ScrapeSourceSettings();
    final effectivePolicy =
        policySnapshot ??
        ScrapePolicySnapshot.current(
          rules: ScrapeRules.builtin,
          exactAllows: options.exactAllows,
          autoExcludeDerivedWorks: options.autoExcludeDerivedWorks,
          exactDenies: options.exactDenies,
        );
    final policyEvaluator = ScrapeExclusionPolicyEvaluator(effectivePolicy);
    final queries = _queries(name, aliases);
    final requestedWorkIds = ScrapeSourceRegistry.resolveWorksSources(
      settings.worksSources,
    );
    final aliasSourceId = options.scrapeAliases ? settings.aliasSource : null;
    _detailsSource = settings.actressDetailsSource;
    _worksSources = List.unmodifiable(requestedWorkIds);
    final sourceResults = <ScrapeSourceId, ScrapeSourceRunResult>{};
    final collectedById = <ScrapeSourceId, _CollectedSource>{};
    final collectionFutures =
        <ScrapeSourceId, Future<_SourceCollectionOutcome>>{};
    final auxiliaryCollectionFutures =
        <ScrapeSourceId, Future<_SourceCollectionOutcome>>{};

    void recordCollectionOutcome(
      ScrapeSourceId sourceId,
      _SourceCollectionOutcome outcome,
    ) {
      final collected = outcome.collected;
      if (collected != null) {
        collectedById[sourceId] = collected;
      }
      if (requestedWorkIds.contains(sourceId) ||
          sourceId == settings.actressDetailsSource ||
          sourceId == aliasSourceId) {
        sourceResults[sourceId] = outcome.result;
        _observer?.onSourceResult(outcome.result);
      }
    }

    Future<_SourceCollectionOutcome> startCollection(
      ScrapeSourceId sourceId, {
      required bool includeWorks,
    }) {
      _notify(
        onProgress,
        0,
        0,
        0,
        0,
        0,
        phase: WorksScrapePhase.collectingSources,
        source: sourceId,
      );
      final source = sources[sourceId];
      return source == null
          ? Future.value(
              _SourceCollectionOutcome(
                result: ScrapeSourceRunResult(
                  source: sourceId,
                  state: ScrapeSourceRunState.unavailable,
                  error: 'Source is not configured.',
                ),
              ),
            )
          : _collectSourceSafely(
              source: source,
              queries: queries,
              cancellationToken: cancellationToken,
              includeWorks: includeWorks,
              onCollectionProgress: (progress) {
                _notify(
                  onProgress,
                  progress.currentPage,
                  progress.totalPages,
                  0,
                  0,
                  0,
                  phase: WorksScrapePhase.collectingSources,
                  source: sourceId,
                  totalKnown: true,
                  sourceCurrent: progress.currentPage,
                  sourceTotal: progress.totalPages,
                  sourceTotalKnown: true,
                  sourceDiscovered: progress.discovered,
                );
              },
            );
    }

    Future<_SourceCollectionOutcome> ensureCollection(
      ScrapeSourceId sourceId,
    ) async {
      final future = collectionFutures[sourceId] ??= startCollection(
        sourceId,
        includeWorks: true,
      );
      final outcome = await future;
      recordCollectionOutcome(sourceId, outcome);
      return outcome;
    }

    // The first configured works source is the primary.  Actress details and
    // aliases may run in parallel, but later works sources are started only
    // when primary coverage or provenance evidence is insufficient.
    collectionFutures[requestedWorkIds.first] = startCollection(
      requestedWorkIds.first,
      includeWorks: true,
    );
    for (final sourceId in <ScrapeSourceId>{
      settings.actressDetailsSource,
      ?aliasSourceId,
    }) {
      if (sourceId == requestedWorkIds.first) continue;
      auxiliaryCollectionFutures[sourceId] = startCollection(
        sourceId,
        includeWorks: false,
      );
    }

    final sourcePipelines = _runConditionalWorkPipelines(
      requestedWorkIds: requestedWorkIds,
      collectedById: collectedById,
      retryWorkCodes: options.retryWorkCodes,
      policyEvaluator: policyEvaluator,
      ensureCollection: ensureCollection,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
    );

    final detailsSourceId = settings.actressDetailsSource;
    final detailsSource = sources[detailsSourceId];
    final detailsCollectionFuture =
        collectionFutures[detailsSourceId] ??
        auxiliaryCollectionFutures[detailsSourceId];
    final detailsOutcome = detailsCollectionFuture == null
        ? null
        : await detailsCollectionFuture;
    if (detailsOutcome != null) {
      recordCollectionOutcome(detailsSourceId, detailsOutcome);
    }
    final detailsCollection = detailsOutcome?.collected;
    ActressImageSyncStatus actressImageStatus = options.replaceActressImage
        ? ActressImageSyncStatus.unavailable
        : ActressImageSyncStatus.notRequested;
    if (detailsSource != null &&
        detailsCollection != null &&
        detailsCollection.pages.isNotEmpty) {
      _notify(
        onProgress,
        0,
        0,
        0,
        0,
        0,
        phase: WorksScrapePhase.syncingActress,
        source: detailsSourceId,
      );
      if (_isCancelled(cancellationToken)) {
        return WorksScrapeResult(
          saved: 0,
          excluded: 0,
          failed: 0,
          cancelled: true,
          sourceResults: Map.unmodifiable(sourceResults),
          detailsSource: _detailsSource,
          worksSources: _worksSources,
        );
      }
      final details = _mergeActressPages(
        detailsCollection.pages.values.toList(growable: false),
        source: detailsSource,
      );
      actressImageStatus = await _syncActress(
        actressId: actressId,
        details: details,
        source: detailsSource,
        options: options,
        cancellationToken: cancellationToken,
      );
      if (_isCancelled(cancellationToken)) {
        return WorksScrapeResult(
          saved: 0,
          excluded: 0,
          failed: 0,
          cancelled: true,
          actressImageStatus: actressImageStatus,
          sourceResults: Map.unmodifiable(sourceResults),
          detailsSource: _detailsSource,
          worksSources: _worksSources,
        );
      }
    }

    ScrapeSourceRunResult? aliasSyncResult;
    final aliasOutcome = aliasSourceId == null
        ? null
        : aliasSourceId == detailsSourceId
        ? detailsOutcome
        : await (collectionFutures[aliasSourceId] ??
              auxiliaryCollectionFutures[aliasSourceId]);
    final aliasId = aliasSourceId;
    if (aliasOutcome != null && aliasId != null && aliasId != detailsSourceId) {
      recordCollectionOutcome(aliasId, aliasOutcome);
    }
    final aliasPages = aliasOutcome?.collected?.pages.values.toList(
      growable: false,
    );
    if (aliasPages != null &&
        aliasPages.isNotEmpty &&
        !_isCancelled(cancellationToken)) {
      try {
        await _syncActressAliases(actressId: actressId, pages: aliasPages);
      } on Object catch (error) {
        if (aliasId != null) {
          final failedAliasResult = ScrapeSourceRunResult(
            source: aliasId,
            state: ScrapeSourceRunState.failed,
            error: error,
          );
          aliasSyncResult = failedAliasResult;
          sourceResults[aliasId] = failedAliasResult;
          _observer?.onSourceResult(failedAliasResult);
        }
      }
    }

    final pipelineResults = await sourcePipelines;
    for (final pipeline in pipelineResults) {
      recordCollectionOutcome(
        pipeline.sourceId,
        _SourceCollectionOutcome(
          collected: pipeline.collected,
          result: pipeline.result,
        ),
      );
    }
    if (aliasSyncResult != null) {
      sourceResults[aliasSyncResult.source] = aliasSyncResult;
    }

    if (_isCancelled(cancellationToken)) {
      return WorksScrapeResult(
        saved: 0,
        excluded: 0,
        failed: 0,
        cancelled: true,
        actressImageStatus: actressImageStatus,
        sourceResults: Map.unmodifiable(sourceResults),
        detailsSource: _detailsSource,
        worksSources: _worksSources,
      );
    }

    final successfulWorkSources = pipelineResults
        .where(
          (pipeline) =>
              requestedWorkIds.contains(pipeline.sourceId) &&
              pipeline.collected?.result.succeeded == true,
        )
        .toList(growable: false);
    if (successfulWorkSources.isEmpty) {
      final lastError = sourceResults.values
          .map((result) => result.error)
          .whereType<Object>()
          .lastOrNull;
      throw WorksScrapeException(
        _hasExactMatch(sourceResults.values)
            ? 'Actress works could not be fetched: $name'
                  '${lastError == null ? '' : ' ($lastError)'}'
            : 'Exact actress was not found: $name',
      );
    }

    final fetched = pipelineResults
        .expand((pipeline) => pipeline.fetched)
        .toList(growable: false);
    final failedCandidates = pipelineResults
        .expand((pipeline) => pipeline.failedCandidates)
        .toList(growable: false);
    final resolvedGroups = _resolveAcrossSources(fetched, failedCandidates);
    if (_isCancelled(cancellationToken)) {
      return WorksScrapeResult(
        saved: 0,
        excluded: 0,
        failed: 0,
        cancelled: true,
        actressImageStatus: actressImageStatus,
        partialSuccess: true,
        sourceResults: Map.unmodifiable(sourceResults),
        detailsSource: _detailsSource,
        worksSources: _worksSources,
      );
    }

    _notify(
      onProgress,
      0,
      resolvedGroups.length,
      0,
      0,
      0,
      phase: WorksScrapePhase.resolvingWorks,
      totalKnown: true,
    );
    for (final group in resolvedGroups) {
      if (_isCancelled(cancellationToken)) {
        break;
      }
      _notify(
        onProgress,
        0,
        resolvedGroups.length,
        0,
        0,
        0,
        phase: WorksScrapePhase.resolvingWorks,
        source: group.sourceId,
        totalKnown: true,
        updateSourceProgress: false,
      );
    }
    final outcomes = <String, _CanonicalWorkOutcome>{};

    void recordOutcome({
      required String identityKey,
      required String code,
      required _CanonicalWorkStatus status,
      WorksScrapeFailure? failure,
      Set<WorkImageVariant> imageFailures = const <WorkImageVariant>{},
      String? reason,
      bool review = false,
      Map<String, Object?> metadata = const <String, Object?>{},
    }) {
      final existing = outcomes[identityKey];
      if (existing == null) {
        outcomes[identityKey] = _CanonicalWorkOutcome(
          code: code,
          status: status,
          failure: failure,
          imageFailures: imageFailures,
          reason: reason,
          review: review,
          metadata: metadata,
        );
        return;
      }
      existing.imageFailures.addAll(imageFailures);
      if (status == _CanonicalWorkStatus.saved ||
          existing.status == _CanonicalWorkStatus.excluded) {
        existing.status = status;
        existing.failure = failure;
        existing.reason = reason;
        existing.review = review;
        existing.metadata = metadata;
      }
    }

    int savedCount() => outcomes.values
        .where((outcome) => outcome.status == _CanonicalWorkStatus.saved)
        .length;

    int reviewCount() => outcomes.values
        .where(
          (outcome) =>
              outcome.status == _CanonicalWorkStatus.saved && outcome.review,
        )
        .length;

    int excludedCount() => outcomes.values
        .where((outcome) => outcome.status == _CanonicalWorkStatus.excluded)
        .length;

    int failedCount() => outcomes.values
        .where((outcome) => outcome.status == _CanonicalWorkStatus.failed)
        .length;

    _notify(
      onProgress,
      0,
      resolvedGroups.length,
      savedCount(),
      excludedCount(),
      failedCount(),
      review: reviewCount(),
      phase: WorksScrapePhase.savingWorks,
      totalKnown: true,
    );
    final sourceTotals = <ScrapeSourceId, int>{};
    for (final resolved in resolvedGroups) {
      sourceTotals.update(
        resolved.sourceId,
        (total) => total + 1,
        ifAbsent: () => 1,
      );
    }
    int sourceTotalFor(ScrapeSourceId sourceId) {
      final existing = _sourceProgress[sourceId];
      if (existing != null && existing.hasKnownTotal) {
        return existing.total;
      }
      return sourceTotals[sourceId] ?? 0;
    }

    final sourceCurrents = <ScrapeSourceId, int>{};
    var savingCurrent = 0;
    for (final resolved in resolvedGroups) {
      if (_isCancelled(cancellationToken)) {
        break;
      }
      final currentForSource = sourceCurrents[resolved.sourceId] ?? 0;
      final totalForSource = sourceTotalFor(resolved.sourceId);
      _notify(
        onProgress,
        savingCurrent,
        resolvedGroups.length,
        savedCount(),
        excludedCount(),
        failedCount(),
        review: reviewCount(),
        phase: WorksScrapePhase.savingWorks,
        source: resolved.sourceId,
        totalKnown: true,
        sourceCurrent: currentForSource,
        sourceTotal: totalForSource,
        sourceTotalKnown: true,
      );
      final code = scrapeWorkStorageCode(resolved.code);
      if (code == null) {
        final failureCode = resolved.code.isEmpty ? '未知番號：來源候選' : resolved.code;
        recordOutcome(
          identityKey: resolved.identityKey,
          code: failureCode,
          status: _CanonicalWorkStatus.failed,
          failure: WorksScrapeFailure(
            code: failureCode,
            stage: WorksScrapeFailureStage.resolvingWorks,
            reason: WorksScrapeFailureReason.invalidCode,
            source: resolved.sourceId,
          ),
        );
      } else if (resolved.details.isEmpty) {
        recordOutcome(
          identityKey: resolved.identityKey,
          code: code,
          status: _CanonicalWorkStatus.failed,
          failure: WorksScrapeFailure(
            code: code,
            stage: WorksScrapeFailureStage.fetchingDetails,
            reason:
                resolved.failureReason ??
                WorksScrapeFailureReason.detailsUnavailable,
            source: resolved.sourceId,
            error: resolved.failureError,
          ),
        );
      } else {
        final selectedDetails = resolved.details.first;
        final decision = policyEvaluator.evaluate(
          code: code,
          details: resolved.details,
        );
        final decisionMetadata = <String, Object?>{
          'canonicalCode': code,
          'finalVerdict': decision.verdict.name,
          'provenanceClass': decision.provenanceClass.name,
          'evidenceLevel': decision.evidenceLevel.name,
          'reasonCodes': decision.reasonCodes,
          'evidenceRuleIds': decision.evidence
              .map((item) => item.ruleId)
              .toSet()
              .toList(),
          'evidenceSources': resolved.details
              .map((item) => item.source.storageValue)
              .toSet()
              .toList(),
          'primarySource': selectedDetails.source.storageValue,
          'secondaryEscalated': resolved.details.length > 1,
          if (resolved.details.length > 1)
            'escalationReason': 'primary_uncertain',
        };
        if (decision.finalAction == ScrapeFinalAction.exclude) {
          recordOutcome(
            identityKey: resolved.identityKey,
            code: code,
            status: _CanonicalWorkStatus.excluded,
            reason: decision.reason,
            metadata: decisionMetadata,
          );
        } else {
          try {
            final savedWork = await _saveWork(
              actressId: actressId,
              details: selectedDetails,
              missingOnly: options.fillMissingOnly,
              cancellationToken: cancellationToken,
              onImageDownload: (imageCode, _) {
                _notify(
                  onProgress,
                  savingCurrent,
                  resolvedGroups.length,
                  savedCount(),
                  excludedCount(),
                  failedCount(),
                  review: reviewCount(),
                  phase: WorksScrapePhase.downloadingImages,
                  source: resolved.sourceId,
                  workCode: imageCode,
                  totalKnown: true,
                  updateSourceProgress: false,
                );
              },
            );
            recordOutcome(
              identityKey: resolved.identityKey,
              code: code,
              status: _CanonicalWorkStatus.saved,
              imageFailures: savedWork.failedVariants,
              reason: decision.reason,
              review: decision.reviewRequired,
              metadata: decisionMetadata,
            );
          } on _ScrapeCancelled {
            break;
          } catch (_) {
            recordOutcome(
              identityKey: resolved.identityKey,
              code: code,
              status: _CanonicalWorkStatus.failed,
              failure: WorksScrapeFailure(
                code: code,
                stage: WorksScrapeFailureStage.savingWorks,
                reason: WorksScrapeFailureReason.databaseSaveFailed,
                source: resolved.sourceId,
              ),
            );
          }
        }
      }
      final nextSourceCurrent = currentForSource + 1;
      sourceCurrents[resolved.sourceId] = nextSourceCurrent;
      savingCurrent++;
      final recordedOutcome = outcomes[resolved.identityKey];
      if (recordedOutcome != null) {
        _notifyWorkOutcome(
          code: recordedOutcome.code,
          source: resolved.sourceId,
          status: recordedOutcome.status,
          failure: recordedOutcome.failure,
          reason: recordedOutcome.reason,
          imageFailures: recordedOutcome.imageFailures,
          review: recordedOutcome.review,
          metadata: recordedOutcome.metadata,
        );
      }
      _notify(
        onProgress,
        savingCurrent,
        resolvedGroups.length,
        savedCount(),
        excludedCount(),
        failedCount(),
        review: reviewCount(),
        phase: WorksScrapePhase.savingWorks,
        source: resolved.sourceId,
        totalKnown: true,
        sourceCurrent: nextSourceCurrent,
        sourceTotal: totalForSource,
        sourceTotalKnown: true,
      );
    }

    final saved = savedCount();
    final review = reviewCount();
    final excluded = excludedCount();
    final failed = failedCount();
    final failedWorks = outcomes.values
        .where((outcome) => outcome.status == _CanonicalWorkStatus.failed)
        .map((outcome) => outcome.failure)
        .whereType<WorksScrapeFailure>()
        .toList(growable: false);
    final imageFailures = outcomes.values
        .where((outcome) => outcome.imageFailures.isNotEmpty)
        .map(
          (outcome) => WorksScrapeImageFailure(
            code: outcome.code,
            variants: List.unmodifiable(outcome.imageFailures),
          ),
        )
        .toList(growable: false);
    final cancelled = _isCancelled(cancellationToken);
    final partial =
        sourceResults.values.any(
          (result) =>
              result.state == ScrapeSourceRunState.failed ||
              result.state == ScrapeSourceRunState.unavailable ||
              result.state == ScrapeSourceRunState.cancelled,
        ) ||
        failed > 0 ||
        imageFailures.isNotEmpty ||
        resolvedGroups.any((group) => group.hadSourceFailure);
    if (!cancelled) {
      _notify(
        onProgress,
        savingCurrent,
        resolvedGroups.length,
        saved,
        excluded,
        failed,
        review: review,
        phase: WorksScrapePhase.completed,
        totalKnown: true,
      );
    }
    return WorksScrapeResult(
      saved: saved,
      excluded: excluded,
      failed: failed,
      cancelled: cancelled,
      review: review,
      actressImageStatus: actressImageStatus,
      partialSuccess: partial,
      sourceResults: Map.unmodifiable(sourceResults),
      failedWorks: List.unmodifiable(failedWorks),
      imageFailures: List.unmodifiable(imageFailures),
      detailsSource: _detailsSource,
      worksSources: _worksSources,
    );
  }

  List<String> _queries(String name, List<String> aliases) {
    final queries = <String>[name];
    final seen = <String>{name.toLowerCase()};
    for (final alias in aliases) {
      final normalized = alias.trim();
      if (normalized.isNotEmpty && seen.add(normalized.toLowerCase())) {
        queries.add(normalized);
      }
    }
    return queries;
  }

  Future<_CollectedSource> _collectSource({
    required ScrapeSource source,
    required List<String> queries,
    required WorksScrapeCancellationToken? cancellationToken,
    required bool includeWorks,
    void Function(ScrapeCollectionProgress progress)? onCollectionProgress,
  }) async {
    final diagnostics = source is ScrapeSourceDiagnosticsProvider
        ? source as ScrapeSourceDiagnosticsProvider
        : null;
    diagnostics?.resetRunDiagnostic();
    final pages = <String, ScrapeActressPage>{};
    final matches = <String, ScrapeActressSearchResult>{};
    final completedUris = <String>{};
    final summaries = <ScrapeWorkSummary>[];
    Object? lastError;
    Object? lastSearchError;
    var matched = false;
    var traversed = false;
    for (final query in queries) {
      if (_isCancelled(cancellationToken)) {
        break;
      }
      List<ScrapeActressSearchResult> results;
      try {
        results = await source.searchActresses(query);
      } catch (error) {
        // A single name/alias search can legitimately fail while a later
        // alias still finds the exact actress. Do not turn that superseded
        // query failure into a partial source result.
        lastSearchError = error;
        continue;
      }
      if (_isCancelled(cancellationToken)) {
        break;
      }
      final queryKey = query.trim().toLowerCase();
      for (final actress in results.where(
        (result) => result.name.trim().toLowerCase() == queryKey,
      )) {
        if (_isCancelled(cancellationToken)) {
          break;
        }
        matched = true;
        final uriKey = actress.uri.toString();
        if (completedUris.contains(uriKey)) {
          continue;
        }
        matches[uriKey] = actress;
        try {
          final page = await source.fetchActressPage(actress);
          if (_isCancelled(cancellationToken)) {
            break;
          }
          pages[uriKey] = page;
          if (!includeWorks) {
            traversed = true;
            completedUris.add(uriKey);
            continue;
          }
          try {
            final sourceWorks = await source.fetchActressWorks(
              actress,
              firstPage: page,
              isCancelled: () => _isCancelled(cancellationToken),
              onProgress: onCollectionProgress,
            );
            if (_isCancelled(cancellationToken)) {
              break;
            }
            summaries.addAll(sourceWorks);
            traversed = true;
            completedUris.add(uriKey);
          } catch (error) {
            lastError = error;
          }
        } catch (error) {
          lastError = error;
        }
      }
    }
    if (!matched && lastError == null) {
      lastError = lastSearchError;
    }
    final sourceDiagnostic = diagnostics?.lastRunDiagnostic;
    final state = _isCancelled(cancellationToken)
        ? ScrapeSourceRunState.cancelled
        : sourceDiagnostic?.state ??
              (traversed
                  ? (summaries.isEmpty
                        ? ScrapeSourceRunState.zeroResults
                        : lastError == null
                        ? ScrapeSourceRunState.success
                        : ScrapeSourceRunState.partial)
                  : matched
                  ? _sourceStateForError(lastError)
                  : ScrapeSourceRunState.unavailable);
    return _CollectedSource(
      source: source,
      pages: pages,
      summaries: summaries,
      result: ScrapeSourceRunResult(
        source: source.id,
        state: state,
        discovered: summaries.length,
        error: sourceDiagnostic?.error ?? lastError,
      ),
    );
  }

  Future<_SourceCollectionOutcome> _collectSourceSafely({
    required ScrapeSource source,
    required List<String> queries,
    required WorksScrapeCancellationToken? cancellationToken,
    required bool includeWorks,
    void Function(ScrapeCollectionProgress progress)? onCollectionProgress,
  }) async {
    try {
      final collected = await _collectSource(
        source: source,
        queries: queries,
        cancellationToken: cancellationToken,
        includeWorks: includeWorks,
        onCollectionProgress: onCollectionProgress,
      );
      return _SourceCollectionOutcome(
        collected: collected,
        result: collected.result,
      );
    } catch (error) {
      return _SourceCollectionOutcome(
        result: ScrapeSourceRunResult(
          source: source.id,
          state: _isCancelled(cancellationToken)
              ? ScrapeSourceRunState.cancelled
              : _sourceStateForError(error),
          error: error,
        ),
      );
    }
  }

  ScrapeSourceRunState _sourceStateForError(Object? error) {
    if (error is JavBusVerificationRequiredException) {
      return ScrapeSourceRunState.verificationRequired;
    }
    if (error is JavBusVerificationCancelledException) {
      return ScrapeSourceRunState.cancelled;
    }
    if (error is JavBusRequestException) {
      return switch (error.kind) {
        JavBusFailureKind.verificationRequired =>
          ScrapeSourceRunState.verificationRequired,
        JavBusFailureKind.blocked => ScrapeSourceRunState.blocked,
        JavBusFailureKind.rateLimited => ScrapeSourceRunState.rateLimited,
        JavBusFailureKind.timeout => ScrapeSourceRunState.timedOut,
        JavBusFailureKind.cancelled => ScrapeSourceRunState.cancelled,
        JavBusFailureKind.notFound ||
        JavBusFailureKind.parserInvalid ||
        JavBusFailureKind.transport ||
        JavBusFailureKind.transientTransport => ScrapeSourceRunState.failed,
      };
    }
    if (error is AvBaseRequestException) {
      return switch (error.kind) {
        AvBaseFailureKind.blocked => ScrapeSourceRunState.blocked,
        AvBaseFailureKind.rateLimited => ScrapeSourceRunState.rateLimited,
        AvBaseFailureKind.timeout => ScrapeSourceRunState.timedOut,
        AvBaseFailureKind.cancelled => ScrapeSourceRunState.cancelled,
        AvBaseFailureKind.notFound ||
        AvBaseFailureKind.parserInvalid ||
        AvBaseFailureKind.transport ||
        AvBaseFailureKind.transientTransport => ScrapeSourceRunState.failed,
      };
    }
    return ScrapeSourceRunState.failed;
  }

  _GlobalCandidateSelection _selectGlobalWorkCandidates({
    required List<ScrapeSourceId> requestedWorkIds,
    required Map<ScrapeSourceId, _CollectedSource> collectedById,
    required List<String> retryWorkCodes,
  }) {
    final grouped = <String, List<_WorkCandidate>>{};
    var rawDiscovered = 0;
    for (final sourceId in requestedWorkIds) {
      final collected = collectedById[sourceId];
      if (collected == null || !collected.result.succeeded) continue;
      for (final summary in collected.summaries) {
        rawDiscovered++;
        final rawCode = summary.rawCode ?? summary.code;
        final identity = parseScrapeWorkCodeIdentity(rawCode);
        final key = identity == null
            ? 'uri:${sourceId.storageValue}:${summary.detailUri}'
            : 'code:${identity.key}';
        final candidates = grouped.putIfAbsent(key, () => <_WorkCandidate>[]);
        if (candidates.every(
          (candidate) =>
              candidate.source.id != sourceId ||
              candidate.summary.detailUri != summary.detailUri,
        )) {
          candidates.add(
            _WorkCandidate(source: collected.source, summary: summary),
          );
        }
      }
    }

    final retryKeys = retryWorkCodes
        .map(scrapeWorkCodeIdentityKey)
        .whereType<String>()
        .toSet();
    final groups = <_GlobalWorkGroup>[];
    var ordinal = 0;
    for (final entry in grouped.entries) {
      final allCandidates = entry.value;
      final ordinary = allCandidates
          .where(
            (candidate) => !scrapeWorkCodeIsSpecialEdition(
              candidate.summary.rawCode ?? candidate.summary.code,
            ),
          )
          .toList(growable: false);
      final retained = ordinary.isEmpty ? allCandidates : ordinary;
      retained.sort((left, right) {
        final sourceComparison = requestedWorkIds
            .indexOf(left.source.id)
            .compareTo(requestedWorkIds.indexOf(right.source.id));
        if (sourceComparison != 0) return sourceComparison;
        return left.summary.detailUri.toString().compareTo(
          right.summary.detailUri.toString(),
        );
      });
      final first = retained.first;
      final rawCode = first.summary.rawCode ?? first.summary.code;
      final storageCode = scrapeWorkStorageCode(rawCode) ?? '';
      final identityKey = scrapeWorkCodeIdentityKey(rawCode);
      if (retryKeys.isNotEmpty &&
          (identityKey == null || !retryKeys.contains(identityKey))) {
        continue;
      }
      if (storageCode.isNotEmpty) {
        _observer?.onWorkDiscovered(
          canonicalCode: storageCode,
          rawCode: rawCode,
          source: first.source.id,
        );
      }
      groups.add(
        _GlobalWorkGroup(
          identityKey: entry.key,
          identityCodeKey: identityKey,
          storageCode: storageCode,
          candidates: List.unmodifiable(retained),
          ordinal: ordinal++,
        ),
      );
    }
    groups.sort((left, right) {
      final sourceComparison = requestedWorkIds
          .indexOf(left.candidates.first.source.id)
          .compareTo(
            requestedWorkIds.indexOf(right.candidates.first.source.id),
          );
      if (sourceComparison != 0) return sourceComparison;
      return left.ordinal.compareTo(right.ordinal);
    });
    final uniqueCount = groups.length;
    return _GlobalCandidateSelection(
      groups: List.unmodifiable(groups),
      rawDiscovered: rawDiscovered,
      uniqueCount: uniqueCount,
      duplicateCount: rawDiscovered > uniqueCount
          ? rawDiscovered - uniqueCount
          : 0,
    );
  }

  Future<List<_SourcePipelineOutcome>> _runConditionalWorkPipelines({
    required List<ScrapeSourceId> requestedWorkIds,
    required Map<ScrapeSourceId, _CollectedSource> collectedById,
    required List<String> retryWorkCodes,
    required ScrapeExclusionPolicyEvaluator policyEvaluator,
    required Future<_SourceCollectionOutcome> Function(ScrapeSourceId)
    ensureCollection,
    required WorksScrapeCancellationToken? cancellationToken,
    void Function(WorksScrapeProgress progress)? onProgress,
  }) async {
    if (requestedWorkIds.isEmpty) return const [];

    final attemptedSourceIds = <ScrapeSourceId>[];
    final resultsBySource = <ScrapeSourceId, ScrapeSourceRunResult>{};
    _GlobalCandidateSelection? selection;

    // First obtain coverage from the primary source.  If it cannot produce
    // any usable candidate, move to the next source one at a time.
    for (final sourceId in requestedWorkIds) {
      if (_isCancelled(cancellationToken)) break;
      final outcome = await ensureCollection(sourceId);
      attemptedSourceIds.add(sourceId);
      resultsBySource[sourceId] = outcome.result;
      final collected = outcome.collected;
      if (collected != null) collectedById[sourceId] = collected;
      if (!outcome.result.succeeded) continue;

      final candidateSelection = _selectGlobalWorkCandidates(
        requestedWorkIds: requestedWorkIds,
        collectedById: collectedById,
        retryWorkCodes: retryWorkCodes,
      );
      if (candidateSelection.groups.isNotEmpty) {
        selection = candidateSelection;
        break;
      }
    }

    if (selection == null) {
      return [
        for (final sourceId in attemptedSourceIds)
          _SourcePipelineOutcome(
            sourceId: sourceId,
            collected: collectedById[sourceId],
            result:
                resultsBySource[sourceId] ??
                ScrapeSourceRunResult(
                  source: sourceId,
                  state: ScrapeSourceRunState.unavailable,
                ),
          ),
      ];
    }

    final selected = selection;
    _rawDiscovered = selected.rawDiscovered;
    _duplicateCount = selected.duplicateCount;
    _detailTotal = selected.groups.length;
    _uniqueTotal = selected.uniqueCount;

    final fetched = <_FetchedWorkDetail>[];
    final failedCandidates = <_FailedWorkCandidate>[];
    final pipelineResults = <_SourcePipelineOutcome>[];
    var unresolved = selected.groups.toList(growable: false);

    bool needsSecondaryEvidence(
      _GlobalWorkGroup group,
      List<ScrapeWorkDetails> groupDetails,
    ) {
      if (groupDetails.isEmpty) return true;
      final decision = policyEvaluator.evaluate(
        code: group.storageCode,
        details: groupDetails,
      );
      if (!decision.reviewRequired) return false;
      // A disabled automatic filter is an intentional user choice, not a
      // missing fact that should trigger another site's request.
      if (decision.reasonCodes.contains('derived_work_filter_disabled') ||
          decision.reasonCodes.contains('manual_rule_scope_uncertain') ||
          decision.reasonCodes.contains('manual_override_conflict')) {
        return false;
      }
      return true;
    }

    final selectedSourceIndex = requestedWorkIds.indexOf(
      unresolved.first.candidates.first.source.id,
    );
    final firstStageIndex = selectedSourceIndex < 0 ? 0 : selectedSourceIndex;
    for (
      var sourceIndex = firstStageIndex;
      sourceIndex < requestedWorkIds.length && unresolved.isNotEmpty;
      sourceIndex++
    ) {
      if (_isCancelled(cancellationToken)) break;
      final sourceId = requestedWorkIds[sourceIndex];
      var stageGroups = unresolved;

      if (sourceIndex > firstStageIndex) {
        final source = sources[sourceId];
        final directLookup = source is ScrapeSourceWorkCodeLookup
            ? source as ScrapeSourceWorkCodeLookup
            : null;
        if (source != null && directLookup != null) {
          _supplementalEvidenceTotal += unresolved.length;
          final directStage = await _runDirectSecondaryEvidence(
            source: source,
            lookup: directLookup,
            groups: unresolved,
            cancellationToken: cancellationToken,
            onProgress: onProgress,
          );
          pipelineResults.add(directStage);
          fetched.addAll(directStage.fetched);
          failedCandidates.addAll(directStage.failedCandidates);
          final nextUnresolved = <_GlobalWorkGroup>[];
          for (final group in unresolved) {
            final groupDetails = fetched
                .where((item) => item.identityKey == group.identityKey)
                .map((item) => item.details)
                .toList(growable: false);
            if (needsSecondaryEvidence(group, groupDetails)) {
              nextUnresolved.add(group);
            }
          }
          unresolved = nextUnresolved;
          continue;
        }
        final outcome = await ensureCollection(sourceId);
        if (!attemptedSourceIds.contains(sourceId)) {
          attemptedSourceIds.add(sourceId);
        }
        resultsBySource[sourceId] = outcome.result;
        final collected = outcome.collected;
        if (collected != null) collectedById[sourceId] = collected;
        if (!outcome.result.succeeded || collected == null) continue;

        final candidatesByIdentity = <String, List<_WorkCandidate>>{};
        for (final summary in collected.summaries) {
          final key = _summaryIdentityKey(sourceId, summary);
          candidatesByIdentity
              .putIfAbsent(key, () => <_WorkCandidate>[])
              .add(_WorkCandidate(source: collected.source, summary: summary));
        }
        final stagedGroups = <_GlobalWorkGroup>[];
        for (final group in unresolved) {
          final candidates = candidatesByIdentity[group.identityKey];
          if (candidates == null || candidates.isEmpty) continue;
          stagedGroups.add(
            _GlobalWorkGroup(
              identityKey: group.identityKey,
              identityCodeKey: group.identityCodeKey,
              storageCode: group.storageCode,
              candidates: List.unmodifiable(candidates),
              ordinal: group.ordinal,
            ),
          );
        }
        if (stagedGroups.isEmpty) continue;
        stageGroups = stagedGroups;
      }

      if (sourceIndex > firstStageIndex) {
        _supplementalEvidenceTotal += stageGroups.length;
      }

      final stageResult = await _runGlobalDetailPipelines(
        requestedWorkIds: [sourceId],
        collectedById: {
          if (collectedById[sourceId] != null)
            sourceId: collectedById[sourceId]!,
        },
        groups: stageGroups,
        cancellationToken: cancellationToken,
        supplementalEvidence: sourceIndex > firstStageIndex,
        onProgress: onProgress,
      );
      pipelineResults.addAll(stageResult);
      for (final pipeline in stageResult) {
        fetched.addAll(pipeline.fetched);
        failedCandidates.addAll(pipeline.failedCandidates);
      }

      final nextUnresolved = <_GlobalWorkGroup>[];
      for (final group in unresolved) {
        final groupDetails = fetched
            .where((item) => item.identityKey == group.identityKey)
            .map((item) => item.details)
            .toList(growable: false);
        if (needsSecondaryEvidence(group, groupDetails)) {
          nextUnresolved.add(group);
        }
      }
      unresolved = nextUnresolved;
    }

    // A source may have been used for coverage but not for detail fetching
    // (for example when cancellation arrived between stages). Keep its
    // collection result visible without inventing a failure.
    final known = pipelineResults.map((item) => item.sourceId).toSet();
    for (final sourceId in attemptedSourceIds) {
      if (known.contains(sourceId)) continue;
      pipelineResults.add(
        _SourcePipelineOutcome(
          sourceId: sourceId,
          collected: collectedById[sourceId],
          result:
              resultsBySource[sourceId] ??
              ScrapeSourceRunResult(
                source: sourceId,
                state: ScrapeSourceRunState.unavailable,
              ),
        ),
      );
    }
    return List.unmodifiable(pipelineResults);
  }

  Future<_SourcePipelineOutcome> _runDirectSecondaryEvidence({
    required ScrapeSource source,
    required ScrapeSourceWorkCodeLookup lookup,
    required List<_GlobalWorkGroup> groups,
    required WorksScrapeCancellationToken? cancellationToken,
    void Function(WorksScrapeProgress progress)? onProgress,
  }) async {
    final scheduler = _SourceDetailScheduler(
      delay:
          source.id == ScrapeSourceId.javbus ||
              source.id == ScrapeSourceId.avbase
          ? javBusDetailDelay
          : Duration.zero,
    );
    final fetched = <_FetchedWorkDetail>[];
    final sourceCurrent = <ScrapeSourceId, int>{};

    Future<void> lookupGroup(_GlobalWorkGroup group) async {
      if (_isCancelled(cancellationToken)) return;
      final primaryCandidate = group.candidates.first;
      final code = group.storageCode.isEmpty
          ? (primaryCandidate.summary.code ?? '').trim()
          : group.storageCode;
      if (code.isEmpty) return;
      _observer?.onWorkAttemptStarted(code: code, source: source.id);
      try {
        final details = await scheduler.add(
          () => lookup.fetchWorkDetailsByCode(code),
        );
        if (details == null) return;
        final detailIdentity = parseScrapeWorkCodeIdentity(details.code);
        if (detailIdentity == null ||
            (group.identityCodeKey != null &&
                detailIdentity.key != group.identityCodeKey)) {
          _observer?.onError(
            stage: WorksScrapePhase.fetchingDetails.name,
            code: code,
            error: 'Supplemental detail code does not match the selected work.',
          );
          return;
        }
        final summary = ScrapeWorkSummary(
          source: source.id,
          code: code,
          rawCode: code,
          title: primaryCandidate.summary.title,
          detailUri: Uri(path: '/works/$code'),
          releaseDate: primaryCandidate.summary.releaseDate,
        );
        final evidenced = details.copyWith(sourceUri: summary.detailUri);
        fetched.add(
          _FetchedWorkDetail(
            candidate: _WorkCandidate(source: source, summary: summary),
            identityKey: group.identityKey,
            sourceId: source.id,
            details: _withScrapeCode(
              evidenced,
              group.storageCode.isEmpty ? code : group.storageCode,
              fallbackTitle: primaryCandidate.summary.title,
              fallbackReleaseDate: primaryCandidate.summary.releaseDate,
            ),
          ),
        );
        _observer?.onWorkCompleted(
          code: group.storageCode.isEmpty ? code : group.storageCode,
          source: source.id,
          state: 'details_ready',
        );
      } on Object catch (error) {
        _observer?.onError(
          stage: WorksScrapePhase.fetchingDetails.name,
          code: code,
          error: error,
        );
      } finally {
        if (!_isCancelled(cancellationToken)) {
          _supplementalEvidenceCompleted++;
          final current = sourceCurrent.update(
            source.id,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
          _notify(
            onProgress,
            _detailCompleted,
            _detailTotal,
            0,
            0,
            0,
            phase: WorksScrapePhase.fetchingDetails,
            source: source.id,
            workCode: code,
            totalKnown: true,
            sourceCurrent: current,
            sourceTotal: groups.length,
            sourceTotalKnown: true,
          );
        }
      }
    }

    await Future.wait(groups.map(lookupGroup));
    return _SourcePipelineOutcome(
      sourceId: source.id,
      result: ScrapeSourceRunResult(
        source: source.id,
        state: ScrapeSourceRunState.success,
        discovered: groups.length,
      ),
      fetched: List.unmodifiable(fetched),
    );
  }

  String _summaryIdentityKey(
    ScrapeSourceId sourceId,
    ScrapeWorkSummary summary,
  ) {
    final identity = parseScrapeWorkCodeIdentity(
      summary.rawCode ?? summary.code,
    );
    return identity == null
        ? 'uri:${sourceId.storageValue}:${summary.detailUri}'
        : 'code:${identity.key}';
  }

  Future<List<_SourcePipelineOutcome>> _runGlobalDetailPipelines({
    required List<ScrapeSourceId> requestedWorkIds,
    required Map<ScrapeSourceId, _CollectedSource> collectedById,
    required List<_GlobalWorkGroup> groups,
    required WorksScrapeCancellationToken? cancellationToken,
    bool supplementalEvidence = false,
    void Function(WorksScrapeProgress progress)? onProgress,
  }) async {
    final schedulers = <ScrapeSourceId, _SourceDetailScheduler>{
      for (final sourceId in requestedWorkIds)
        sourceId: _SourceDetailScheduler(
          delay:
              sourceId == ScrapeSourceId.javbus ||
                  sourceId == ScrapeSourceId.avbase
              ? javBusDetailDelay
              : Duration.zero,
        ),
    };
    final fetchedBySource = <ScrapeSourceId, List<_FetchedWorkDetail>>{};
    final failedBySource = <ScrapeSourceId, List<_FailedWorkCandidate>>{};
    final sourceCompleted = <ScrapeSourceId, int>{};
    final sourceTotals = <ScrapeSourceId, int>{};
    for (final group in groups) {
      final sourceId = group.candidates.first.source.id;
      sourceTotals.update(sourceId, (value) => value + 1, ifAbsent: () => 1);
    }
    _notify(
      onProgress,
      0,
      _detailTotal > 0 ? _detailTotal : groups.length,
      0,
      0,
      0,
      phase: WorksScrapePhase.fetchingDetails,
      totalKnown: true,
    );

    Future<void> fetchGroup(_GlobalWorkGroup group) async {
      _FailedWorkCandidate? lastFailure;
      _FetchedWorkDetail? fetched;
      for (final candidate in group.candidates) {
        if (_isCancelled(cancellationToken)) break;
        final sourceId = candidate.source.id;
        final attemptCode = group.storageCode.isEmpty
            ? candidate.summary.title
            : group.storageCode;
        _observer?.onWorkAttemptStarted(code: attemptCode, source: sourceId);
        try {
          final details = await schedulers[sourceId]!.add(
            () => candidate.source.fetchWorkDetails(candidate.summary),
          );
          final detailIdentity = parseScrapeWorkCodeIdentity(details.code);
          if (detailIdentity == null ||
              (group.identityCodeKey != null &&
                  detailIdentity.key != group.identityCodeKey)) {
            lastFailure = _FailedWorkCandidate(
              candidate: candidate,
              identityKey: group.identityKey,
              reason: WorksScrapeFailureReason.detailCodeMismatch,
            );
            failedBySource.putIfAbsent(sourceId, () => []).add(lastFailure);
            _observer?.onError(
              stage: WorksScrapePhase.fetchingDetails.name,
              code: attemptCode,
              error: 'Detail code does not match the selected work.',
            );
            continue;
          }
          final storageCode = group.storageCode.isNotEmpty
              ? group.storageCode
              : scrapeWorkStorageCode(details.rawCode ?? details.code) ?? '';
          if (storageCode.isEmpty) {
            lastFailure = _FailedWorkCandidate(
              candidate: candidate,
              identityKey: group.identityKey,
              reason: WorksScrapeFailureReason.invalidCode,
            );
            failedBySource.putIfAbsent(sourceId, () => []).add(lastFailure);
            _observer?.onError(
              stage: WorksScrapePhase.fetchingDetails.name,
              code: attemptCode,
              error: 'Detail page did not provide a valid work code.',
            );
            continue;
          }
          final evidenced = details.copyWith(
            sourceUri: candidate.summary.detailUri,
          );
          fetched = _FetchedWorkDetail(
            candidate: candidate,
            identityKey: group.identityKey,
            sourceId: sourceId,
            details: _withScrapeCode(
              evidenced,
              storageCode,
              fallbackTitle: candidate.summary.title,
              fallbackReleaseDate: candidate.summary.releaseDate,
            ),
          );
          _observer?.onWorkCompleted(
            code: storageCode,
            source: sourceId,
            state: 'details_ready',
          );
          break;
        } on Object catch (error) {
          lastFailure = _FailedWorkCandidate(
            candidate: candidate,
            identityKey: group.identityKey,
            reason: WorksScrapeFailureReason.detailsUnavailable,
            error: error,
          );
          failedBySource.putIfAbsent(sourceId, () => []).add(lastFailure);
          _observer?.onError(
            stage: WorksScrapePhase.fetchingDetails.name,
            code: attemptCode,
            error: error,
          );
        }
      }
      final outcomeSource =
          fetched?.sourceId ??
          lastFailure?.candidate.source.id ??
          group.candidates.first.source.id;
      if (fetched != null) {
        fetchedBySource.putIfAbsent(outcomeSource, () => []).add(fetched);
      }
      if (supplementalEvidence) {
        _supplementalEvidenceCompleted++;
      } else {
        _detailCompleted++;
      }
      final sourceCurrent = sourceCompleted.update(
        group.candidates.first.source.id,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      _notify(
        onProgress,
        _detailCompleted,
        _detailTotal > 0 ? _detailTotal : groups.length,
        0,
        0,
        0,
        phase: WorksScrapePhase.fetchingDetails,
        source: group.candidates.first.source.id,
        workCode: fetched?.details.code ?? group.storageCode,
        totalKnown: true,
        sourceCurrent: sourceCurrent,
        sourceTotal: sourceTotals[group.candidates.first.source.id] ?? 0,
        sourceTotalKnown: true,
      );
    }

    await Future.wait(groups.map(fetchGroup));
    return [
      for (var index = 0; index < requestedWorkIds.length; index++)
        _SourcePipelineOutcome(
          sourceId: requestedWorkIds[index],
          collected: collectedById[requestedWorkIds[index]],
          result:
              collectedById[requestedWorkIds[index]]?.result ??
              ScrapeSourceRunResult(
                source: requestedWorkIds[index],
                state: ScrapeSourceRunState.unavailable,
              ),
          fetched: List.unmodifiable(
            fetchedBySource[requestedWorkIds[index]] ?? const [],
          ),
          failedCandidates: List.unmodifiable(
            failedBySource[requestedWorkIds[index]] ?? const [],
          ),
        ),
    ];
  }

  List<_ResolvedWorkGroup> _resolveAcrossSources(
    List<_FetchedWorkDetail> fetched,
    List<_FailedWorkCandidate> failedCandidates,
  ) {
    final groups = <String, _ResolvedWorkGroup>{};

    int sourcePriority(ScrapeSourceId source) {
      final priority = _worksSources.indexOf(source);
      return priority < 0 ? _worksSources.length : priority;
    }

    String canonicalCode(String? rawCode) {
      return scrapeWorkStorageCode(rawCode)?.trim() ?? '';
    }

    int compareSourceAndCode(
      ScrapeSourceId leftSource,
      String leftCode,
      Uri leftUri,
      ScrapeSourceId rightSource,
      String rightCode,
      Uri rightUri,
    ) {
      final sourceComparison = sourcePriority(
        leftSource,
      ).compareTo(sourcePriority(rightSource));
      if (sourceComparison != 0) {
        return sourceComparison;
      }
      final codeComparison = leftCode.toLowerCase().compareTo(
        rightCode.toLowerCase(),
      );
      if (codeComparison != 0) {
        return codeComparison;
      }
      return leftUri.toString().compareTo(rightUri.toString());
    }

    final sortedFetched = [...fetched]
      ..sort(
        (left, right) => compareSourceAndCode(
          left.sourceId,
          canonicalCode(left.details.code),
          left.candidate.summary.detailUri,
          right.sourceId,
          canonicalCode(right.details.code),
          right.candidate.summary.detailUri,
        ),
      );
    for (final detail in sortedFetched) {
      final code = canonicalCode(detail.details.code);
      final sourceUri = detail.candidate.summary.detailUri.toString();
      final codeKey = scrapeWorkCodeIdentityKey(detail.details.code);
      final identityKey = codeKey == null
          ? 'resolved:${detail.sourceId.storageValue}:$sourceUri'
          : 'resolved:$codeKey';
      final group = groups.putIfAbsent(
        identityKey,
        () => _ResolvedWorkGroup(
          code: code,
          details: <ScrapeWorkDetails>[],
          identityKey: identityKey,
          hadSourceFailure: false,
          sourceId: detail.sourceId,
        ),
      );
      group.details.add(detail.details);
      if (sourcePriority(detail.sourceId) < sourcePriority(group.sourceId)) {
        group.sourceId = detail.sourceId;
      }
    }

    final sortedFailures = [...failedCandidates]
      ..sort(
        (left, right) => compareSourceAndCode(
          left.candidate.source.id,
          canonicalCode(left.candidate.summary.code),
          left.candidate.summary.detailUri,
          right.candidate.source.id,
          canonicalCode(right.candidate.summary.code),
          right.candidate.summary.detailUri,
        ),
      );
    for (final failed in sortedFailures) {
      final rawCode = failed.candidate.summary.code?.trim() ?? '';
      final code = canonicalCode(rawCode);
      final codeKey = scrapeWorkCodeIdentityKey(rawCode);
      final identityKey = codeKey == null
          ? 'failed:${failed.candidate.source.id.storageValue}:${failed.candidate.summary.detailUri}'
          : 'resolved:$codeKey';
      final group = groups.putIfAbsent(
        identityKey,
        () => _ResolvedWorkGroup(
          code: code,
          details: <ScrapeWorkDetails>[],
          identityKey: identityKey,
          hadSourceFailure: true,
          sourceId: failed.candidate.source.id,
          failureReason: failed.reason,
          failureError: failed.error,
        ),
      );
      group.hadSourceFailure = true;
      if (group.details.isEmpty &&
          sourcePriority(failed.candidate.source.id) <
              sourcePriority(group.sourceId)) {
        group.sourceId = failed.candidate.source.id;
        group.failureReason = failed.reason;
        group.failureError = failed.error;
      } else if (group.failureReason == null) {
        group.failureReason = failed.reason;
        group.failureError = failed.error;
      }
    }

    for (final group in groups.values) {
      group.details.sort((left, right) {
        final leftSpecial = scrapeWorkCodeIsSpecialEdition(
          left.rawCode ?? left.code,
        );
        final rightSpecial = scrapeWorkCodeIsSpecialEdition(
          right.rawCode ?? right.code,
        );
        if (leftSpecial != rightSpecial) {
          return leftSpecial ? 1 : -1;
        }
        final sourceComparison = sourcePriority(
          left.source,
        ).compareTo(sourcePriority(right.source));
        if (sourceComparison != 0) {
          return sourceComparison;
        }
        return (left.rawCode ?? left.code).compareTo(
          right.rawCode ?? right.code,
        );
      });
    }
    final resolved = groups.values.toList()
      ..sort((left, right) {
        final sourceComparison = sourcePriority(
          left.sourceId,
        ).compareTo(sourcePriority(right.sourceId));
        if (sourceComparison != 0) {
          return sourceComparison;
        }
        return left.identityKey.compareTo(right.identityKey);
      });
    return List.unmodifiable(resolved);
  }

  ScrapedActressDetails _mergeActressPages(
    List<ScrapeActressPage> pages, {
    required ScrapeSource source,
  }) {
    String? firstValue(String? Function(ScrapedActressDetails) select) {
      for (final page in pages) {
        final value = select(page.details)?.trim();
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
      return null;
    }

    Uri? avatarUrl;
    for (final page in pages) {
      final candidate = page.details.avatarUrl;
      if (candidate != null && source.acceptsImageUri(candidate)) {
        avatarUrl = candidate;
        break;
      }
    }
    return ScrapedActressDetails(
      name: firstValue((details) => details.name),
      avatarUrl: avatarUrl,
      birthDate: firstValue((details) => details.birthDate),
      height: firstValue((details) => details.height),
      cup: firstValue((details) => details.cup),
      bust: firstValue((details) => details.bust),
      waist: firstValue((details) => details.waist),
      hip: firstValue((details) => details.hip),
    );
  }

  Future<void> _syncActressAliases({
    required int actressId,
    required List<ScrapeActressPage> pages,
  }) async {
    final existing = await db.getActressAliases(actressId);
    final scraped = pages.expand((page) => page.aliases);
    await db.replaceActressAliases(
      actressId: actressId,
      aliases: [...existing, ...scraped],
    );
  }

  Future<ActressImageSyncStatus> _syncActress({
    required int actressId,
    required ScrapedActressDetails details,
    required ScrapeSource source,
    required WorkScrapeOptions options,
    required WorksScrapeCancellationToken? cancellationToken,
  }) async {
    return db.runManagedImageLifecycle(
      () => _syncActressUnlocked(
        actressId: actressId,
        details: details,
        source: source,
        options: options,
        cancellationToken: cancellationToken,
      ),
    );
  }

  Future<ActressImageSyncStatus> _syncActressUnlocked({
    required int actressId,
    required ScrapedActressDetails details,
    required ScrapeSource source,
    required WorkScrapeOptions options,
    required WorksScrapeCancellationToken? cancellationToken,
  }) async {
    String? imagePath;
    String? previousImagePath;
    var imageStatus = options.replaceActressImage
        ? ActressImageSyncStatus.unavailable
        : ActressImageSyncStatus.notRequested;
    final avatar = details.avatarUrl;
    if (options.replaceActressImage &&
        avatar != null &&
        source.acceptsImageUri(avatar)) {
      try {
        if (_isCancelled(cancellationToken)) {
          return imageStatus;
        }
        previousImagePath = (await db.getActressById(
          actressId,
        ))?['img_path']?.toString();
        if (_isCancelled(cancellationToken)) {
          return imageStatus;
        }
        final version = DateTime.now().microsecondsSinceEpoch;
        imagePath = await actressImageDownloader.download(
          avatar,
          path.join(
            imageDirectory,
            'actresses',
            'actress_${actressId}_$version.jpg',
          ),
        );
        imageStatus = ActressImageSyncStatus.replaced;
      } catch (_) {
        imagePath = null;
        imageStatus = ActressImageSyncStatus.downloadFailed;
      }
    }

    if (_isCancelled(cancellationToken)) {
      if (imagePath != null) {
        await _deleteManagedActressImage(imagePath);
      }
      return imageStatus;
    }

    if (!options.syncDetails && imagePath == null) {
      return imageStatus;
    }

    final syncDetails = ScrapedActressDetails(
      // The local canonical name is authoritative; scraped alias pages must
      // never rename the actress record.
      name: null,
      imagePath: imagePath,
      birthDate: options.syncDetails ? details.birthDate : null,
      height: options.syncDetails ? details.height : null,
      cup: options.syncDetails ? details.cup : null,
      bust: options.syncDetails ? details.bust : null,
      waist: options.syncDetails ? details.waist : null,
      hip: options.syncDetails ? details.hip : null,
    );
    if (_isCancelled(cancellationToken)) {
      if (imagePath != null) {
        await _deleteManagedActressImage(imagePath);
      }
      return imageStatus;
    }
    final updated = await db.syncActressDetails(
      actressId: actressId,
      details: syncDetails,
      missingOnly: options.fillMissingOnly,
      replaceImage: options.replaceActressImage,
    );
    if (!updated && imagePath != null) {
      final file = File(imagePath);
      if (file.existsSync()) {
        await file.delete();
      }
      return ActressImageSyncStatus.databaseFailed;
    } else if (updated && imagePath != null) {
      await _deletePreviousManagedAvatar(previousImagePath, imagePath);
    }
    return imageStatus;
  }

  Future<void> _deleteManagedActressImage(String imagePath) async {
    final managedDirectory = path.normalize(
      path.absolute(path.join(imageDirectory, 'actresses')),
    );
    final image = path.normalize(path.absolute(imagePath));
    if (!path.isWithin(managedDirectory, image)) {
      return;
    }
    final file = File(image);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<void> _deletePreviousManagedAvatar(
    String? previousPath,
    String newPath,
  ) async {
    if (previousPath == null || previousPath.trim().isEmpty) {
      return;
    }
    final managedDirectory = path.normalize(
      path.absolute(path.join(imageDirectory, 'actresses')),
    );
    final previous = path.normalize(path.absolute(previousPath));
    final replacement = path.normalize(path.absolute(newPath));
    if (previous == replacement || !path.isWithin(managedDirectory, previous)) {
      return;
    }
    final file = File(previous);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<_WorkImageSaveResult> _saveWork({
    required int actressId,
    required ScrapeWorkDetails details,
    required bool missingOnly,
    WorksScrapeCancellationToken? cancellationToken,
    void Function(String code, WorkImageVariant variant)? onImageDownload,
  }) async {
    return _saveWorkUnlocked(
      actressId: actressId,
      details: details,
      missingOnly: missingOnly,
      cancellationToken: cancellationToken,
      onImageDownload: onImageDownload,
    );
  }

  Future<_WorkImageSaveResult> _saveWorkUnlocked({
    required int actressId,
    required ScrapeWorkDetails details,
    required bool missingOnly,
    WorksScrapeCancellationToken? cancellationToken,
    void Function(String code, WorkImageVariant variant)? onImageDownload,
  }) async {
    if (_isCancelled(cancellationToken)) {
      throw const _ScrapeCancelled();
    }
    final code = scrapeWorkStorageCode(details.code);
    if (code == null) {
      throw ArgumentError('Work code must not be empty.');
    }
    if (details.code != code) {
      details = _withScrapeCode(
        details,
        code,
        fallbackTitle: details.title,
        fallbackReleaseDate: details.releaseDate,
      );
    }
    final performerSource = details.source == ScrapeSourceId.javbus
        ? details.source.storageValue
        : null;
    final performers = performerSource == null ? null : details.performers;
    final prepared = await db.runManagedImageLifecycle(() async {
      final workId = await db.upsertActressWork(
        actressId: actressId,
        work: details.toWork(),
        missingOnly: missingOnly,
        performerSource: performerSource,
        performers: performers,
        provenance: details.provenanceFor(0),
      );
      final current = await db.getWorkById(workId);
      return _PreparedWorkImage(
        details: details,
        currentCard: current?['card_image_path']?.toString() ?? '',
        currentDetail: current?['detail_image_path']?.toString() ?? '',
      );
    });
    if (_isCancelled(cancellationToken)) {
      throw const _ScrapeCancelled();
    }
    final imageResults = await Future.wait<_WorkImageResult>([
      _downloadWorkImage(
        details: prepared.details,
        variant: WorkImageVariant.card,
        targetPath: path.join(
          imageDirectory,
          'works',
          workImageDownloader.fileNameFor(
            code: prepared.details.code,
            variant: WorkImageVariant.card,
          ),
        ),
        currentPath: prepared.currentCard,
        missingOnly: missingOnly,
        onImageDownload: onImageDownload,
      ),
      _downloadWorkImage(
        details: prepared.details,
        variant: WorkImageVariant.detail,
        targetPath: path.join(
          imageDirectory,
          'works',
          workImageDownloader.fileNameFor(
            code: prepared.details.code,
            variant: WorkImageVariant.detail,
          ),
        ),
        currentPath: prepared.currentDetail,
        missingOnly: missingOnly,
        onImageDownload: onImageDownload,
      ),
    ]);
    if (_isCancelled(cancellationToken)) {
      throw const _ScrapeCancelled();
    }
    final cardPath = imageResults[0];
    final detailPath = imageResults[1];
    final work = prepared.details.toWork(
      cardImagePath: cardPath.path,
      detailImagePath: detailPath.path,
    );
    await db.runManagedImageLifecycle(
      () => db.upsertActressWork(
        actressId: actressId,
        work: work,
        missingOnly: missingOnly,
        performerSource: performerSource,
        performers: performers,
        provenance: details.provenanceFor(0),
      ),
    );
    return _WorkImageSaveResult(
      failedVariants: {
        if (cardPath.failed) WorkImageVariant.card,
        if (detailPath.failed) WorkImageVariant.detail,
      },
    );
  }

  Future<_WorkImageResult> _downloadWorkImage({
    required ScrapeWorkDetails details,
    required WorkImageVariant variant,
    required String targetPath,
    required String currentPath,
    required bool missingOnly,
    void Function(String code, WorkImageVariant variant)? onImageDownload,
  }) async {
    if (missingOnly &&
        currentPath.isNotEmpty &&
        File(currentPath).existsSync()) {
      return _WorkImageResult(path: currentPath);
    }
    onImageDownload?.call(details.code, variant);
    // Work images must come only from the explicit WorkImagePolicy hosts
    // (DMM/MGStage).  Source pages such as JavBus and Minnano AV are metadata
    // and avatar sources only; never use their jacket/gallery URI as a work
    // image or as a fallback here.
    try {
      await workImageDownloader.downloadToFile(
        code: details.code,
        studio: details.studio,
        publisher: details.publisher,
        originalImageEvidenceUris: details.originalImageEvidenceUris,
        variant: variant,
        targetPath: targetPath,
      );
      return _WorkImageResult(path: targetPath);
    } catch (_) {
      return _WorkImageResult(
        path: currentPath.isEmpty ? null : currentPath,
        failed: true,
      );
    }
  }

  ScrapeWorkDetails _withScrapeCode(
    ScrapeWorkDetails details,
    String code, {
    required String fallbackTitle,
    required String? fallbackReleaseDate,
  }) {
    return ScrapeWorkDetails(
      source: details.source,
      code: code,
      rawCode: details.rawCode ?? details.code,
      title: details.title.trim().isEmpty ? fallbackTitle : details.title,
      releaseDate: details.releaseDate ?? fallbackReleaseDate,
      durationMinutes: details.durationMinutes,
      studio: details.studio,
      publisher: details.publisher,
      series: details.series,
      performerCount: details.performerCount,
      performers: details.performers,
      imageUris: details.imageUris,
      originalImageEvidenceUris: details.originalImageEvidenceUris,
      fieldSources: details.fieldSources,
      sourceUri: details.sourceUri,
      description: details.description,
      includedWorks: details.includedWorks,
      parentWorks: details.parentWorks,
      genres: details.genres,
      coPerformance: details.coPerformance,
      provenanceFacts: details.provenanceFacts,
    );
  }

  bool _hasExactMatch(Iterable<ScrapeSourceRunResult> results) {
    return results.any(
      (result) =>
          result.error != null ||
          result.state == ScrapeSourceRunState.failed ||
          result.state == ScrapeSourceRunState.zeroResults,
    );
  }

  bool _isCancelled(WorksScrapeCancellationToken? token) =>
      token?.shouldStop ?? false;

  void _notify(
    void Function(WorksScrapeProgress progress)? callback,
    int current,
    int total,
    int saved,
    int excluded,
    int failed, {
    int review = 0,
    WorksScrapePhase phase = WorksScrapePhase.savingWorks,
    ScrapeSourceId? source,
    String? workCode,
    bool totalKnown = false,
    bool updateSourceProgress = true,
    int? sourceCurrent,
    int? sourceTotal,
    bool? sourceTotalKnown,
    int? sourceDiscovered,
  }) {
    if (source != null) {
      final previous = _sourceProgress[source];
      final effectiveSourceTotal = sourceTotal ?? previous?.total ?? total;
      final effectiveSourceTotalKnown =
          sourceTotalKnown ?? previous?.totalKnown ?? totalKnown;
      final effectiveSourceCurrent = updateSourceProgress
          ? sourceCurrent ?? current
          : previous?.current ?? sourceCurrent ?? current;
      _sourceProgress[source] = WorksScrapeSourceProgress(
        phase: phase,
        current: effectiveSourceCurrent,
        total: effectiveSourceTotal,
        totalKnown: effectiveSourceTotalKnown,
        workCode: workCode,
        discovered: sourceDiscovered ?? previous?.discovered ?? 0,
      );
    }
    final isCollection =
        phase == WorksScrapePhase.collectingSources ||
        phase == WorksScrapePhase.syncingActress;
    final effectiveTotal = !isCollection && _uniqueTotal > 0
        ? _uniqueTotal
        : total;
    final effectiveCurrent = switch (phase) {
      WorksScrapePhase.fetchingDetails => _detailCompleted,
      WorksScrapePhase.savingWorks ||
      WorksScrapePhase.downloadingImages ||
      WorksScrapePhase.completed => saved + excluded + failed,
      _ => current,
    };
    final progress = WorksScrapeProgress(
      phase: phase,
      current: effectiveCurrent,
      total: effectiveTotal,
      saved: saved,
      excluded: excluded,
      failed: failed,
      review: review,
      totalKnown: totalKnown || (!isCollection && _uniqueTotal > 0),
      source: source,
      workCode: workCode,
      sourceProgress: Map.unmodifiable(_sourceProgress),
      detailsSource: _detailsSource,
      worksSources: _worksSources,
      rawDiscovered: _rawDiscovered,
      duplicateCount: _duplicateCount,
      detailCompleted: _detailCompleted,
      detailTotal: _detailTotal,
      supplementalEvidenceCompleted: _supplementalEvidenceCompleted,
      supplementalEvidenceTotal: _supplementalEvidenceTotal,
    );
    callback?.call(progress);
    _observer?.onProgress(progress);
  }

  void _notifyWorkOutcome({
    required String code,
    required ScrapeSourceId source,
    required _CanonicalWorkStatus status,
    WorksScrapeFailure? failure,
    String? reason,
    Set<WorkImageVariant> imageFailures = const <WorkImageVariant>{},
    bool cancelled = false,
    bool review = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _observer?.onWorkOutcome(
      code: code,
      source: source,
      outcome: cancelled
          ? ScrapeWorkOutcomeState.cancelled
          : review && status == _CanonicalWorkStatus.saved
          ? ScrapeWorkOutcomeState.review
          : switch (status) {
              _CanonicalWorkStatus.saved => ScrapeWorkOutcomeState.saved,
              _CanonicalWorkStatus.excluded => ScrapeWorkOutcomeState.excluded,
              _CanonicalWorkStatus.failed => ScrapeWorkOutcomeState.failed,
            },
      error: failure?.error,
      reason: reason ?? failure?.reason.name,
      imageFailureVariants: imageFailures.map((variant) => variant.name),
      metadata: metadata,
    );
  }
}

final class _CollectedSource {
  const _CollectedSource({
    required this.source,
    required this.pages,
    required this.summaries,
    required this.result,
  });

  final ScrapeSource source;
  final Map<String, ScrapeActressPage> pages;
  final List<ScrapeWorkSummary> summaries;
  final ScrapeSourceRunResult result;
}

final class _SourceCollectionOutcome {
  const _SourceCollectionOutcome({this.collected, required this.result});

  final _CollectedSource? collected;
  final ScrapeSourceRunResult result;
}

final class _WorkCandidate {
  const _WorkCandidate({required this.source, required this.summary});

  final ScrapeSource source;
  final ScrapeWorkSummary summary;
}

final class _GlobalWorkGroup {
  const _GlobalWorkGroup({
    required this.identityKey,
    required this.identityCodeKey,
    required this.storageCode,
    required this.candidates,
    required this.ordinal,
  });

  final String identityKey;
  final String? identityCodeKey;
  final String storageCode;
  final List<_WorkCandidate> candidates;
  final int ordinal;
}

final class _GlobalCandidateSelection {
  const _GlobalCandidateSelection({
    required this.groups,
    required this.rawDiscovered,
    required this.uniqueCount,
    required this.duplicateCount,
  });

  final List<_GlobalWorkGroup> groups;
  final int rawDiscovered;
  final int uniqueCount;
  final int duplicateCount;
}

final class _SourcePipelineOutcome {
  const _SourcePipelineOutcome({
    required this.sourceId,
    required this.result,
    this.collected,
    this.fetched = const [],
    this.failedCandidates = const [],
  });

  final ScrapeSourceId sourceId;
  final _CollectedSource? collected;
  final ScrapeSourceRunResult result;
  final List<_FetchedWorkDetail> fetched;
  final List<_FailedWorkCandidate> failedCandidates;
}

final class _FetchedWorkDetail {
  const _FetchedWorkDetail({
    required this.candidate,
    required this.identityKey,
    required this.sourceId,
    required this.details,
  });

  final _WorkCandidate candidate;
  final String identityKey;
  final ScrapeSourceId sourceId;
  final ScrapeWorkDetails details;
}

final class _FailedWorkCandidate {
  const _FailedWorkCandidate({
    required this.candidate,
    required this.identityKey,
    required this.reason,
    this.error,
  });

  final _WorkCandidate candidate;
  final String identityKey;
  final WorksScrapeFailureReason reason;
  final Object? error;
}

final class _ResolvedWorkGroup {
  _ResolvedWorkGroup({
    required this.code,
    required this.details,
    required this.identityKey,
    required this.hadSourceFailure,
    required this.sourceId,
    this.failureReason,
    this.failureError,
  });

  final String code;
  final List<ScrapeWorkDetails> details;
  final String identityKey;
  ScrapeSourceId sourceId;
  bool hadSourceFailure;
  WorksScrapeFailureReason? failureReason;
  Object? failureError;
}

enum _CanonicalWorkStatus { saved, excluded, failed }

final class _CanonicalWorkOutcome {
  _CanonicalWorkOutcome({
    required this.code,
    required this.status,
    this.failure,
    Set<WorkImageVariant> imageFailures = const <WorkImageVariant>{},
    this.reason,
    this.review = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : imageFailures = {...imageFailures},
       metadata = Map.unmodifiable(metadata);

  final String code;
  _CanonicalWorkStatus status;
  WorksScrapeFailure? failure;
  String? reason;
  bool review;
  Map<String, Object?> metadata;
  final Set<WorkImageVariant> imageFailures;
}

final class _WorkImageResult {
  const _WorkImageResult({this.path, this.failed = false});

  final String? path;
  final bool failed;
}

final class _PreparedWorkImage {
  const _PreparedWorkImage({
    required this.details,
    required this.currentCard,
    required this.currentDetail,
  });

  final ScrapeWorkDetails details;
  final String currentCard;
  final String currentDetail;
}

final class _WorkImageSaveResult {
  const _WorkImageSaveResult({required this.failedVariants});

  final Set<WorkImageVariant> failedVariants;
}

final class _SourceDetailScheduler {
  _SourceDetailScheduler({required this.delay});

  final Duration delay;
  Future<void> _tail = Future<void>.value();
  bool _hasStarted = false;

  Future<T> add<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      if (_hasStarted && delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      _hasStarted = true;
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

class _ScrapeCancelled implements Exception {
  const _ScrapeCancelled();
}
