import 'dart:async';

import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/models/scrape_job.dart';
import 'package:avaca/services/scrape_job_coordinator.dart';
import 'package:avaca/services/scrape_job_repository.dart';
import 'package:avaca/views/scrape_job_detail_view.dart';
import 'package:avaca/views/scrape_jobs_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows partial diagnostic and keeps a large checkpoint list scrollable',
    (tester) async {
      final db = AppDatabase();
      final job = ScrapeJob(
        id: 'ui-test-job',
        actressId: 1,
        actressNameSnapshot: '測試女優',
        state: ScrapeJobState.partial,
        phase: ScrapeJobPhase.completed,
        optionsSnapshot: '{}',
        sourceSettingsSnapshot: '{}',
        rulesVersionSnapshot: 'builtin-1',
        rulesSnapshot: '{}',
        processedCount: 31,
        savedCount: 30,
        failedCount: 1,
        lastError: '來源 javbus：partial\n作品 BAD-001：detailsUnavailable',
      );
      final now = DateTime.now().toUtc();
      final items = List<ScrapeJobItem>.generate(31, (index) {
        final failed = index == 30;
        return ScrapeJobItem(
          id: index + 1,
          jobId: job.id,
          canonicalCode: failed ? 'BAD-001' : 'OK-${index + 1}',
          state: failed
              ? ScrapeJobItemState.failed
              : ScrapeJobItemState.succeeded,
          stage: ScrapeJobPhase.completed,
          lastError: failed ? 'detailsUnavailable' : null,
          createdAt: now,
          updatedAt: now,
        );
      });

      final repository = _FakeScrapeJobRepository(
        db: db,
        job: job,
        items: items,
      );
      final coordinator = ScrapeJobCoordinator(db: db, repository: repository);
      addTearDown(coordinator.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ScrapeJobDetailView(
            db: db,
            coordinator: coordinator,
            jobId: job.id,
          ),
        ),
      );
      await tester.pump();
      for (var index = 0; index < 12; index++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byKey(const Key('scrape-job-diagnostic')), findsOneWidget);
      expect(find.textContaining('BAD-001'), findsWidgets);
      expect(find.byKey(const Key('scrape-job-items-list')), findsOneWidget);
      final viewport = tester.getSize(
        find.byKey(const Key('scrape-job-items-viewport')),
      );
      expect(viewport.height, lessThanOrEqualTo(480));
    },
  );

  testWidgets('detail view ignores an out-of-order stale read', (tester) async {
    final db = AppDatabase();
    final staleRead = Completer<ScrapeJob?>();
    final oldJob = _job(id: 'old-job', name: '舊女優');
    final currentJob = _job(id: 'current-job', name: '新女優');
    final repository = _FakeScrapeJobRepository(
      db: db,
      job: currentJob,
      getResponses: [staleRead.future, Future.value(currentJob)],
    );
    final coordinator = ScrapeJobCoordinator(db: db, repository: repository);
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      _testApp(
        ScrapeJobDetailView(
          db: db,
          coordinator: coordinator,
          jobId: currentJob.id,
        ),
      ),
    );
    await tester.pump();
    coordinator.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('新女優'), findsOneWidget);
    staleRead.complete(oldJob);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('新女優'), findsOneWidget);
    expect(find.text('舊女優'), findsNothing);
  });

  testWidgets('jobs view ignores an out-of-order stale read', (tester) async {
    final db = AppDatabase();
    final staleRead = Completer<List<ScrapeJob>>();
    final oldJob = _job(id: 'old-job', name: '舊女優');
    final currentJob = _job(id: 'current-job', name: '新女優');
    final repository = _FakeScrapeJobRepository(
      db: db,
      job: currentJob,
      listResponses: [
        staleRead.future,
        Future.value([currentJob]),
      ],
    );
    final coordinator = ScrapeJobCoordinator(db: db, repository: repository);
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      _testApp(ScrapeJobsView(db: db, coordinator: coordinator)),
    );
    await tester.pump();
    coordinator.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('新女優'), findsOneWidget);
    staleRead.complete([oldJob]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('新女優'), findsOneWidget);
    expect(find.text('舊女優'), findsNothing);
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

ScrapeJob _job({required String id, required String name}) {
  return ScrapeJob(
    id: id,
    actressId: 1,
    actressNameSnapshot: name,
    state: ScrapeJobState.running,
    phase: ScrapeJobPhase.savingWorks,
    optionsSnapshot: '{}',
    sourceSettingsSnapshot: '{}',
    rulesVersionSnapshot: 'builtin-1',
    rulesSnapshot: '{}',
  );
}

class _FakeScrapeJobRepository extends ScrapeJobRepository {
  _FakeScrapeJobRepository({
    required super.db,
    required this.job,
    this.items = const [],
    List<Future<ScrapeJob?>> getResponses = const [],
    List<Future<List<ScrapeJob>>> listResponses = const [],
  }) : getResponses = List<Future<ScrapeJob?>>.of(getResponses),
       listResponses = List<Future<List<ScrapeJob>>>.of(listResponses);

  final ScrapeJob job;
  final List<ScrapeJobItem> items;
  final List<Future<ScrapeJob?>> getResponses;
  final List<Future<List<ScrapeJob>>> listResponses;

  @override
  Future<ScrapeJob?> get(String id) async {
    if (getResponses.isNotEmpty) return getResponses.removeAt(0);
    return id == job.id ? job : null;
  }

  @override
  Future<List<ScrapeJob>> list({int? actressId, int limit = 100}) async {
    if (listResponses.isNotEmpty) return listResponses.removeAt(0);
    return [job];
  }

  @override
  Future<List<ScrapeJobItem>> listItems(String jobId) async =>
      jobId == job.id ? items : const [];

  @override
  Future<List<ScrapeJobEvent>> listEvents(
    String jobId, {
    int limit = 200,
  }) async => const [];
}
