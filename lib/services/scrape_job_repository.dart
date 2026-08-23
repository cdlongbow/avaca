import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../core/database.dart';
import '../models/scrape_job.dart';
import 'scrape_event_sanitizer.dart';

class ScrapeJobRepository {
  ScrapeJobRepository({required this.db});

  final AppDatabase db;
  static const activeStates = <ScrapeJobState>{
    ScrapeJobState.queued,
    ScrapeJobState.running,
    ScrapeJobState.paused,
    ScrapeJobState.waitingForVerification,
  };
  static const terminalStates = <ScrapeJobState>{
    ScrapeJobState.succeeded,
    ScrapeJobState.partial,
    ScrapeJobState.failed,
    ScrapeJobState.cancelled,
  };

  Future<ScrapeJob?> get(String id) async {
    final database = await db.database;
    final rows = await database.query(
      'scrape_jobs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ScrapeJob.fromRow(rows.first);
  }

  Future<List<ScrapeJob>> list({int? actressId, int limit = 100}) async {
    final database = await db.database;
    final rows = await database.query(
      'scrape_jobs',
      where: actressId == null ? null : 'actress_id = ?',
      whereArgs: actressId == null ? null : [actressId],
      orderBy: 'updated_at DESC, created_at DESC',
      limit: limit.clamp(1, 500),
    );
    return rows.map(ScrapeJob.fromRow).toList(growable: false);
  }

  Future<void> deleteTerminalJobs(Iterable<String> ids) async {
    final jobIds = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (jobIds.isEmpty) return;

    final database = await db.database;
    await database.transaction((transaction) async {
      final placeholders = List.filled(jobIds.length, '?').join(', ');
      final rows = await transaction.query(
        'scrape_jobs',
        columns: const ['id', 'state'],
        where: 'id IN ($placeholders)',
        whereArgs: jobIds,
      );
      if (rows.length != jobIds.length ||
          rows.any(
            (row) => !terminalStates.contains(
              ScrapeJobStateCodec.parse(row['state']),
            ),
          )) {
        throw StateError('Only terminal scrape jobs can be deleted.');
      }

      await transaction.delete(
        'scrape_jobs',
        where: 'id IN ($placeholders)',
        whereArgs: jobIds,
      );
    });
  }

  Future<ScrapeJob?> findActiveForActress(int actressId) async {
    final database = await db.database;
    final rows = await database.rawQuery(
      '''
      SELECT * FROM scrape_jobs
      WHERE actress_id = ? AND state IN (?, ?, ?, ?)
      ORDER BY updated_at DESC, created_at DESC
      LIMIT 1
      ''',
      [actressId, ...activeStates.map((state) => state.storageValue)],
    );
    return rows.isEmpty ? null : ScrapeJob.fromRow(rows.first);
  }

  Future<ScrapeJob> create({
    required int actressId,
    required String actressName,
    required String optionsSnapshot,
    required String sourceSettingsSnapshot,
    required String rulesVersionSnapshot,
    required String rulesSnapshot,
    List<String> retryTargetCodes = const [],
  }) async {
    final existing = await findActiveForActress(actressId);
    if (existing != null) return existing;
    final now = DateTime.now().toUtc();
    final job = ScrapeJob(
      id: _newId(actressId),
      actressId: actressId,
      actressNameSnapshot: actressName.trim(),
      state: ScrapeJobState.queued,
      phase: ScrapeJobPhase.queued,
      optionsSnapshot: optionsSnapshot,
      sourceSettingsSnapshot: sourceSettingsSnapshot,
      rulesVersionSnapshot: rulesVersionSnapshot,
      rulesSnapshot: rulesSnapshot,
      retryTargetCodes: List.unmodifiable(retryTargetCodes),
      createdAt: now,
      updatedAt: now,
    );
    final database = await db.database;
    await database.insert('scrape_jobs', job.toRow());
    await appendEvent(
      job.id,
      severity: ScrapeJobEventSeverity.info,
      stage: ScrapeJobPhase.queued,
      message: '刮削工作已排入佇列',
    );
    await retainRecent();
    return job;
  }

  Future<void> updateJob(
    String id, {
    ScrapeJobState? state,
    ScrapeJobPhase? phase,
    int? discoveredCount,
    int? processedCount,
    int? savedCount,
    int? excludedCount,
    int? failedCount,
    int? imageFailureCount,
    int? attemptCount,
    List<String>? retryTargetCodes,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? lastError,
    bool clearError = false,
    bool clearFinishedAt = false,
  }) async {
    final database = await db.database;
    final values = <String, Object?>{
      if (state != null) 'state': state.storageValue,
      if (phase != null) 'phase': phase.storageValue,
      if (discoveredCount != null) 'discovered_count': discoveredCount,
      if (processedCount != null) 'processed_count': processedCount,
      if (savedCount != null) 'saved_count': savedCount,
      if (excludedCount != null) 'excluded_count': excludedCount,
      if (failedCount != null) 'failed_count': failedCount,
      if (imageFailureCount != null) 'image_failure_count': imageFailureCount,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (retryTargetCodes != null)
        'retry_target_codes': jsonEncode(retryTargetCodes),
      if (startedAt != null) 'started_at': startedAt.toUtc().toIso8601String(),
      if (finishedAt != null)
        'finished_at': finishedAt.toUtc().toIso8601String(),
      if (clearFinishedAt) 'finished_at': null,
      if (clearError) 'last_error': null,
      if (lastError != null) 'last_error': lastError,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (values.length == 1) return;
    await database.update(
      'scrape_jobs',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int?> upsertItem(ScrapeJobItem item, {int? existingId}) async {
    final database = await db.database;
    final values = item.toRow();
    if (existingId != null) {
      values.remove('id');
      await database.update(
        'scrape_job_items',
        values,
        where: 'id = ?',
        whereArgs: [existingId],
      );
      return existingId;
    }
    final id = await database.insert(
      'scrape_job_items',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }

  Future<ScrapeJobItem?> findItem(String jobId, String canonicalCode) async {
    final database = await db.database;
    final rows = await database.query(
      'scrape_job_items',
      where: 'job_id = ? AND canonical_code = ?',
      whereArgs: [jobId, canonicalCode],
      limit: 1,
    );
    return rows.isEmpty ? null : ScrapeJobItem.fromRow(rows.first);
  }

  Future<List<ScrapeJobItem>> listItems(String jobId) async {
    final database = await db.database;
    final rows = await database.query(
      'scrape_job_items',
      where: 'job_id = ?',
      whereArgs: [jobId],
      orderBy: 'canonical_code COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(ScrapeJobItem.fromRow).toList(growable: false);
  }

  Future<void> upsertSourceProgress(ScrapeJobSourceProgress progress) async {
    final database = await db.database;
    await database.insert(
      'scrape_job_source_progress',
      progress.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ScrapeJobSourceProgress>> listSourceProgress(String jobId) async {
    final database = await db.database;
    final rows = await database.query(
      'scrape_job_source_progress',
      where: 'job_id = ?',
      whereArgs: [jobId],
      orderBy: 'source ASC',
    );
    return rows.map(ScrapeJobSourceProgress.fromRow).toList(growable: false);
  }

  Future<int> appendEvent(
    String jobId, {
    required ScrapeJobEventSeverity severity,
    required ScrapeJobPhase stage,
    required String message,
    int? itemId,
    String? canonicalCode,
    String? source,
    Map<String, Object?> metadata = const {},
  }) async {
    final database = await db.database;
    return database.insert('scrape_job_events', {
      'job_id': jobId,
      'item_id': itemId,
      'canonical_code': canonicalCode,
      'source': source,
      'severity': severity.storageValue,
      'stage': stage.storageValue,
      'message': ScrapeEventSanitizer.message(message),
      'metadata_json': jsonEncode(ScrapeEventSanitizer.metadata(metadata)),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<ScrapeJobEvent>> listEvents(
    String jobId, {
    int limit = 200,
  }) async {
    final database = await db.database;
    final rows = await database.query(
      'scrape_job_events',
      where: 'job_id = ?',
      whereArgs: [jobId],
      orderBy: 'created_at DESC, id DESC',
      limit: limit.clamp(1, 1000),
    );
    return rows.map(ScrapeJobEvent.fromRow).toList(growable: false);
  }

  Future<List<WorkFieldProvenance>> listWorkProvenance(int workId) async {
    final database = await db.database;
    final rows = await database.query(
      'work_field_provenance',
      where: 'work_id = ?',
      whereArgs: [workId],
      orderBy: 'field ASC',
    );
    return rows.map(WorkFieldProvenance.fromRow).toList(growable: false);
  }

  Future<int> recoverInterruptedJobs() async {
    final database = await db.database;
    final rows = await database.query(
      'scrape_jobs',
      columns: const ['id'],
      where: 'state = ?',
      whereArgs: [ScrapeJobState.running.storageValue],
    );
    for (final row in rows) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      await updateJob(
        id,
        state: ScrapeJobState.queued,
        phase: ScrapeJobPhase.queued,
      );
      await appendEvent(
        id,
        severity: ScrapeJobEventSeverity.warning,
        stage: ScrapeJobPhase.queued,
        message: '上次程序結束時工作未完成，已安全重新排隊',
      );
    }
    return rows.length;
  }

  Future<void> retainRecent({int limit = 100}) async {
    final database = await db.database;
    final rows = await database.rawQuery(
      '''
      SELECT id FROM scrape_jobs
      WHERE state IN (?, ?, ?, ?)
      ORDER BY finished_at DESC, updated_at DESC, created_at DESC
      LIMIT -1 OFFSET ?
      ''',
      [
        ...terminalStates.map((state) => state.storageValue),
        limit.clamp(1, 500),
      ],
    );
    for (final row in rows) {
      final id = row['id']?.toString();
      if (id != null) {
        await database.delete('scrape_jobs', where: 'id = ?', whereArgs: [id]);
      }
    }
  }

  String _newId(int actressId) {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final suffix = Random().nextInt(1 << 20).toRadixString(16).padLeft(5, '0');
    return 'scrape-$actressId-$now-$suffix';
  }
}
