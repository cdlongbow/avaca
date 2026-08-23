import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/database.dart';
import '../models/scrape_job.dart';
import '../models/scrape_source_settings.dart';
import '../models/work_scrape_options.dart';
import 'javbus/javbus_client.dart';
import 'javbus/javbus_verification.dart';
import 'scrape_event_sanitizer.dart';
import 'scrape_run_observer.dart';
import 'scrape_job_repository.dart';
import 'scrape_rules_repository.dart';
import 'scrape/scrape_models.dart';
import 'works_scrape_service.dart';
import 'works_scrape_session_factory.dart';

class ScrapeJobProgressAccumulator {
  ScrapeJobProgressAccumulator({
    this.discoveredCount = 0,
    this.processedCount = 0,
    this.savedCount = 0,
    this.excludedCount = 0,
    this.failedCount = 0,
  });

  int discoveredCount;
  int processedCount;
  int savedCount;
  int excludedCount;
  int failedCount;
  final _outcomes = <String, ScrapeWorkOutcomeState>{};
  int _excludedBaseline = 0;
  bool _hasOutcome = false;

  void seed(ScrapeJob job) {
    discoveredCount = math.max(discoveredCount, job.discoveredCount);
    processedCount = math.max(processedCount, job.processedCount);
    savedCount = math.max(savedCount, job.savedCount);
    excludedCount = math.max(excludedCount, job.excludedCount);
    failedCount = math.max(failedCount, job.failedCount);
  }

  void seedItems(Iterable<ScrapeJobItem> items) {
    if (_outcomes.isNotEmpty) return;
    for (final item in items) {
      final outcome = switch (item.state) {
        ScrapeJobItemState.succeeded => ScrapeWorkOutcomeState.saved,
        ScrapeJobItemState.excluded => ScrapeWorkOutcomeState.excluded,
        ScrapeJobItemState.failed => ScrapeWorkOutcomeState.failed,
        _ => null,
      };
      if (outcome != null) _outcomes[item.canonicalCode] = outcome;
    }
    _hasOutcome = _outcomes.isNotEmpty;
    if (_hasOutcome) {
      _excludedBaseline = math.max(
        0,
        excludedCount - _count(ScrapeWorkOutcomeState.excluded),
      );
      _recountOutcomes();
    }
  }

  void recordOutcome(String code, ScrapeWorkOutcomeState outcome) {
    if (outcome == ScrapeWorkOutcomeState.cancelled) return;
    if (!_hasOutcome) {
      _excludedBaseline = math.max(_excludedBaseline, excludedCount);
    }
    _outcomes[code] = outcome;
    _hasOutcome = true;
    _recountOutcomes();
  }

  void apply(WorksScrapeProgress progress) {
    discoveredCount = math.max(discoveredCount, progress.total);
    if (!_hasOutcome) {
      savedCount = math.max(savedCount, progress.saved);
      excludedCount = math.max(excludedCount, progress.excluded);
      failedCount = math.max(failedCount, progress.failed);
    } else {
      _excludedBaseline = math.max(
        _excludedBaseline,
        progress.excluded - _count(ScrapeWorkOutcomeState.excluded),
      );
      _recountOutcomes();
    }
    processedCount = math.max(
      processedCount,
      math.max(progress.current, savedCount + excludedCount + failedCount),
    );
  }

  int _count(ScrapeWorkOutcomeState state) =>
      _outcomes.values.where((outcome) => outcome == state).length;

  void _recountOutcomes() {
    savedCount = _count(ScrapeWorkOutcomeState.saved);
    excludedCount = _excludedBaseline + _count(ScrapeWorkOutcomeState.excluded);
    failedCount = _count(ScrapeWorkOutcomeState.failed);
    processedCount = math.max(
      processedCount,
      savedCount + excludedCount + failedCount,
    );
  }
}

class ScrapeJobWriteFence {
  ScrapeJobWriteFence({
    required Future<void> Function(Future<void> Function()) enqueue,
    required Future<void> Function() drain,
  }) : _enqueue = enqueue,
       _drain = drain;

  final Future<void> Function(Future<void> Function()) _enqueue;
  final Future<void> Function() _drain;
  bool _accepting = true;

  void stopAccepting() => _accepting = false;

  Future<void> enqueue(Future<void> Function() operation) {
    if (!_accepting) return Future<void>.value();
    return _enqueue(operation);
  }

  Future<void> drain() => _drain();
}

class ScrapeJobTerminalCounters {
  const ScrapeJobTerminalCounters({
    required this.processed,
    required this.saved,
    required this.excluded,
    required this.failed,
    required this.imageFailures,
    required this.cancelled,
  });

  factory ScrapeJobTerminalCounters.fromResult(WorksScrapeResult result) {
    return ScrapeJobTerminalCounters(
      processed: result.saved + result.excluded + result.failed,
      saved: result.saved,
      excluded: result.excluded,
      failed: result.failed,
      imageFailures: result.imageFailures.length,
      cancelled: result.cancelled,
    );
  }

  final int processed;
  final int saved;
  final int excluded;
  final int failed;
  final int imageFailures;
  final bool cancelled;
}

ScrapeJobState resolveScrapeJobFinalState({
  required bool pauseRequested,
  required bool cancelRequested,
  required bool resultCancelled,
  required bool partialSuccess,
}) {
  if (pauseRequested) return ScrapeJobState.paused;
  if (cancelRequested || resultCancelled) return ScrapeJobState.cancelled;
  if (partialSuccess) return ScrapeJobState.partial;
  return ScrapeJobState.succeeded;
}

String? buildScrapeJobResultDiagnostic(WorksScrapeResult result) {
  final lines = <String>[];
  for (final entry in result.sourceResults.entries) {
    final sourceResult = entry.value;
    final hasSourceWarning =
        sourceResult.error != null ||
        (sourceResult.state != ScrapeSourceRunState.success &&
            sourceResult.state != ScrapeSourceRunState.zeroResults);
    if (!hasSourceWarning) continue;
    final reason = sourceResult.error == null
        ? sourceResult.state.name
        : ScrapeEventSanitizer.message(
            sourceResult.error,
            fallback: sourceResult.state.name,
          );
    lines.add('來源 ${entry.key.storageValue}：$reason');
  }
  for (final failure in result.failedWorks) {
    final reason = failure.error == null
        ? failure.reason.name
        : ScrapeEventSanitizer.message(
            failure.error,
            fallback: failure.reason.name,
          );
    lines.add('作品 ${failure.code}：$reason');
  }
  for (final imageFailure in result.imageFailures) {
    lines.add(scrapeJobImageFailureMessage(imageFailure));
  }
  if (lines.isEmpty && result.partialSuccess) {
    lines.add('部分來源或作品有警告，請查看事件紀錄');
  }
  if (lines.isEmpty) return null;
  final limited = lines.take(12).toList(growable: true);
  if (lines.length > limited.length) {
    limited.add('其餘 ${lines.length - limited.length} 筆診斷請查看事件紀錄');
  }
  return limited.map((line) => ScrapeEventSanitizer.message(line)).join('\n');
}

String scrapeJobImageFailureMessage(WorksScrapeImageFailure failure) {
  final variants = failure.variants.map((variant) => variant.name).join('、');
  return '作品 ${failure.code}：圖片下載失敗（$variants）';
}

class ScrapeJobCoordinator extends ChangeNotifier {
  ScrapeJobCoordinator({
    required this.db,
    ScrapeJobRepository? repository,
    ScrapeRulesRepository? rulesRepository,
    WorksScrapeSessionFactory? sessionFactory,
    this.verificationHandler,
  }) : repository = repository ?? ScrapeJobRepository(db: db),
       rulesRepository = rulesRepository ?? ScrapeRulesRepository(db: db),
       sessionFactory = sessionFactory ?? WorksScrapeSessionFactory(db: db);

  final AppDatabase db;
  final ScrapeJobRepository repository;
  final ScrapeRulesRepository rulesRepository;
  final WorksScrapeSessionFactory sessionFactory;
  JavBusVerificationHandler? verificationHandler;

  bool _initialized = false;
  Future<void>? _initializationFuture;
  bool _pumpRunning = false;
  bool _pumpRequested = false;
  String? _runningJobId;
  final _tokens = <String, WorksScrapeCancellationToken>{};
  Future<void> _writeQueue = Future<void>.value();
  Timer? _notificationTimer;
  bool _disposed = false;

  Future<void> initialize() {
    final inFlight = _initializationFuture;
    if (inFlight != null) return inFlight;

    final future = _initializeOnce();
    _initializationFuture = future;
    return future;
  }

  Future<void> _initializeOnce() async {
    try {
      await repository.recoverInterruptedJobs();
      await rulesRepository.load();
      _initialized = true;
      _emitChanged();
      unawaited(
        rulesRepository.refreshIfDue().then((_) {
          if (_initialized) _scheduleChanged();
        }),
      );
      unawaited(_pump());
    } on Object {
      _initializationFuture = null;
      rethrow;
    }
  }

  Future<ScrapeJob> enqueue({
    required int actressId,
    required String actressName,
    required WorkScrapeOptions options,
    required ScrapeSourceSettings sourceSettings,
  }) async {
    await initialize();
    final job = await repository.create(
      actressId: actressId,
      actressName: actressName,
      optionsSnapshot: options.encode(),
      sourceSettingsSnapshot: sourceSettings.encode(),
      rulesVersionSnapshot: rulesRepository.current.rulesVersion,
      rulesSnapshot: rulesRepository.current.encode(),
    );
    _emitChanged();
    unawaited(_pump());
    return job;
  }

  Future<void> pause(String jobId) async {
    _tokens[jobId]?.pause();
    _emitChanged();
    final job = await repository.get(jobId);
    if (job == null || !job.isActive || job.state == ScrapeJobState.paused) {
      return;
    }
    await repository.updateJob(jobId, state: ScrapeJobState.paused);
    await repository.appendEvent(
      jobId,
      severity: ScrapeJobEventSeverity.info,
      stage: job.phase,
      message: '已要求暫停，會在目前安全檢查點停止',
    );
    _emitChanged();
  }

  Future<void> resume(String jobId) async {
    final job = await repository.get(jobId);
    if (job == null ||
        (job.state != ScrapeJobState.paused &&
            job.state != ScrapeJobState.waitingForVerification)) {
      return;
    }
    await repository.updateJob(
      jobId,
      state: ScrapeJobState.queued,
      phase: ScrapeJobPhase.queued,
      clearError: true,
    );
    await repository.appendEvent(
      jobId,
      severity: ScrapeJobEventSeverity.info,
      stage: ScrapeJobPhase.queued,
      message: '工作已恢復，等待執行',
    );
    _emitChanged();
    unawaited(_pump());
  }

  Future<void> cancel(String jobId) async {
    _tokens[jobId]?.cancel();
    _emitChanged();
    final job = await repository.get(jobId);
    if (job == null || !job.isActive) return;
    final now = DateTime.now().toUtc();
    await repository.updateJob(
      jobId,
      state: ScrapeJobState.cancelled,
      finishedAt: now,
      phase: ScrapeJobPhase.completed,
    );
    await repository.appendEvent(
      jobId,
      severity: ScrapeJobEventSeverity.warning,
      stage: job.phase,
      message: '工作已取消',
    );
    _emitChanged();
  }

  Future<void> retryFailed(String jobId) async {
    final items = await repository.listItems(jobId);
    final retryCodes = items
        .where((item) => item.state == ScrapeJobItemState.failed)
        .map((item) => item.canonicalCode)
        .toList(growable: false);
    final job = await repository.get(jobId);
    if (job == null || retryCodes.isEmpty) return;
    await repository.updateJob(
      jobId,
      state: ScrapeJobState.queued,
      phase: ScrapeJobPhase.queued,
      retryTargetCodes: retryCodes,
      clearError: true,
      clearFinishedAt: true,
    );
    for (final item in items.where(
      (item) => retryCodes.contains(item.canonicalCode),
    )) {
      await repository.upsertItem(
        ScrapeJobItem(
          id: item.id,
          jobId: item.jobId,
          canonicalCode: item.canonicalCode,
          observedRawCode: item.observedRawCode,
          state: ScrapeJobItemState.queued,
          stage: ScrapeJobPhase.queued,
          attemptCount: item.attemptCount,
          createdAt: item.createdAt,
          updatedAt: DateTime.now().toUtc(),
        ),
        existingId: item.id,
      );
    }
    await repository.appendEvent(
      jobId,
      severity: ScrapeJobEventSeverity.info,
      stage: ScrapeJobPhase.queued,
      message: '只重試失敗作品',
      metadata: {'count': retryCodes.length},
    );
    _emitChanged();
    unawaited(_pump());
  }

  Future<ScrapeJob?> latestForActress(int actressId) =>
      repository.findActiveForActress(actressId);

  Future<List<ScrapeJob>> listJobs() => repository.list();

  Future<void> deleteJobs(Iterable<String> ids) async {
    await initialize();
    await _drainWrites();
    await repository.deleteTerminalJobs(ids);
    _emitChanged();
  }

  Future<List<ScrapeJobEvent>> eventsFor(String jobId) =>
      repository.listEvents(jobId);

  Future<void> _pump() async {
    if (_disposed) return;
    _pumpRequested = true;
    if (_pumpRunning) return;
    _pumpRunning = true;
    try {
      while (_pumpRequested && !_disposed) {
        _pumpRequested = false;
        while (_runningJobId == null && !_disposed) {
          final jobs = await repository.list(limit: 100);
          final next = jobs.firstWhereOrNull(
            (job) => job.state == ScrapeJobState.queued,
          );
          if (next == null) break;
          _runningJobId = next.id;
          await _run(next);
          _runningJobId = null;
        }
      }
    } finally {
      _pumpRunning = false;
      if (_pumpRequested && !_disposed) {
        unawaited(_pump());
      }
    }
  }

  Future<void> _run(ScrapeJob queued) async {
    final now = DateTime.now().toUtc();
    final attempt = queued.attemptCount + 1;
    final token = WorksScrapeCancellationToken();
    _tokens[queued.id] = token;
    _JobObserver? observer;
    var workDataChanged = false;
    try {
      await repository.updateJob(
        queued.id,
        state: ScrapeJobState.running,
        phase: ScrapeJobPhase.collectingSources,
        attemptCount: attempt,
        startedAt: queued.startedAt ?? now,
        clearError: true,
      );
      _emitChanged();
      if (token.shouldStop) {
        await _persistControlState(queued.id, token);
        return;
      }
      observer = _JobObserver(
        repository,
        queued.id,
        ScrapeJobWriteFence(enqueue: _queueWrite, drain: _drainWrites),
      );
      final session = await sessionFactory.create(
        queued,
        verificationHandler: verificationHandler,
      );
      try {
        if (token.shouldStop) {
          await _persistControlState(queued.id, token);
          return;
        }
        final result = await session.service.scrape(
          actressId: queued.actressId,
          actressName: queued.actressNameSnapshot,
          aliases: await sessionFactory.aliasesFor(queued.actressId),
          options: WorkScrapeOptions.decode(queued.optionsSnapshot).copyWith(
            retryWorkCodes: queued.retryTargetCodes.isEmpty
                ? null
                : queued.retryTargetCodes,
          ),
          sourceSettings: ScrapeSourceSettings.decode(
            queued.sourceSettingsSnapshot,
          ),
          cancellationToken: token,
          observer: observer,
        );
        workDataChanged = true;
        for (final failure in result.failedWorks) {
          await observer.complete(
            failure.code,
            state: ScrapeJobItemState.failed,
            error: failure.error ?? failure.reason.name,
          );
        }
        for (final imageFailure in result.imageFailures) {
          await observer.complete(
            imageFailure.code,
            state: ScrapeJobItemState.succeeded,
            error: scrapeJobImageFailureMessage(imageFailure),
          );
        }
        final finalState = resolveScrapeJobFinalState(
          pauseRequested: token.isPauseRequested,
          cancelRequested: token.isCancelRequested,
          resultCancelled: result.cancelled,
          partialSuccess: result.partialSuccess,
        );
        final diagnostic = finalState == ScrapeJobState.partial
            ? buildScrapeJobResultDiagnostic(result)
            : null;
        final counters = ScrapeJobTerminalCounters.fromResult(result);
        observer.stopAccepting();
        await observer.drain();
        await _queueWrite(() async {
          await observer!.completeRemaining(
            finalState == ScrapeJobState.cancelled
                ? ScrapeJobItemState.cancelled
                : finalState == ScrapeJobState.paused
                ? ScrapeJobItemState.queued
                : ScrapeJobItemState.succeeded,
          );
          await repository.updateJob(
            queued.id,
            state: finalState,
            phase: ScrapeJobPhase.completed,
            processedCount: counters.processed,
            savedCount: counters.saved,
            excludedCount: counters.excluded,
            failedCount: counters.failed,
            imageFailureCount: counters.imageFailures,
            finishedAt: finalState == ScrapeJobState.paused
                ? null
                : DateTime.now().toUtc(),
            retryTargetCodes: const [],
            lastError: diagnostic,
            clearError: diagnostic == null,
          );
          await repository.appendEvent(
            queued.id,
            severity: finalState == ScrapeJobState.succeeded
                ? ScrapeJobEventSeverity.info
                : ScrapeJobEventSeverity.warning,
            stage: ScrapeJobPhase.completed,
            message: _resultMessage(finalState),
            metadata: {
              'saved': result.saved,
              'excluded': result.excluded,
              'failed': result.failed,
              'image_failures': result.imageFailures.length,
            },
          );
          if (diagnostic != null) {
            await repository.appendEvent(
              queued.id,
              severity: result.failed > 0
                  ? ScrapeJobEventSeverity.error
                  : ScrapeJobEventSeverity.warning,
              stage: ScrapeJobPhase.completed,
              message: '刮削診斷：$diagnostic',
            );
          }
        });
      } finally {
        if (session.javBusTransport?.cookieHeader.isNotEmpty == true) {
          await db.setSetting(
            'javbus_cookies',
            session.javBusTransport!.cookieHeader,
          );
        }
        session.service.close();
      }
    } on Object catch (error) {
      observer?.stopAccepting();
      await observer?.drain();
      final waiting =
          error is JavBusVerificationRequiredException ||
          error is JavBusVerificationCancelledException ||
          error.toString().toLowerCase().contains('verification');
      final state = token.isPauseRequested
          ? ScrapeJobState.paused
          : token.isCancelRequested
          ? ScrapeJobState.cancelled
          : waiting
          ? ScrapeJobState.waitingForVerification
          : ScrapeJobState.failed;
      workDataChanged = ScrapeJobRepository.terminalStates.contains(state);
      final safeError = ScrapeEventSanitizer.message(error);
      await _queueWrite(() async {
        await repository.updateJob(
          queued.id,
          state: state,
          phase: state == ScrapeJobState.waitingForVerification
              ? ScrapeJobPhase.collectingSources
              : ScrapeJobPhase.completed,
          lastError: state == ScrapeJobState.paused ? null : safeError,
          clearError: state == ScrapeJobState.paused,
          finishedAt:
              state == ScrapeJobState.paused ||
                  state == ScrapeJobState.waitingForVerification
              ? null
              : DateTime.now().toUtc(),
        );
        await repository.appendEvent(
          queued.id,
          severity: state == ScrapeJobState.failed
              ? ScrapeJobEventSeverity.error
              : ScrapeJobEventSeverity.warning,
          stage: ScrapeJobPhase.completed,
          message: waiting ? '需要完成來源驗證後才能繼續' : safeError,
        );
      });
    } finally {
      _tokens.remove(queued.id);
      _emitChanged(workDataChanged: workDataChanged);
    }
  }

  Future<void> _persistControlState(
    String jobId,
    WorksScrapeCancellationToken token,
  ) async {
    final cancelled = token.isCancelRequested;
    await repository.updateJob(
      jobId,
      state: cancelled ? ScrapeJobState.cancelled : ScrapeJobState.paused,
      phase: ScrapeJobPhase.completed,
      finishedAt: cancelled ? DateTime.now().toUtc() : null,
      clearError: !cancelled,
    );
  }

  Future<void> _queueWrite(Future<void> Function() operation) {
    final next = _writeQueue.then((_) async {
      await operation();
      _scheduleChanged();
    });
    _writeQueue = next.catchError((_) {});
    return next;
  }

  Future<void> _drainWrites() => _writeQueue;

  void _scheduleChanged() {
    if (_disposed || _notificationTimer != null) return;
    _notificationTimer = Timer(const Duration(milliseconds: 120), () {
      _notificationTimer = null;
      _emitChanged();
    });
  }

  int _workDataRevision = 0;

  int get workDataRevision => _workDataRevision;

  void _emitChanged({bool workDataChanged = false}) {
    if (_disposed) return;
    if (workDataChanged) _workDataRevision++;
    _notificationTimer?.cancel();
    _notificationTimer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _notificationTimer?.cancel();
    _notificationTimer = null;
    super.dispose();
  }

  String _resultMessage(ScrapeJobState state) => switch (state) {
    ScrapeJobState.succeeded => '刮削工作完成',
    ScrapeJobState.partial => '刮削工作部分完成',
    ScrapeJobState.cancelled => '刮削工作已取消',
    ScrapeJobState.paused => '刮削工作已暫停',
    _ => '刮削工作結束',
  };
}

class _JobObserver extends ScrapeRunObserver {
  _JobObserver(this.repository, this.jobId, this.writeFence);

  final ScrapeJobRepository repository;
  final String jobId;
  final ScrapeJobWriteFence writeFence;
  final _items = <String, int?>{};
  final _progress = ScrapeJobProgressAccumulator();
  bool _progressSeeded = false;
  bool _accepting = true;
  ScrapeJobPhase? _lastPhase;

  void stopAccepting() {
    _accepting = false;
    writeFence.stopAccepting();
  }

  Future<void> drain() => writeFence.drain();

  void _enqueue(Future<void> Function() operation) {
    if (!_accepting) return;
    writeFence.enqueue(operation);
  }

  Future<void> _ensureProgressState() async {
    if (_progressSeeded) return;
    final currentJob = await repository.get(jobId);
    if (currentJob != null) _progress.seed(currentJob);
    _progress.seedItems(await repository.listItems(jobId));
    _progressSeeded = true;
  }

  @override
  void onProgress(WorksScrapeProgress progress) {
    _enqueue(() async {
      await _ensureProgressState();
      _progress.apply(progress);
      await repository.updateJob(
        jobId,
        phase: _phase(progress.phase),
        discoveredCount: _progress.discoveredCount,
        processedCount: _progress.processedCount,
        savedCount: _progress.savedCount,
        excludedCount: _progress.excludedCount,
        failedCount: _progress.failedCount,
      );
      for (final entry in progress.sourceProgress.entries) {
        await repository.upsertSourceProgress(
          ScrapeJobSourceProgress(
            jobId: jobId,
            source: entry.key,
            phase: _phase(entry.value.phase),
            current: entry.value.current,
            total: entry.value.total,
            totalKnown: entry.value.totalKnown,
            workCode: entry.value.workCode,
          ),
        );
      }
      if (_lastPhase != _phase(progress.phase)) {
        _lastPhase = _phase(progress.phase);
        await repository.appendEvent(
          jobId,
          severity: ScrapeJobEventSeverity.info,
          stage: _lastPhase!,
          message: '刮削階段：${_lastPhase!.storageValue}',
        );
      }
      if (progress.workCode != null && progress.workCode!.trim().isNotEmpty) {
        await _setItem(
          progress.workCode!,
          state: ScrapeJobItemState.running,
          stage: _phase(progress.phase),
        );
      }
    });
  }

  @override
  void onWorkDiscovered({
    required String canonicalCode,
    String? rawCode,
    required ScrapeSourceId source,
  }) {
    _enqueue(
      () => _setItem(
        canonicalCode,
        rawCode: rawCode,
        state: ScrapeJobItemState.queued,
        stage: ScrapeJobPhase.fetchingDetails,
      ),
    );
  }

  @override
  void onWorkAttemptStarted({
    required String code,
    required ScrapeSourceId source,
  }) {
    _enqueue(
      () => _setItem(
        code,
        state: ScrapeJobItemState.running,
        stage: ScrapeJobPhase.fetchingDetails,
      ),
    );
  }

  @override
  void onWorkCompleted({
    required String code,
    required ScrapeSourceId source,
    required String state,
    Object? error,
  }) {
    if (state != 'details_ready') return;
    _enqueue(
      () => _setItem(
        code,
        state: ScrapeJobItemState.running,
        stage: ScrapeJobPhase.resolvingWorks,
      ),
    );
  }

  @override
  void onWorkOutcome({
    required String code,
    required ScrapeSourceId source,
    required ScrapeWorkOutcomeState outcome,
    Object? error,
    String? reason,
    Iterable<String> imageFailureVariants = const <String>[],
  }) {
    final imageVariants = imageFailureVariants.toList(growable: false);
    final diagnostic = error == null && reason == null && imageVariants.isEmpty
        ? null
        : error == null
        ? reason ?? '圖片下載失敗（${imageVariants.join('、')}）'
        : ScrapeEventSanitizer.message(error);
    final itemState = switch (outcome) {
      ScrapeWorkOutcomeState.saved => ScrapeJobItemState.succeeded,
      ScrapeWorkOutcomeState.excluded => ScrapeJobItemState.excluded,
      ScrapeWorkOutcomeState.failed => ScrapeJobItemState.failed,
      ScrapeWorkOutcomeState.cancelled => ScrapeJobItemState.cancelled,
    };
    _enqueue(() async {
      await _ensureProgressState();
      _progress.recordOutcome(code, outcome);
      await _setItem(
        code,
        state: itemState,
        stage: ScrapeJobPhase.completed,
        lastError: diagnostic,
      );
      await repository.updateJob(
        jobId,
        discoveredCount: _progress.discoveredCount,
        processedCount: _progress.processedCount,
        savedCount: _progress.savedCount,
        excludedCount: _progress.excludedCount,
        failedCount: _progress.failedCount,
      );
      if (diagnostic != null) {
        await repository.appendEvent(
          jobId,
          severity: outcome == ScrapeWorkOutcomeState.failed
              ? ScrapeJobEventSeverity.error
              : ScrapeJobEventSeverity.warning,
          stage: ScrapeJobPhase.completed,
          canonicalCode: code,
          source: source.storageValue,
          message: diagnostic,
        );
      }
    });
  }

  Future<void> complete(
    String code, {
    required ScrapeJobItemState state,
    Object? error,
  }) {
    if (!_accepting) return Future<void>.value();
    return writeFence.enqueue(
      () => _setItem(
        code,
        state: state,
        stage: ScrapeJobPhase.completed,
        lastError: error == null ? null : ScrapeEventSanitizer.message(error),
      ),
    );
  }

  Future<void> completeRemaining(ScrapeJobItemState state) async {
    final items = await repository.listItems(jobId);
    for (final item in items) {
      if (item.state == ScrapeJobItemState.failed ||
          item.state == ScrapeJobItemState.excluded ||
          item.state == ScrapeJobItemState.succeeded) {
        continue;
      }
      await _setItem(
        item.canonicalCode,
        state: state,
        stage: state == ScrapeJobItemState.queued
            ? ScrapeJobPhase.queued
            : ScrapeJobPhase.completed,
      );
    }
  }

  @override
  void onSourceResult(ScrapeSourceRunResult result) {
    if (result.error == null) return;
    _enqueue(
      () => repository.appendEvent(
        jobId,
        severity: ScrapeJobEventSeverity.warning,
        stage: ScrapeJobPhase.collectingSources,
        source: result.source.storageValue,
        message: ScrapeEventSanitizer.message(result.error),
      ),
    );
  }

  @override
  void onError({required String stage, Object? error, String? code}) {
    _enqueue(
      () => repository.appendEvent(
        jobId,
        severity: ScrapeJobEventSeverity.error,
        stage: ScrapeJobPhase.savingWorks,
        canonicalCode: code,
        message: ScrapeEventSanitizer.message(error),
      ),
    );
  }

  Future<void> _setItem(
    String code, {
    String? rawCode,
    required ScrapeJobItemState state,
    required ScrapeJobPhase stage,
    String? lastError,
  }) async {
    final existing = await repository.findItem(jobId, code);
    final item = ScrapeJobItem(
      id: existing?.id,
      jobId: jobId,
      canonicalCode: code,
      observedRawCode: rawCode ?? existing?.observedRawCode,
      state: state,
      stage: stage,
      attemptCount:
          (existing?.attemptCount ?? 0) +
          (state == ScrapeJobItemState.running ? 1 : 0),
      lastError: lastError,
      createdAt: existing?.createdAt ?? DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    final id = await repository.upsertItem(item, existingId: existing?.id);
    _items[code] = id;
  }

  ScrapeJobPhase _phase(WorksScrapePhase phase) => switch (phase) {
    WorksScrapePhase.collectingSources => ScrapeJobPhase.collectingSources,
    WorksScrapePhase.syncingActress => ScrapeJobPhase.syncingActress,
    WorksScrapePhase.fetchingDetails => ScrapeJobPhase.fetchingDetails,
    WorksScrapePhase.resolvingWorks => ScrapeJobPhase.resolvingWorks,
    WorksScrapePhase.savingWorks => ScrapeJobPhase.savingWorks,
    WorksScrapePhase.downloadingImages => ScrapeJobPhase.downloadingImages,
    WorksScrapePhase.completed => ScrapeJobPhase.completed,
  };
}

extension<T> on List<T> {
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}
