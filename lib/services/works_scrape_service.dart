import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../core/database.dart';
import '../models/scrape_source_settings.dart';
import '../models/scraped_actress_details.dart';
import '../models/work_scrape_options.dart';
import 'javbus/javbus_client.dart';
import 'javbus/javbus_scrape_source.dart';
import 'javbus/prefix_exclusion.dart';
import 'javbus/work_image_downloader.dart';
import 'javbus/work_image_policy.dart';
import 'safe_image.dart';
import 'scrape/scrape_image_downloader.dart';
import 'scrape/scrape_models.dart';
import 'scrape/scrape_source.dart';
import 'scrape/scrape_source_registry.dart';
import 'scrape/work_identity.dart';

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

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
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
  performerCountUnavailable,
  databaseSaveFailed,
}

final class WorksScrapeFailure {
  const WorksScrapeFailure({
    required this.code,
    required this.stage,
    required this.reason,
    this.source,
  });

  final String code;
  final WorksScrapeFailureStage stage;
  final WorksScrapeFailureReason reason;
  final ScrapeSourceId? source;
}

final class WorksScrapeImageFailure {
  const WorksScrapeImageFailure({required this.code, required this.variants});

  final String code;
  final List<WorkImageVariant> variants;
}

class WorksScrapeProgress {
  const WorksScrapeProgress({
    required this.current,
    required this.total,
    required this.saved,
    required this.excluded,
    required this.failed,
    this.phase = WorksScrapePhase.savingWorks,
    this.source,
    this.workCode,
  });

  final WorksScrapePhase phase;
  final int current;
  final int total;
  final int saved;
  final int excluded;
  final int failed;
  final ScrapeSourceId? source;
  final String? workCode;
}

class WorksScrapeResult {
  const WorksScrapeResult({
    required this.saved,
    required this.excluded,
    required this.failed,
    required this.cancelled,
    this.actressImageStatus = ActressImageSyncStatus.notRequested,
    this.partialSuccess = false,
    this.sourceResults = const {},
    this.failedWorks = const [],
    this.imageFailures = const [],
  });

  final int saved;
  final int excluded;
  final int failed;
  final bool cancelled;
  final ActressImageSyncStatus actressImageStatus;
  final bool partialSuccess;
  final Map<ScrapeSourceId, ScrapeSourceRunResult> sourceResults;
  final List<WorksScrapeFailure> failedWorks;
  final List<WorksScrapeImageFailure> imageFailures;
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
  }) : client = client,
       sources = sources ?? _legacySources(client),
       workImageDownloader = workImageDownloader ?? WorkImageDownloader(),
       actressImageDownloader =
           actressImageDownloader ?? HttpActressImageDownloader(),
       imageDirectory = imageDirectory ?? path.join(db.imgDir, 'scraped');

  final AppDatabase db;
  final JavBusClient? client;
  final Map<ScrapeSourceId, ScrapeSource> sources;
  final WorkImageDownloader workImageDownloader;
  final ActressImageDownloader actressImageDownloader;
  final ScrapeImageUriDownloader? imageUriDownloader;
  final String imageDirectory;

  static Map<ScrapeSourceId, ScrapeSource> _legacySources(
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
  }) async {
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
    final settings =
        sourceSettings ?? const ScrapeSourceSettings.legacyJavBus();
    final queries = _queries(name, aliases);
    final requestedWorkIds = ScrapeSourceRegistry.resolveWorksSources(
      settings.worksSource,
    );
    final sourceResults = <ScrapeSourceId, ScrapeSourceRunResult>{};
    final collectedById = <ScrapeSourceId, _CollectedSource>{};
    final collectionFutures =
        <ScrapeSourceId, Future<_SourceCollectionOutcome>>{};
    final sourceIdsToCollect = <ScrapeSourceId>[
      ...requestedWorkIds,
      if (!requestedWorkIds.contains(settings.actressDetailsSource))
        settings.actressDetailsSource,
    ];

    // Start every source collection immediately.  Each works source then
    // chains its own detail queue from this future, so one site's details can
    // start while another site is still traversing its works pages.
    for (final sourceId in sourceIdsToCollect) {
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
      collectionFutures[sourceId] = source == null
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
              includeWorks: requestedWorkIds.contains(sourceId),
            );
    }

    void recordCollectionOutcome(
      ScrapeSourceId sourceId,
      _SourceCollectionOutcome outcome,
    ) {
      final collected = outcome.collected;
      if (collected != null) {
        collectedById[sourceId] = collected;
      }
      if (requestedWorkIds.contains(sourceId) ||
          sourceId == settings.actressDetailsSource) {
        sourceResults[sourceId] = outcome.result;
      }
    }

    final exclusions = PrefixExclusion(options.excludedPrefixes);
    final sourcePipelines = <Future<_SourcePipelineOutcome>>[
      for (final sourceId in requestedWorkIds)
        _runSourcePipeline(
          sourceId: sourceId,
          source: sources[sourceId],
          collectionFuture: collectionFutures[sourceId]!,
          exclusions: exclusions,
          cancellationToken: cancellationToken,
          onProgress: onProgress,
        ),
    ];

    // Actress metadata synchronization may await its own collection, but all
    // works source pipelines above are already running and are not blocked by
    // this optional profile sync.
    final detailsSourceId = settings.actressDetailsSource;
    final detailsSource = sources[detailsSourceId];
    final detailsCollectionFuture = collectionFutures[detailsSourceId];
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
        );
      }
    }

    final pipelineResults = await Future.wait(sourcePipelines);
    for (final pipeline in pipelineResults) {
      recordCollectionOutcome(
        pipeline.sourceId,
        _SourceCollectionOutcome(
          collected: pipeline.collected,
          result: pipeline.result,
        ),
      );
    }

    if (_isCancelled(cancellationToken)) {
      return WorksScrapeResult(
        saved: 0,
        excluded: pipelineResults.fold(
          0,
          (total, pipeline) => total + pipeline.preExcluded,
        ),
        failed: 0,
        cancelled: true,
        actressImageStatus: actressImageStatus,
        sourceResults: Map.unmodifiable(sourceResults),
      );
    }

    final successfulWorkSources = collectedById.values
        .where(
          (value) =>
              requestedWorkIds.contains(value.source.id) &&
              value.result.succeeded,
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
    final preExcluded = pipelineResults.fold(
      0,
      (total, pipeline) => total + pipeline.preExcluded,
    );
    final resolvedGroups = _resolveAcrossSources(fetched, failedCandidates);
    if (_isCancelled(cancellationToken)) {
      return WorksScrapeResult(
        saved: 0,
        excluded: preExcluded,
        failed: 0,
        cancelled: true,
        actressImageStatus: actressImageStatus,
        partialSuccess: true,
        sourceResults: Map.unmodifiable(sourceResults),
      );
    }

    _notify(
      onProgress,
      0,
      resolvedGroups.length,
      0,
      preExcluded,
      0,
      phase: WorksScrapePhase.resolvingWorks,
    );
    var resolveCurrent = 0;
    for (final group in resolvedGroups) {
      if (_isCancelled(cancellationToken)) {
        break;
      }
      resolveCurrent++;
      _notify(
        onProgress,
        resolveCurrent,
        resolvedGroups.length,
        0,
        preExcluded,
        0,
        phase: WorksScrapePhase.resolvingWorks,
        source: group.sourceId,
      );
    }
    final outcomes = <String, _CanonicalWorkOutcome>{};

    void recordOutcome({
      required String identityKey,
      required String code,
      required _CanonicalWorkStatus status,
      WorksScrapeFailure? failure,
      Set<WorkImageVariant> imageFailures = const <WorkImageVariant>{},
    }) {
      final existing = outcomes[identityKey];
      if (existing == null) {
        outcomes[identityKey] = _CanonicalWorkOutcome(
          code: code,
          status: status,
          failure: failure,
          imageFailures: imageFailures,
        );
        return;
      }
      existing.imageFailures.addAll(imageFailures);
      if (status == _CanonicalWorkStatus.saved ||
          existing.status == _CanonicalWorkStatus.excluded) {
        existing.status = status;
        existing.failure = failure;
      }
    }

    int savedCount() => outcomes.values
        .where((outcome) => outcome.status == _CanonicalWorkStatus.saved)
        .length;

    int excludedCount() =>
        preExcluded +
        outcomes.values
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
      phase: WorksScrapePhase.savingWorks,
    );
    var savingCurrent = 0;
    for (final resolved in resolvedGroups) {
      if (_isCancelled(cancellationToken)) {
        break;
      }
      _notify(
        onProgress,
        savingCurrent,
        resolvedGroups.length,
        savedCount(),
        excludedCount(),
        failedCount(),
        phase: WorksScrapePhase.savingWorks,
        source: resolved.sourceId,
      );
      final code = normalizeScrapeWorkCodeSurface(resolved.code);
      if (code == null) {
        recordOutcome(
          identityKey: resolved.identityKey,
          code: resolved.code,
          status: _CanonicalWorkStatus.failed,
          failure: WorksScrapeFailure(
            code: resolved.code,
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
          ),
        );
      } else if (exclusions.matches(code)) {
        recordOutcome(
          identityKey: resolved.identityKey,
          code: code,
          status: _CanonicalWorkStatus.excluded,
        );
      } else {
        final merged = _mergeWorkDetails(resolved.details, code);
        final maxActressCount = options.maxActressCount;
        final performerCount = merged.performerCount;
        if (maxActressCount != null &&
            (performerCount == null || performerCount <= 0)) {
          recordOutcome(
            identityKey: resolved.identityKey,
            code: code,
            status: _CanonicalWorkStatus.failed,
            failure: WorksScrapeFailure(
              code: code,
              stage: WorksScrapeFailureStage.resolvingWorks,
              reason: WorksScrapeFailureReason.performerCountUnavailable,
              source: resolved.sourceId,
            ),
          );
        } else if (maxActressCount != null &&
            performerCount! > maxActressCount) {
          recordOutcome(
            identityKey: resolved.identityKey,
            code: code,
            status: _CanonicalWorkStatus.excluded,
          );
        } else {
          try {
            final savedWork = await _saveWork(
              actressId: actressId,
              details: merged,
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
                  phase: WorksScrapePhase.downloadingImages,
                  source: resolved.sourceId,
                  workCode: imageCode,
                );
              },
            );
            recordOutcome(
              identityKey: resolved.identityKey,
              code: code,
              status: _CanonicalWorkStatus.saved,
              imageFailures: savedWork.failedVariants,
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
      savingCurrent++;
      _notify(
        onProgress,
        savingCurrent,
        resolvedGroups.length,
        savedCount(),
        excludedCount(),
        failedCount(),
        phase: WorksScrapePhase.savingWorks,
        source: resolved.sourceId,
      );
    }

    final saved = savedCount();
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
        phase: WorksScrapePhase.completed,
      );
    }
    return WorksScrapeResult(
      saved: saved,
      excluded: excluded,
      failed: failed,
      cancelled: cancelled,
      actressImageStatus: actressImageStatus,
      partialSuccess: partial,
      sourceResults: Map.unmodifiable(sourceResults),
      failedWorks: List.unmodifiable(failedWorks),
      imageFailures: List.unmodifiable(imageFailures),
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
  }) async {
    final pages = <String, ScrapeActressPage>{};
    final matches = <String, ScrapeActressSearchResult>{};
    final completedUris = <String>{};
    final summaries = <ScrapeWorkSummary>[];
    Object? lastError;
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
        lastError = error;
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
    final state = _isCancelled(cancellationToken)
        ? ScrapeSourceRunState.cancelled
        : traversed
        ? (summaries.isEmpty
              ? ScrapeSourceRunState.zeroResults
              : ScrapeSourceRunState.success)
        : matched
        ? ScrapeSourceRunState.failed
        : ScrapeSourceRunState.unavailable;
    return _CollectedSource(
      source: source,
      pages: pages,
      summaries: summaries,
      result: ScrapeSourceRunResult(
        source: source.id,
        state: state,
        discovered: summaries.length,
        error: lastError,
      ),
    );
  }

  Future<_SourceCollectionOutcome> _collectSourceSafely({
    required ScrapeSource source,
    required List<String> queries,
    required WorksScrapeCancellationToken? cancellationToken,
    required bool includeWorks,
  }) async {
    try {
      final collected = await _collectSource(
        source: source,
        queries: queries,
        cancellationToken: cancellationToken,
        includeWorks: includeWorks,
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
              : ScrapeSourceRunState.failed,
          error: error,
        ),
      );
    }
  }

  Future<_SourcePipelineOutcome> _runSourcePipeline({
    required ScrapeSourceId sourceId,
    required ScrapeSource? source,
    required Future<_SourceCollectionOutcome> collectionFuture,
    required PrefixExclusion exclusions,
    required WorksScrapeCancellationToken? cancellationToken,
    void Function(WorksScrapeProgress progress)? onProgress,
  }) async {
    final collectionOutcome = await collectionFuture;
    final collected = collectionOutcome.collected;
    if (source == null ||
        collected == null ||
        !collectionOutcome.result.succeeded) {
      return _SourcePipelineOutcome(
        sourceId: sourceId,
        collected: collected,
        result: collectionOutcome.result,
      );
    }

    final selection = _selectWorkCandidates(collected, exclusions);
    var detailCurrent = 0;
    _notify(
      onProgress,
      0,
      selection.candidates.length,
      0,
      selection.preExcluded,
      0,
      phase: WorksScrapePhase.fetchingDetails,
      source: sourceId,
    );

    void notifyDetailProgress() {
      _notify(
        onProgress,
        detailCurrent,
        selection.candidates.length,
        0,
        selection.preExcluded,
        0,
        phase: WorksScrapePhase.fetchingDetails,
        source: sourceId,
      );
    }

    final detailResult = await _fetchDetailsForSourceSafely(
      source: source,
      candidates: selection.candidates,
      cancellationToken: cancellationToken,
      onAttemptStart: (_) => notifyDetailProgress(),
      onAttemptComplete: (_) {
        detailCurrent++;
        notifyDetailProgress();
      },
    );
    final sourceResolution = _resolveSourceDetails(detailResult);
    return _SourcePipelineOutcome(
      sourceId: sourceId,
      collected: collected,
      result: collectionOutcome.result,
      fetched: sourceResolution.fetched,
      failedCandidates: sourceResolution.failedCandidates,
      preExcluded: selection.preExcluded,
    );
  }

  _SourceCandidateSelection _selectWorkCandidates(
    _CollectedSource collected,
    PrefixExclusion exclusions,
  ) {
    final selected = <_WorkCandidate>[];
    final selectedByTitle = <String, int>{};
    var preExcluded = 0;

    for (final summary in collected.summaries) {
      final summaryCode = summary.code?.trim() ?? '';
      if (summaryCode.isNotEmpty && exclusions.matches(summaryCode)) {
        preExcluded++;
        continue;
      }
      final candidate = _WorkCandidate(
        source: collected.source,
        summary: summary,
      );
      final identity = scrapeTitleIdentity(summary.title);
      if (!identity.isUsable) {
        selected.add(candidate);
        continue;
      }
      final existingIndex = selectedByTitle[identity.key];
      if (existingIndex == null) {
        selectedByTitle[identity.key] = selected.length;
        selected.add(candidate);
        continue;
      }

      // When the title explicitly identifies an edition, keep the ordinary
      // candidate. For equally classified titles, traversal order is the
      // deterministic tie-break and no code is consulted.
      final existing = selected[existingIndex];
      final existingIdentity = scrapeTitleIdentity(existing.summary.title);
      if (existingIdentity.isSpecialEdition && !identity.isSpecialEdition) {
        selected[existingIndex] = candidate;
      }
    }
    return _SourceCandidateSelection(
      candidates: List.unmodifiable(selected),
      preExcluded: preExcluded,
    );
  }

  _SourceDetailResolution _resolveSourceDetails(_DetailQueueResult result) {
    final resolvedFetched = <_FetchedWorkDetail>[];
    final fetchedByKey = <String, int>{};
    for (final fetched in result.fetched) {
      final identity = scrapeTitleIdentity(fetched.details.title);
      final key = identity.isUsable
          ? 'title:${identity.key}'
          : 'uri:${fetched.candidate.summary.detailUri}';
      final existingIndex = fetchedByKey[key];
      if (existingIndex == null) {
        fetchedByKey[key] = resolvedFetched.length;
        resolvedFetched.add(fetched);
        continue;
      }
      final existing = resolvedFetched[existingIndex];
      final existingIdentity = scrapeTitleIdentity(existing.details.title);
      if (existingIdentity.isSpecialEdition && !identity.isSpecialEdition) {
        resolvedFetched[existingIndex] = fetched;
      }
    }

    final failed = <_FailedWorkCandidate>[];
    final failedKeys = <String>{};
    for (final failure in result.failedCandidates) {
      final identity = scrapeTitleIdentity(failure.candidate.summary.title);
      final key = identity.isUsable
          ? 'title:${identity.key}'
          : 'uri:${failure.candidate.summary.detailUri}';
      if (fetchedByKey.containsKey(key) || !failedKeys.add(key)) {
        continue;
      }
      failed.add(failure);
    }
    return _SourceDetailResolution(
      fetched: List.unmodifiable(resolvedFetched),
      failedCandidates: List.unmodifiable(failed),
    );
  }

  Future<_DetailQueueResult> _fetchDetailsForSourceSafely({
    required ScrapeSource source,
    required List<_WorkCandidate> candidates,
    required WorksScrapeCancellationToken? cancellationToken,
    void Function(_WorkCandidate candidate)? onAttemptStart,
    void Function(_WorkCandidate candidate)? onAttemptComplete,
  }) async {
    try {
      return await _fetchDetailsForSource(
        source: source,
        candidates: candidates,
        cancellationToken: cancellationToken,
        onAttemptStart: onAttemptStart,
        onAttemptComplete: onAttemptComplete,
      );
    } catch (_) {
      final failed = <_FailedWorkCandidate>[];
      for (final candidate in candidates) {
        onAttemptStart?.call(candidate);
        failed.add(
          _FailedWorkCandidate(
            candidate: candidate,
            reason: WorksScrapeFailureReason.detailsUnavailable,
          ),
        );
        onAttemptComplete?.call(candidate);
      }
      return _DetailQueueResult(failedCandidates: failed);
    }
  }

  Future<_DetailQueueResult> _fetchDetailsForSource({
    required ScrapeSource source,
    required List<_WorkCandidate> candidates,
    required WorksScrapeCancellationToken? cancellationToken,
    void Function(_WorkCandidate candidate)? onAttemptStart,
    void Function(_WorkCandidate candidate)? onAttemptComplete,
  }) async {
    final fetched = <_FetchedWorkDetail>[];
    final failedCandidates = <_FailedWorkCandidate>[];
    for (final candidate in candidates) {
      if (_isCancelled(cancellationToken)) {
        break;
      }
      onAttemptStart?.call(candidate);
      try {
        final details = await source.fetchWorkDetails(candidate.summary);
        final code = normalizeScrapeWorkCodeSurface(details.code);
        if (code == null) {
          failedCandidates.add(
            _FailedWorkCandidate(
              candidate: candidate,
              reason: WorksScrapeFailureReason.invalidCode,
            ),
          );
          continue;
        }
        fetched.add(
          _FetchedWorkDetail(
            candidate: candidate,
            sourceId: source.id,
            details: _withScrapeCode(
              details,
              code,
              fallbackTitle: candidate.summary.title,
              fallbackReleaseDate: candidate.summary.releaseDate,
            ),
          ),
        );
      } catch (_) {
        failedCandidates.add(
          _FailedWorkCandidate(
            candidate: candidate,
            reason: WorksScrapeFailureReason.detailsUnavailable,
          ),
        );
      } finally {
        onAttemptComplete?.call(candidate);
      }
    }
    return _DetailQueueResult(
      fetched: fetched,
      failedCandidates: failedCandidates,
    );
  }

  List<_ResolvedWorkGroup> _resolveAcrossSources(
    List<_FetchedWorkDetail> fetched,
    List<_FailedWorkCandidate> failedCandidates,
  ) {
    final parent = List<int>.generate(fetched.length, (index) => index);

    int find(int index) {
      var current = index;
      while (parent[current] != current) {
        parent[current] = parent[parent[current]];
        current = parent[current];
      }
      return current;
    }

    void union(int left, int right) {
      final leftRoot = find(left);
      final rightRoot = find(right);
      if (leftRoot != rightRoot) {
        parent[rightRoot] = leftRoot;
      }
    }

    for (var left = 0; left < fetched.length; left++) {
      for (var right = left + 1; right < fetched.length; right++) {
        final first = fetched[left];
        final second = fetched[right];
        if (first.sourceId == second.sourceId) {
          continue;
        }
        final firstCode = normalizeScrapeWorkCodeSurface(first.details.code);
        final secondCode = normalizeScrapeWorkCodeSurface(second.details.code);
        final sameCode =
            firstCode != null && secondCode != null && firstCode == secondCode;
        final firstTitle = scrapeTitleIdentity(first.details.title);
        final secondTitle = scrapeTitleIdentity(second.details.title);
        final rebeccaTitleMatch =
            isRebeccaPublisher(first.details.publisher) &&
            isRebeccaPublisher(second.details.publisher) &&
            firstTitle.isUsable &&
            secondTitle.isUsable &&
            firstTitle.key == secondTitle.key;
        if (sameCode || rebeccaTitleMatch) {
          union(left, right);
        }
      }
    }

    final grouped = <int, List<_FetchedWorkDetail>>{};
    for (var index = 0; index < fetched.length; index++) {
      grouped
          .putIfAbsent(find(index), () => <_FetchedWorkDetail>[])
          .add(fetched[index]);
    }

    final resolved = <_ResolvedWorkGroup>[];
    var groupIndex = 0;
    for (final details in grouped.values) {
      details.sort(
        (left, right) => _sourcePriority(
          left.sourceId,
        ).compareTo(_sourcePriority(right.sourceId)),
      );
      final detailValues = details
          .map((item) => item.details)
          .toList(growable: false);
      final usesRebeccaCode = _hasRebeccaTitleMatch(detailValues);
      final code = usesRebeccaCode
          ? _preferredRebeccaCode(detailValues)
          : normalizeScrapeWorkCodeSurface(detailValues.first.code) ??
                '未知番號：${detailValues.first.title}';
      resolved.add(
        _ResolvedWorkGroup(
          code: code,
          details: detailValues,
          identityKey: 'resolved:$groupIndex',
          hadSourceFailure: false,
          sourceId: details.first.sourceId,
        ),
      );
      groupIndex++;
    }

    for (var index = 0; index < failedCandidates.length; index++) {
      final failed = failedCandidates[index];
      final rawCode = failed.candidate.summary.code?.trim() ?? '';
      final code = rawCode.isEmpty
          ? '未知番號：${failed.candidate.summary.title.trim()}'
          : normalizeScrapeWorkCodeSurface(rawCode) ?? rawCode;
      resolved.add(
        _ResolvedWorkGroup(
          code: code,
          details: const <ScrapeWorkDetails>[],
          identityKey:
              'failed:${failed.candidate.source.id.storageValue}:$index',
          hadSourceFailure: true,
          sourceId: failed.candidate.source.id,
          failureReason: failed.reason,
        ),
      );
    }
    return List.unmodifiable(resolved);
  }

  bool _hasRebeccaTitleMatch(List<ScrapeWorkDetails> details) {
    for (var left = 0; left < details.length; left++) {
      for (var right = left + 1; right < details.length; right++) {
        if (details[left].source == details[right].source) {
          continue;
        }
        final firstTitle = scrapeTitleIdentity(details[left].title);
        final secondTitle = scrapeTitleIdentity(details[right].title);
        if (isRebeccaPublisher(details[left].publisher) &&
            isRebeccaPublisher(details[right].publisher) &&
            firstTitle.isUsable &&
            firstTitle.key == secondTitle.key) {
          return true;
        }
      }
    }
    return false;
  }

  String _preferredRebeccaCode(List<ScrapeWorkDetails> details) {
    final candidates = details
        .map((item) => normalizeScrapeWorkCodeSurface(item.code))
        .whereType<String>()
        .toList();
    candidates.sort((left, right) {
      final length = left.length.compareTo(right.length);
      if (length != 0) {
        return length;
      }
      final sourcePriority = _sourcePriorityForCode(
        left,
        details,
      ).compareTo(_sourcePriorityForCode(right, details));
      if (sourcePriority != 0) {
        return sourcePriority;
      }
      return left.compareTo(right);
    });
    return candidates.first;
  }

  int _sourcePriorityForCode(String code, List<ScrapeWorkDetails> details) {
    for (final detail in details) {
      final normalized = normalizeScrapeWorkCodeSurface(detail.code);
      if (normalized == code) {
        return _sourcePriority(detail.source);
      }
    }
    return ScrapeSourceRegistry.aggregatePriority.length;
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
    return db.runManagedImageLifecycle(
      () => _saveWorkUnlocked(
        actressId: actressId,
        details: details,
        missingOnly: missingOnly,
        cancellationToken: cancellationToken,
        onImageDownload: onImageDownload,
      ),
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
    final code = normalizeScrapeWorkCodeSurface(details.code);
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
    var work = details.toWork();
    final workId = await db.upsertActressWork(
      actressId: actressId,
      work: work,
      missingOnly: missingOnly,
    );
    final current = await db.getWorkById(workId);
    final currentCard = current?['card_image_path']?.toString() ?? '';
    final currentDetail = current?['detail_image_path']?.toString() ?? '';
    if (_isCancelled(cancellationToken)) {
      throw const _ScrapeCancelled();
    }
    final cardPath = await _downloadWorkImage(
      details: details,
      variant: WorkImageVariant.card,
      targetPath: path.join(
        imageDirectory,
        'works',
        workImageDownloader.fileNameFor(
          code: details.code,
          variant: WorkImageVariant.card,
        ),
      ),
      currentPath: currentCard,
      missingOnly: missingOnly,
      onImageDownload: onImageDownload,
    );
    if (_isCancelled(cancellationToken)) {
      throw const _ScrapeCancelled();
    }
    final detailPath = await _downloadWorkImage(
      details: details,
      variant: WorkImageVariant.detail,
      targetPath: path.join(
        imageDirectory,
        'works',
        workImageDownloader.fileNameFor(
          code: details.code,
          variant: WorkImageVariant.detail,
        ),
      ),
      currentPath: currentDetail,
      missingOnly: missingOnly,
      onImageDownload: onImageDownload,
    );
    if (_isCancelled(cancellationToken)) {
      throw const _ScrapeCancelled();
    }
    work = details.toWork(
      cardImagePath: cardPath.path,
      detailImagePath: detailPath.path,
    );
    await db.upsertActressWork(
      actressId: actressId,
      work: work,
      missingOnly: missingOnly,
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
      title: details.title.trim().isEmpty ? fallbackTitle : details.title,
      releaseDate: details.releaseDate ?? fallbackReleaseDate,
      durationMinutes: details.durationMinutes,
      studio: details.studio,
      publisher: details.publisher,
      series: details.series,
      performerCount: details.performerCount,
      imageUris: details.imageUris,
    );
  }

  ScrapeWorkDetails _mergeWorkDetails(
    List<ScrapeWorkDetails> details,
    String code,
  ) {
    String? firstText(String? Function(ScrapeWorkDetails) select) {
      for (final item in details) {
        final value = select(item)?.trim();
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
      return null;
    }

    int? firstInt(int? Function(ScrapeWorkDetails) select) {
      for (final item in details) {
        final value = select(item);
        if (value != null && value > 0) {
          return value;
        }
      }
      return null;
    }

    int? performerCount;
    for (final item in details) {
      final value = item.performerCount;
      if (value != null && (performerCount == null || value > performerCount)) {
        performerCount = value;
      }
    }
    final imageUris = <Uri>[];
    final imageKeys = <String>{};
    for (final item in details) {
      for (final uri in item.imageUris) {
        if (imageKeys.add(uri.toString())) {
          imageUris.add(uri);
        }
      }
    }
    return ScrapeWorkDetails(
      source: details.first.source,
      code: code,
      title: firstText((item) => item.title) ?? code,
      releaseDate: firstText((item) => item.releaseDate),
      durationMinutes: firstInt((item) => item.durationMinutes),
      studio: firstText((item) => item.studio),
      publisher: firstText((item) => item.publisher),
      series: firstText((item) => item.series),
      performerCount: performerCount,
      imageUris: List.unmodifiable(imageUris),
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

  int _sourcePriority(ScrapeSourceId sourceId) {
    final index = ScrapeSourceRegistry.aggregatePriority.indexOf(sourceId);
    return index < 0 ? ScrapeSourceRegistry.aggregatePriority.length : index;
  }

  bool _isCancelled(WorksScrapeCancellationToken? token) =>
      token?.isCancelled ?? false;

  void _notify(
    void Function(WorksScrapeProgress progress)? callback,
    int current,
    int total,
    int saved,
    int excluded,
    int failed, {
    WorksScrapePhase phase = WorksScrapePhase.savingWorks,
    ScrapeSourceId? source,
    String? workCode,
  }) {
    callback?.call(
      WorksScrapeProgress(
        phase: phase,
        current: current,
        total: total,
        saved: saved,
        excluded: excluded,
        failed: failed,
        source: source,
        workCode: workCode,
      ),
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

final class _SourcePipelineOutcome {
  const _SourcePipelineOutcome({
    required this.sourceId,
    required this.result,
    this.collected,
    this.fetched = const [],
    this.failedCandidates = const [],
    this.preExcluded = 0,
  });

  final ScrapeSourceId sourceId;
  final _CollectedSource? collected;
  final ScrapeSourceRunResult result;
  final List<_FetchedWorkDetail> fetched;
  final List<_FailedWorkCandidate> failedCandidates;
  final int preExcluded;
}

final class _SourceCandidateSelection {
  const _SourceCandidateSelection({
    required this.candidates,
    required this.preExcluded,
  });

  final List<_WorkCandidate> candidates;
  final int preExcluded;
}

final class _SourceDetailResolution {
  const _SourceDetailResolution({
    required this.fetched,
    required this.failedCandidates,
  });

  final List<_FetchedWorkDetail> fetched;
  final List<_FailedWorkCandidate> failedCandidates;
}

final class _FetchedWorkDetail {
  const _FetchedWorkDetail({
    required this.candidate,
    required this.sourceId,
    required this.details,
  });

  final _WorkCandidate candidate;
  final ScrapeSourceId sourceId;
  final ScrapeWorkDetails details;
}

final class _FailedWorkCandidate {
  const _FailedWorkCandidate({required this.candidate, required this.reason});

  final _WorkCandidate candidate;
  final WorksScrapeFailureReason reason;
}

final class _DetailQueueResult {
  const _DetailQueueResult({
    this.fetched = const [],
    this.failedCandidates = const [],
  });

  final List<_FetchedWorkDetail> fetched;
  final List<_FailedWorkCandidate> failedCandidates;
}

final class _ResolvedWorkGroup {
  _ResolvedWorkGroup({
    required this.code,
    required this.details,
    required this.identityKey,
    required this.hadSourceFailure,
    required this.sourceId,
    this.failureReason,
  });

  final String code;
  final List<ScrapeWorkDetails> details;
  final String identityKey;
  final ScrapeSourceId sourceId;
  bool hadSourceFailure;
  WorksScrapeFailureReason? failureReason;
}

enum _CanonicalWorkStatus { saved, excluded, failed }

final class _CanonicalWorkOutcome {
  _CanonicalWorkOutcome({
    required this.code,
    required this.status,
    this.failure,
    Set<WorkImageVariant> imageFailures = const <WorkImageVariant>{},
  }) : imageFailures = {...imageFailures};

  final String code;
  _CanonicalWorkStatus status;
  WorksScrapeFailure? failure;
  final Set<WorkImageVariant> imageFailures;
}

final class _WorkImageResult {
  const _WorkImageResult({this.path, this.failed = false});

  final String? path;
  final bool failed;
}

final class _WorkImageSaveResult {
  const _WorkImageSaveResult({required this.failedVariants});

  final Set<WorkImageVariant> failedVariants;
}

class _ScrapeCancelled implements Exception {
  const _ScrapeCancelled();
}
