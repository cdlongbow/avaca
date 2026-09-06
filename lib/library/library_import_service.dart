import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../models/work.dart';
import '../services/scrape/scrape_models.dart';
import 'library_exact_resolver.dart';
import 'library_filesystem.dart';
import 'library_image_downloader.dart';
import 'library_info_store.dart';
import 'library_media_probe.dart';
import 'library_models.dart';
import 'library_repository.dart';
import 'library_source_access.dart';

class LibraryPlanIssue {
  const LibraryPlanIssue({
    required this.sourcePath,
    required this.code,
    required this.message,
  });

  final String sourcePath;
  final String? code;
  final String message;

  @override
  String toString() => '${code ?? path.basename(sourcePath)}: $message';
}

class LibraryImportPlanItem {
  const LibraryImportPlanItem({
    required this.entry,
    required this.details,
    required this.sourceSnapshot,
    required this.sourceSha256,
    required this.mediaProbe,
    required this.workPortableId,
    required this.mediaPortableId,
    required this.primaryActressName,
    required this.primaryActressId,
    required this.performers,
    required this.destinationRelativePath,
    required this.normalizedFileName,
    this.itemIndex = 1,
  });

  final LibraryScanEntry entry;
  final ScrapeWorkDetails details;
  final LibrarySourceSnapshot sourceSnapshot;
  final String sourceSha256;
  final MediaProbeResult mediaProbe;
  final String workPortableId;
  final String mediaPortableId;
  final String primaryActressName;
  final String primaryActressId;
  final List<Map<String, Object?>> performers;
  final String destinationRelativePath;
  final String normalizedFileName;
  final int itemIndex;

  Map<String, Object?> toJournalJson() => {
    'code': details.code,
    'sourcePath': entry.sourcePath,
    'source': entry.sourceLocator.toJson(),
    'originalFileName': entry.originalFileName,
    'workPortableId': workPortableId,
    'mediaPortableId': mediaPortableId,
    'primaryActressName': primaryActressName,
    'primaryActressId': primaryActressId,
    'performers': performers,
    'destinationRelativePath': destinationRelativePath,
    'normalizedFileName': normalizedFileName,
    'itemIndex': itemIndex,
    'sourceSha256': sourceSha256,
    'sourceSizeBytes': sourceSnapshot.sizeBytes,
    'sourceModifiedAt': sourceSnapshot.modifiedAt?.toUtc().toIso8601String(),
    'sourceCreatedAt': sourceSnapshot.createdAt?.toUtc().toIso8601String(),
    'parserVersion': entry.parseResult.parserVersion,
    'mediaProbe': mediaProbe.toJson(),
  };
}

class _SourceMediaInspection {
  const _SourceMediaInspection({required this.sha256, required this.probe});

  final String sha256;
  final MediaProbeResult probe;
}

class LibraryImportPlan {
  const LibraryImportPlan({
    required this.sourceFolder,
    required this.libraryRoot,
    required this.items,
    required this.issues,
    required this.fingerprint,
    this.revision = 0,
    this.totalSelected = 0,
    this.sourceLocator,
  });

  final String sourceFolder;
  final String libraryRoot;
  final List<LibraryImportPlanItem> items;
  final List<LibraryPlanIssue> issues;
  final String fingerprint;
  final int revision;
  final int totalSelected;
  final LibrarySourceLocator? sourceLocator;

  int get progressItemCount => totalSelected > 0 ? totalSelected : items.length;

  bool get isUsable => items.isNotEmpty && issues.isEmpty;
}

class LibraryPreflightItem {
  const LibraryPreflightItem({
    required this.item,
    required this.duplicateMedia,
    this.error,
  });

  final LibraryImportPlanItem item;
  final bool duplicateMedia;
  final String? error;

  bool get isReady => error == null;
}

class LibraryPreflightReport {
  const LibraryPreflightReport({
    required this.items,
    required this.errors,
    required this.diskSpaceChecked,
    this.planFingerprint = '',
    this.revision = 0,
  });

  final List<LibraryPreflightItem> items;
  final List<LibraryPlanIssue> errors;
  final bool diskSpaceChecked;
  final String planFingerprint;
  final int revision;

  bool get isReady => errors.isEmpty && items.every((item) => item.isReady);

  bool get hasReadyItems => items.any((item) => item.isReady);
}

enum LibraryImportResultState {
  succeeded,
  duplicateMedia,
  failed,
  cancelled,
  repairRequired,
}

class LibraryImportItemResult {
  const LibraryImportItemResult({
    required this.code,
    required this.sourcePath,
    required this.state,
    required this.message,
  });

  final String code;
  final String sourcePath;
  final LibraryImportResultState state;
  final String message;
}

class LibraryImportBatchResult {
  const LibraryImportBatchResult({
    required this.operationId,
    required this.items,
    this.planIssues = const [],
  });

  final String operationId;
  final List<LibraryImportItemResult> items;
  final List<LibraryPlanIssue> planIssues;

  int get succeededCount => items
      .where((item) => item.state == LibraryImportResultState.succeeded)
      .length;
  int get duplicateCount => items
      .where((item) => item.state == LibraryImportResultState.duplicateMedia)
      .length;
  int get failedCount =>
      items
          .where((item) => item.state == LibraryImportResultState.failed)
          .length +
      planIssues.length;
}

typedef LibraryPrimaryActressSelector =
    String? Function(ScrapeWorkDetails details);

enum LibraryImportProgressPhase {
  resolving,
  hashing,
  probing,
  preflight,
  staging,
  copying,
  verifying,
  portableCommit,
  indexing,
  linking,
  sourceCleanup,
  succeeded,
  duplicate,
  failed,
  cancelled,
  repairRequired,
}

class LibraryImportProgress {
  const LibraryImportProgress({
    required this.itemIndex,
    required this.itemCount,
    required this.code,
    required this.sourceFileName,
    required this.phase,
    this.resultState,
  });

  final int itemIndex;
  final int itemCount;
  final String code;
  final String sourceFileName;
  final LibraryImportProgressPhase phase;
  final LibraryImportResultState? resultState;

  bool get isTerminal => resultState != null;
}

typedef LibraryProgressCallback = void Function(LibraryImportProgress progress);

/// Coordinates the confirmed scrape -> probe -> preflight -> filesystem
/// journal -> portable index pipeline.
class LibraryImportService {
  LibraryImportService({
    required this.repository,
    required this.resolver,
    required this.mediaProbe,
    required this.filesystem,
    required this.shortcutManager,
    this.sourceAccess,
    LibraryImageDownloader? imageDownloader,
    LibraryInfoStore? infoStore,
    PortableIdGenerator? idGenerator,
    this.diskSpaceChecker,
  }) : imageDownloader = imageDownloader ?? const NoopLibraryImageDownloader(),
       infoStore = infoStore ?? LibraryInfoStore(filesystem: filesystem),
       idGenerator = idGenerator ?? PortableIdGenerator();

  final LibraryRepository repository;
  final LibraryExactWorkResolver resolver;
  final LibraryMediaProbe mediaProbe;
  final LibraryFilesystem filesystem;
  final LibraryShortcutManager shortcutManager;
  final LibrarySourceAccess? sourceAccess;
  final LibraryImageDownloader imageDownloader;
  final LibraryInfoStore infoStore;
  final PortableIdGenerator idGenerator;
  final Future<bool> Function(String root, int requiredBytes)? diskSpaceChecker;

  Future<LibraryImportPlan> buildPlan({
    required String sourceFolder,
    required String libraryRoot,
    LibrarySourceLocator? sourceLocator,
    required Iterable<LibraryScanEntry> selectedEntries,
    LibraryPrimaryActressSelector? primaryActressSelector,
    int revision = 0,
    bool allowImplicitPrimary = false,
    LibraryProgressCallback? onProgress,
  }) async {
    final effectiveSourceLocator =
        sourceLocator ?? LibraryPathSourceLocator(sourceFolder);
    final isExternalSource =
        effectiveSourceLocator is LibraryAndroidTreeSourceLocator;
    if (isExternalSource && sourceAccess == null) {
      throw const LibrarySourceAccessException(
        'Android source access is not configured',
      );
    }
    final source = isExternalSource
        ? effectiveSourceLocator.displayName
        : filesystem.absolutePath(sourceFolder);
    final root = filesystem.absolutePath(libraryRoot);
    filesystem.validateRoot(root);
    await filesystem.validateNoSymbolicLinks(root, root);
    if (!isExternalSource) {
      filesystem.validateRoot(source);
      await filesystem.validateNoSymbolicLinks(source, source);
      if (filesystem.samePath(source, root) ||
          filesystem.isWithin(source, root) ||
          filesystem.isWithin(root, source)) {
        throw const LibraryFilesystemException(
          'source folder and library root must not overlap',
        );
      }
    }
    final issues = <LibraryPlanIssue>[];
    final items = <LibraryImportPlanItem>[];
    final workIdsByCode = <String, String>{};
    final primaryByCode = <String, String>{};
    final actressIdsByName = <String, String>{};
    final resolutionsByCode = <String, LibraryResolutionResult>{};
    final selected = selectedEntries.where((entry) => entry.selected).toList();
    for (
      var selectedIndex = 0;
      selectedIndex < selected.length;
      selectedIndex++
    ) {
      final entry = selected[selectedIndex];
      final parsed = entry.parseResult;
      final progressCode = parsed.normalizedCode ?? entry.originalFileName;
      _emitProgress(
        onProgress,
        itemIndex: selectedIndex + 1,
        itemCount: selected.length,
        code: progressCode,
        sourceFileName: entry.originalFileName,
        phase: LibraryImportProgressPhase.resolving,
      );
      if (!parsed.isImportable || parsed.normalizedCode == null) {
        issues.add(
          LibraryPlanIssue(
            sourcePath: entry.sourcePath,
            code: parsed.normalizedCode,
            message: parsed.diagnostic,
          ),
        );
        _emitProgress(
          onProgress,
          itemIndex: selectedIndex + 1,
          itemCount: selected.length,
          code: progressCode,
          sourceFileName: entry.originalFileName,
          phase: LibraryImportProgressPhase.failed,
          resultState: LibraryImportResultState.failed,
        );
        continue;
      }
      final code = parsed.normalizedCode!;
      try {
        final resolution = resolutionsByCode[code] ??= await resolver.resolve(
          code,
        );
        final details = resolution.details;
        if (details == null) {
          throw StateError(
            'exact work resolution failed${resolution.diagnostics.isEmpty ? '' : ': ${resolution.diagnostics.join('; ')}'}',
          );
        }
        if (details.code.trim().toUpperCase() != code) {
          throw StateError('resolved code does not exactly match $code');
        }
        final rawPerformers = details.performers ?? const <WorkPerformer>[];
        final performerNames = <String>[];
        final seenPerformerNames = <String>{};
        for (final performer in rawPerformers) {
          final name = performer.name.trim();
          if (name.isNotEmpty && seenPerformerNames.add(name.toLowerCase())) {
            performerNames.add(name);
          }
        }
        final selectedPrimary = primaryActressSelector?.call(details)?.trim();
        final primaryName = (selectedPrimary == null || selectedPrimary.isEmpty)
            ? (allowImplicitPrimary || performerNames.length == 1
                  ? performerNames.firstOrNull
                  : null)
            : selectedPrimary;
        if (primaryName == null || primaryName.isEmpty) {
          throw StateError(
            performerNames.length > 1
                ? 'multiple performers require an explicit primary actress'
                : 'performer resolution returned no primary actress',
          );
        }
        if (!seenPerformerNames.contains(primaryName.toLowerCase())) {
          throw StateError(
            'selected primary actress is not a resolved performer',
          );
        }
        performerNames.removeWhere(
          (name) => name.toLowerCase() == primaryName.toLowerCase(),
        );
        performerNames.insert(0, primaryName);
        final previousPrimary = primaryByCode[code];
        if (previousPrimary != null &&
            previousPrimary.toLowerCase() != primaryName.toLowerCase()) {
          throw StateError('same Work has conflicting primary actresses');
        }
        primaryByCode[code] = primaryName;

        _emitProgress(
          onProgress,
          itemIndex: selectedIndex + 1,
          itemCount: selected.length,
          code: code,
          sourceFileName: entry.originalFileName,
          phase: LibraryImportProgressPhase.hashing,
        );
        final sourceSnapshot = await _snapshotSource(entry);
        final inspection = await _inspectSource(
          entry: entry,
          expectedSnapshot: sourceSnapshot,
        );
        final sourceHash = inspection.sha256;
        _emitProgress(
          onProgress,
          itemIndex: selectedIndex + 1,
          itemCount: selected.length,
          code: code,
          sourceFileName: entry.originalFileName,
          phase: LibraryImportProgressPhase.probing,
        );
        final probe = inspection.probe;
        if (!probe.isUsable) {
          throw StateError(
            'media probe failed: ${probe.error ?? 'required stream metadata is missing'}',
          );
        }
        final primaryId = await _portableActressId(
          primaryName,
          actressIdsByName,
        );
        final performerRecords = <Map<String, Object?>>[];
        for (final performer in rawPerformers) {
          final name = performer.name.trim();
          if (name.isEmpty) continue;
          performerRecords.add({
            'actressId': await _portableActressId(name, actressIdsByName),
            'name': name,
            'sourceUri': performer.sourceUri?.toString(),
          });
        }
        if (!performerRecords.any(
          (record) =>
              record['actressId'] == primaryId ||
              record['name']?.toString().toLowerCase() ==
                  primaryName.toLowerCase(),
        )) {
          performerRecords.insert(0, {
            'actressId': primaryId,
            'name': primaryName,
          });
        }
        final workPortableId =
            workIdsByCode[code] ??
            await repository.findWorkPortableIdByCode(code) ??
            idGenerator.next();
        workIdsByCode[code] = workPortableId;
        final destinationRelativePath =
            '${filesystem.safeSegment(primaryName)}/${filesystem.safeSegment(code)}';
        final normalizedFileName = _normalizedFileName(parsed, code);
        items.add(
          LibraryImportPlanItem(
            entry: entry,
            details: details,
            sourceSnapshot: sourceSnapshot,
            sourceSha256: sourceHash,
            mediaProbe: probe,
            workPortableId: workPortableId,
            mediaPortableId: idGenerator.next(),
            primaryActressName: primaryName,
            primaryActressId: primaryId,
            performers: List.unmodifiable(performerRecords),
            destinationRelativePath: destinationRelativePath,
            normalizedFileName: normalizedFileName,
            itemIndex: selectedIndex + 1,
          ),
        );
      } on Object catch (error) {
        issues.add(
          LibraryPlanIssue(
            sourcePath: entry.sourcePath,
            code: code,
            message: '$error',
          ),
        );
        _emitProgress(
          onProgress,
          itemIndex: selectedIndex + 1,
          itemCount: selected.length,
          code: code,
          sourceFileName: entry.originalFileName,
          phase: LibraryImportProgressPhase.failed,
          resultState: LibraryImportResultState.failed,
        );
      }
    }
    final fingerprintInput = <String, Object?>{
      'sourceFolder': source,
      'sourceLocator': effectiveSourceLocator.toJson(),
      'libraryRoot': root,
      'revision': revision,
      'items': items
          .map((item) => item.toJournalJson())
          .toList(growable: false),
    };
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(fingerprintInput)))
        .toString();
    return LibraryImportPlan(
      sourceFolder: source,
      libraryRoot: root,
      items: List.unmodifiable(items),
      issues: List.unmodifiable(issues),
      fingerprint: fingerprint,
      revision: revision,
      totalSelected: selected.length,
      sourceLocator: effectiveSourceLocator,
    );
  }

  Future<LibraryPreflightReport> preflight(
    LibraryImportPlan plan, {
    LibraryProgressCallback? onProgress,
  }) async {
    final errors = <LibraryPlanIssue>[];
    final preflightItems = <LibraryPreflightItem>[];
    final destinationFiles = <String, LibraryImportPlanItem>{};
    final plannedHashes = <String>{};
    var requiredBytes = 0;
    for (final item in plan.items) {
      _emitProgress(
        onProgress,
        itemIndex: item.itemIndex,
        itemCount: plan.progressItemCount,
        code: item.details.code,
        sourceFileName: item.entry.originalFileName,
        phase: LibraryImportProgressPhase.preflight,
      );
      String? error;
      var duplicate = false;
      try {
        final current = await _snapshotSource(item.entry);
        if (!current.matches(item.sourceSnapshot)) {
          error = 'source file changed after scan/plan';
        }
        requiredBytes += item.sourceSnapshot.sizeBytes;
        final destination = path.normalize(
          path.join(
            plan.libraryRoot,
            item.destinationRelativePath.replaceAll('/', path.separator),
            item.normalizedFileName,
          ),
        );
        if (!filesystem.isWithin(plan.libraryRoot, destination)) {
          error = 'destination escapes Library Root';
        }
        await filesystem.validateNoSymbolicLinks(plan.libraryRoot, destination);
        final previous = destinationFiles[destination.toLowerCase()];
        if (previous != null) {
          if (previous.sourceSha256 != item.sourceSha256) {
            error = 'normalized filename collision in import plan';
          } else {
            duplicate = true;
          }
        }
        destinationFiles[destination.toLowerCase()] = item;
        if (!plannedHashes.add(item.sourceSha256)) {
          duplicate = true;
        }
        if (await repository.hasMediaHash(item.sourceSha256)) {
          duplicate = true;
        }
        final destinationFile = File(destination);
        if (await destinationFile.exists()) {
          final destinationHash = await filesystem.hashFile(destination);
          if (destinationHash == item.sourceSha256) {
            duplicate = true;
          } else {
            error =
                'destination media filename already contains different content';
          }
        }
        final destinationDirectory = Directory(path.dirname(destination));
        if (await destinationDirectory.exists()) {
          final info = File(path.join(destinationDirectory.path, 'info.json'));
          if (!await info.exists() &&
              await destinationDirectory.list().isEmpty) {
            // An empty directory is safe to use; non-empty directories without
            // portable info are protected from accidental adoption.
          } else if (!await info.exists()) {
            error = 'destination folder exists without portable info.json';
          } else {
            final document = await infoStore.read(info);
            if (document.code.trim().toUpperCase() !=
                item.details.code.trim().toUpperCase()) {
              error = 'destination info.json belongs to a different Work';
            }
          }
        }
      } on Object catch (caught) {
        error ??= '$caught';
      }
      preflightItems.add(
        LibraryPreflightItem(
          item: item,
          duplicateMedia: duplicate,
          error: error,
        ),
      );
      if (error != null) {
        errors.add(
          LibraryPlanIssue(
            sourcePath: item.entry.sourcePath,
            code: item.details.code,
            message: error,
          ),
        );
      }
    }
    var diskSpaceChecked = false;
    if (diskSpaceChecker != null) {
      diskSpaceChecked = true;
      if (!await diskSpaceChecker!(plan.libraryRoot, requiredBytes)) {
        errors.add(
          const LibraryPlanIssue(
            sourcePath: '',
            code: null,
            message: 'Library Root does not have enough free space',
          ),
        );
      }
    }
    try {
      await _assertWritable(plan.libraryRoot);
    } on Object catch (error) {
      errors.add(
        LibraryPlanIssue(
          sourcePath: plan.libraryRoot,
          code: null,
          message: '$error',
        ),
      );
    }
    return LibraryPreflightReport(
      items: List.unmodifiable(preflightItems),
      errors: List.unmodifiable(errors),
      diskSpaceChecked: diskSpaceChecked,
      planFingerprint: plan.fingerprint,
      revision: plan.revision,
    );
  }

  Future<LibraryImportBatchResult> execute(
    LibraryImportPlan plan,
    LibraryPreflightReport report, {
    bool Function()? isCancelled,
    LibraryProgressCallback? onProgress,
  }) async {
    final blockingErrors = <String>[
      ...plan.issues.map((issue) => issue.toString()),
      ...report.errors.map((issue) => issue.toString()),
      if (report.planFingerprint.isEmpty ||
          report.planFingerprint != plan.fingerprint)
        'import preflight does not match the reviewed plan',
      if (report.revision != plan.revision)
        'import review is stale and must be rebuilt',
      if (report.items.length != plan.items.length)
        'import preflight does not cover the complete selected plan',
    ];
    if (blockingErrors.isNotEmpty ||
        !report.isReady ||
        plan.items.isEmpty ||
        report.items.isEmpty) {
      throw StateError(
        blockingErrors.isEmpty
            ? 'import preflight is not ready for the complete batch'
            : blockingErrors.join('\n'),
      );
    }
    await repository.setActiveLibraryRoot(plan.libraryRoot);
    final operationItems = report.items
        .map(
          (item) => {
            'source_path': item.item.entry.sourcePath,
            'source_file_name': item.item.entry.originalFileName,
            'destination_relative_path': item.item.destinationRelativePath,
            'source_file_size': item.item.sourceSnapshot.sizeBytes,
            'source_file_modified_at': item.item.sourceSnapshot.modifiedAt
                ?.toUtc()
                .toIso8601String(),
            'source_file_created_at': item.item.sourceSnapshot.createdAt
                ?.toUtc()
                .toIso8601String(),
            'source_sha256': item.item.sourceSha256,
            'work_portable_id': item.item.workPortableId,
            'media_portable_id': item.item.mediaPortableId,
            'plan_json': jsonEncode(item.item.toJournalJson()),
          },
        )
        .toList(growable: false);
    final operationId = await repository.createImportOperation(
      libraryRoot: plan.libraryRoot,
      planFingerprint: plan.fingerprint,
      items: operationItems,
    );
    final journalRows = await repository.importItems(operationId);
    await repository.updateImportOperation(
      operationId: operationId,
      state: LibraryImportOperationState.preflighting,
    );
    final results = <LibraryImportItemResult>[];
    for (final issue in plan.issues) {
      results.add(
        LibraryImportItemResult(
          code: issue.code ?? path.basename(issue.sourcePath),
          sourcePath: issue.sourcePath,
          state: LibraryImportResultState.failed,
          message: issue.message,
        ),
      );
    }
    var needsRepair = false;
    var cancelled = false;
    for (var index = 0; index < report.items.length; index++) {
      final preflightItem = report.items[index];
      final item = preflightItem.item;
      final journalId = (journalRows[index]['id'] as num).toInt();
      _emitProgress(
        onProgress,
        itemIndex: item.itemIndex,
        itemCount: plan.progressItemCount,
        code: item.details.code,
        sourceFileName: item.entry.originalFileName,
        phase: LibraryImportProgressPhase.preflight,
      );
      if (preflightItem.error != null) {
        await repository.updateImportItem(
          itemId: journalId,
          state: LibraryImportItemState.failed,
          step: 'preflight_failed',
          error: preflightItem.error,
        );
        results.add(
          LibraryImportItemResult(
            code: item.details.code,
            sourcePath: item.entry.sourcePath,
            state: LibraryImportResultState.failed,
            message: preflightItem.error!,
          ),
        );
        _emitProgress(
          onProgress,
          itemIndex: item.itemIndex,
          itemCount: plan.progressItemCount,
          code: item.details.code,
          sourceFileName: item.entry.originalFileName,
          phase: LibraryImportProgressPhase.failed,
          resultState: LibraryImportResultState.failed,
        );
        continue;
      }
      if (cancelled || isCancelled?.call() == true) {
        cancelled = true;
        await repository.updateImportItem(
          itemId: journalId,
          state: LibraryImportItemState.cancelledBeforeCommit,
          step: 'cancelled_before_commit',
        );
        results.add(
          LibraryImportItemResult(
            code: item.details.code,
            sourcePath: item.entry.sourcePath,
            state: LibraryImportResultState.cancelled,
            message: 'cancelled before portable commit',
          ),
        );
        _emitProgress(
          onProgress,
          itemIndex: item.itemIndex,
          itemCount: plan.progressItemCount,
          code: item.details.code,
          sourceFileName: item.entry.originalFileName,
          phase: LibraryImportProgressPhase.cancelled,
          resultState: LibraryImportResultState.cancelled,
        );
        continue;
      }
      if (preflightItem.duplicateMedia) {
        await repository.updateImportItem(
          itemId: journalId,
          state: LibraryImportItemState.succeeded,
          step: 'duplicate_media',
        );
        results.add(
          LibraryImportItemResult(
            code: item.details.code,
            sourcePath: item.entry.sourcePath,
            state: LibraryImportResultState.duplicateMedia,
            message:
                'same file hash already exists; source was not copied or deleted',
          ),
        );
        _emitProgress(
          onProgress,
          itemIndex: item.itemIndex,
          itemCount: plan.progressItemCount,
          code: item.details.code,
          sourceFileName: item.entry.originalFileName,
          phase: LibraryImportProgressPhase.duplicate,
          resultState: LibraryImportResultState.duplicateMedia,
        );
        continue;
      }
      final stagingItem = Directory(
        path.join(
          plan.libraryRoot,
          '.__avaca_importing',
          operationId,
          item.mediaPortableId,
        ),
      );
      final stagingWork = Directory(path.join(stagingItem.path, 'work'));
      final destinationWork = Directory(
        path.join(
          plan.libraryRoot,
          item.destinationRelativePath.replaceAll('/', path.separator),
        ),
      );
      var portableCommitted = false;
      var sourceCleanupResolved = false;
      var succeeded = false;
      try {
        await repository.updateImportItem(
          itemId: journalId,
          state: LibraryImportItemState.staging,
          step: 'staging',
        );
        await repository.updateImportOperation(
          operationId: operationId,
          state: LibraryImportOperationState.staging,
        );
        _emitProgress(
          onProgress,
          itemIndex: item.itemIndex,
          itemCount: plan.progressItemCount,
          code: item.details.code,
          sourceFileName: item.entry.originalFileName,
          phase: LibraryImportProgressPhase.staging,
        );
        await filesystem.validateNoSymbolicLinks(
          plan.libraryRoot,
          stagingItem.path,
        );
        await filesystem.validateNoSymbolicLinks(
          plan.libraryRoot,
          destinationWork.path,
        );
        await stagingItem.create(recursive: true);
        final stagedMedia = path.join(
          stagingWork.path,
          item.normalizedFileName,
        );
        await repository.updateImportItem(
          itemId: journalId,
          state: LibraryImportItemState.copying,
          step: 'copying',
        );
        await repository.updateImportOperation(
          operationId: operationId,
          state: LibraryImportOperationState.copying,
        );
        _emitProgress(
          onProgress,
          itemIndex: item.itemIndex,
          itemCount: plan.progressItemCount,
          code: item.details.code,
          sourceFileName: item.entry.originalFileName,
          phase: LibraryImportProgressPhase.copying,
        );
        final copiedHash = await _copySource(
          item.entry,
          stagedMedia,
          expectedSnapshot: item.sourceSnapshot,
        );
        if (copiedHash != item.sourceSha256) {
          throw StateError('staged media hash mismatch');
        }
        await repository.updateImportItem(
          itemId: journalId,
          state: LibraryImportItemState.verifying,
          step: 'verifying',
        );
        await repository.updateImportOperation(
          operationId: operationId,
          state: LibraryImportOperationState.verifying,
        );
        _emitProgress(
          onProgress,
          itemIndex: item.itemIndex,
          itemCount: plan.progressItemCount,
          code: item.details.code,
          sourceFileName: item.entry.originalFileName,
          phase: LibraryImportProgressPhase.verifying,
        );
        final imageResult = await imageDownloader.download(
          details: item.details,
          destinationDirectory: stagingWork.path,
        );
        // Re-check the destination after the potentially slow probe/image
        // work.  Preflight is a review snapshot, not a lock against another
        // process creating or changing a portable Work in the meantime.
        final destinationState = await _validateDestinationBeforeCommit(
          item: item,
          libraryRoot: plan.libraryRoot,
          destinationWork: destinationWork,
        );
        final mediaRecord = _mediaRecord(item, importOperationId: operationId);
        var document = await _documentForItem(
          item,
          destinationState.exists ? destinationWork : null,
        );
        final images = <String, String?>{
          ...document.images,
          if (imageResult.coverSource != null) 'cover': 'images/cover.jpg',
          if (imageResult.posterSource != null) 'poster': 'images/poster.jpg',
        };
        document = LibraryInfoDocument(
          schemaVersion: 1,
          workId: document.workId,
          code: document.code,
          metadata: document.metadata,
          primaryActressId: document.primaryActressId,
          performers: document.performers,
          images: images,
          media: [...document.media, mediaRecord],
          scrape: document.scrape,
          libraryRelativePath: item.destinationRelativePath,
        );
        // The staged copy has already been verified.  Resolve source cleanup
        // before publishing any final Library files or DB rows so a provider
        // failure cannot expose a normal Collection item with the source
        // still present.
        await repository.updateImportItem(
          itemId: journalId,
          state: LibraryImportItemState.sourceCleanupPending,
          step: 'source_cleanup_pending',
        );
        await repository.updateImportOperation(
          operationId: operationId,
          state: LibraryImportOperationState.sourceCleanupPending,
        );
        _emitProgress(
          onProgress,
          itemIndex: item.itemIndex,
          itemCount: plan.progressItemCount,
          code: item.details.code,
          sourceFileName: item.entry.originalFileName,
          phase: LibraryImportProgressPhase.sourceCleanup,
        );
        final currentSource = await _snapshotSource(item.entry);
        if (!currentSource.matches(item.sourceSnapshot)) {
          throw StateError(
            'source changed before cleanup; source was preserved',
          );
        }
        await _verifySourceHashBeforeCleanup(item);
        final deleteResult = await _deleteSource(
          item.entry,
          expectedSnapshot: item.sourceSnapshot,
        );
        if (!deleteResult.isConfirmedDeleted) {
          throw StateError(
            'source cleanup ${deleteResult.outcome.name}: '
            '${deleteResult.message ?? 'source was preserved'}',
          );
        }
        sourceCleanupResolved = true;

        if (destinationState.exists) {
          // Recheck immediately before moving the media into an existing
          // Work.  A file that appeared after the first check must never be
          // replaced by this import.
          await _validateDestinationMediaIsAbsent(
            item: item,
            destinationWork: destinationWork,
          );
          await Directory(
            path.dirname(
              path.join(destinationWork.path, item.normalizedFileName),
            ),
          ).create(recursive: true);
          await File(
            stagedMedia,
          ).rename(path.join(destinationWork.path, item.normalizedFileName));
          await _moveStagedImages(stagingWork, destinationWork);
          await infoStore.write(destinationWork, document);
          portableCommitted = true;
        } else {
          await infoStore.write(stagingWork, document);
          await Directory(destinationWork.parent.path).create(recursive: true);
          if (await destinationWork.exists()) {
            throw StateError('destination folder appeared during import');
          }
          await stagingWork.rename(destinationWork.path);
          portableCommitted = true;
        }
        final finalMediaPath = path.join(
          destinationWork.path,
          item.normalizedFileName,
        );
        if (await filesystem.hashFile(finalMediaPath) != item.sourceSha256) {
          throw StateError('portable media hash verification failed');
        }
        await repository.updateImportItem(
          itemId: journalId,
          state: LibraryImportItemState.portableCommitted,
          step: 'portable_committed',
        );
        await repository.updateImportOperation(
          operationId: operationId,
          state: LibraryImportOperationState.portableCommitted,
          committed: true,
        );
        _emitProgress(
          onProgress,
          itemIndex: item.itemIndex,
          itemCount: plan.progressItemCount,
          code: item.details.code,
          sourceFileName: item.entry.originalFileName,
          phase: LibraryImportProgressPhase.portableCommit,
        );
        final commit = await repository.commitInfoDocument(
          document,
          libraryRoot: plan.libraryRoot,
          importOperationId: operationId,
        );
        await repository.updateImportItem(
          itemId: journalId,
          state: LibraryImportItemState.indexing,
          step: 'indexing',
          workPortableId: document.workId,
          mediaPortableId: mediaRecord.mediaId,
        );
        await repository.updateImportOperation(
          operationId: operationId,
          state: LibraryImportOperationState.indexing,
        );
        _emitProgress(
          onProgress,
          itemIndex: item.itemIndex,
          itemCount: plan.progressItemCount,
          code: item.details.code,
          sourceFileName: item.entry.originalFileName,
          phase: LibraryImportProgressPhase.indexing,
        );
        await repository.updateImportItem(
          itemId: journalId,
          state: LibraryImportItemState.linking,
          step: 'linking',
        );
        await repository.updateImportOperation(
          operationId: operationId,
          state: LibraryImportOperationState.linking,
        );
        _emitProgress(
          onProgress,
          itemIndex: item.itemIndex,
          itemCount: plan.progressItemCount,
          code: item.details.code,
          sourceFileName: item.entry.originalFileName,
          phase: LibraryImportProgressPhase.linking,
        );
        await _buildPerformerLinks(
          item: item,
          libraryRoot: plan.libraryRoot,
          destinationWork: destinationWork,
          workId: commit.workId,
        );
        await repository.updateImportItem(
          itemId: journalId,
          state: LibraryImportItemState.succeeded,
          step: 'succeeded',
        );
        await repository.updateImportOperation(
          operationId: operationId,
          state: LibraryImportOperationState.succeeded,
          committed: true,
        );
        results.add(
          LibraryImportItemResult(
            code: item.details.code,
            sourcePath: item.entry.sourcePath,
            state: LibraryImportResultState.succeeded,
            message: 'imported',
          ),
        );
        succeeded = true;
        _emitProgress(
          onProgress,
          itemIndex: item.itemIndex,
          itemCount: plan.progressItemCount,
          code: item.details.code,
          sourceFileName: item.entry.originalFileName,
          phase: LibraryImportProgressPhase.succeeded,
          resultState: LibraryImportResultState.succeeded,
        );
      } on Object catch (error) {
        final committed = portableCommitted || sourceCleanupResolved;
        if (committed) needsRepair = true;
        await repository.updateImportItem(
          itemId: journalId,
          state: committed
              ? LibraryImportItemState.repairRequired
              : LibraryImportItemState.failed,
          step: committed ? 'repair_required' : 'failed',
          error: '$error',
        );
        await repository.updateImportOperation(
          operationId: operationId,
          state: committed
              ? LibraryImportOperationState.repairRequired
              : LibraryImportOperationState.failed,
          error: '$error',
          committed: committed,
        );
        results.add(
          LibraryImportItemResult(
            code: item.details.code,
            sourcePath: item.entry.sourcePath,
            state: committed
                ? LibraryImportResultState.repairRequired
                : LibraryImportResultState.failed,
            message: '$error',
          ),
        );
        _emitProgress(
          onProgress,
          itemIndex: item.itemIndex,
          itemCount: plan.progressItemCount,
          code: item.details.code,
          sourceFileName: item.entry.originalFileName,
          phase: committed
              ? LibraryImportProgressPhase.repairRequired
              : LibraryImportProgressPhase.failed,
          resultState: committed
              ? LibraryImportResultState.repairRequired
              : LibraryImportResultState.failed,
        );
      } finally {
        if (succeeded || (!portableCommitted && !sourceCleanupResolved)) {
          try {
            await filesystem.deleteStagingTree(
              stagingItem.path,
              stagingRoot: path.join(plan.libraryRoot, '.__avaca_importing'),
            );
          } on Object {
            needsRepair = true;
          }
        } else {
          // A verified copy may be the only recoverable media after source
          // cleanup or final publication crossed its boundary. Keep the
          // staging journal for explicit recovery instead of deleting it.
          needsRepair = true;
        }
      }
    }
    if (cancelled) {
      await repository.updateImportOperation(
        operationId: operationId,
        state: LibraryImportOperationState.cancelledBeforeCommit,
      );
    } else if (needsRepair) {
      await repository.updateImportOperation(
        operationId: operationId,
        state: LibraryImportOperationState.repairRequired,
      );
    } else if (results.any(
      (item) => item.state == LibraryImportResultState.failed,
    )) {
      await repository.updateImportOperation(
        operationId: operationId,
        state: LibraryImportOperationState.failed,
      );
    } else {
      await repository.updateImportOperation(
        operationId: operationId,
        state: LibraryImportOperationState.succeeded,
        committed: true,
      );
    }
    return LibraryImportBatchResult(
      operationId: operationId,
      items: List.unmodifiable(results),
      planIssues: plan.issues,
    );
  }

  bool _isAndroidSourceEntry(LibraryScanEntry entry) =>
      entry.sourceLocator is LibraryAndroidDocumentSourceEntryLocator;

  Future<LibrarySourceSnapshot> _snapshotSource(LibraryScanEntry entry) {
    if (_isAndroidSourceEntry(entry)) {
      final access = sourceAccess;
      if (access == null) {
        throw const LibrarySourceAccessException(
          'Android source access is not configured',
        );
      }
      return access.snapshot(entry.sourceLocator);
    }
    return filesystem.snapshot(entry.sourcePath);
  }

  Future<_SourceMediaInspection> _inspectSource({
    required LibraryScanEntry entry,
    required LibrarySourceSnapshot expectedSnapshot,
  }) async {
    if (!_isAndroidSourceEntry(entry)) {
      return _SourceMediaInspection(
        sha256: await filesystem.hashFile(entry.sourcePath),
        probe: await mediaProbe.probe(entry.sourcePath),
      );
    }
    final access = sourceAccess;
    if (access == null) {
      throw const LibrarySourceAccessException(
        'Android source access is not configured',
      );
    }
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'avaca_library_probe_',
    );
    try {
      final localPath = path.join(temporaryDirectory.path, 'source.media');
      await access.copyToFile(
        entry.sourceLocator,
        localPath,
        expectedSnapshot: expectedSnapshot,
      );
      final hash = await filesystem.hashFile(localPath);
      return _SourceMediaInspection(
        sha256: hash,
        probe: await mediaProbe.probe(localPath),
      );
    } finally {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    }
  }

  Future<String> _copySource(
    LibraryScanEntry entry,
    String destinationPath, {
    required LibrarySourceSnapshot expectedSnapshot,
  }) {
    if (_isAndroidSourceEntry(entry)) {
      final access = sourceAccess;
      if (access == null) {
        throw const LibrarySourceAccessException(
          'Android source access is not configured',
        );
      }
      return access.copyToFile(
        entry.sourceLocator,
        destinationPath,
        expectedSnapshot: expectedSnapshot,
      );
    }
    return filesystem.copyAndHash(
      entry.sourcePath,
      destinationPath,
      expectedSnapshot: expectedSnapshot,
    );
  }

  Future<void> _verifySourceHashBeforeCleanup(
    LibraryImportPlanItem item,
  ) async {
    if (!_isAndroidSourceEntry(item.entry)) {
      if (await filesystem.hashFile(item.entry.sourcePath) !=
          item.sourceSha256) {
        throw StateError('source changed before cleanup; source was preserved');
      }
      return;
    }
    final access = sourceAccess;
    if (access == null) {
      throw const LibrarySourceAccessException(
        'Android source access is not configured',
      );
    }
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'avaca_library_verify_',
    );
    try {
      final localPath = path.join(temporaryDirectory.path, 'source.media');
      final hash = await access.copyToFile(
        item.entry.sourceLocator,
        localPath,
        expectedSnapshot: item.sourceSnapshot,
      );
      if (hash != item.sourceSha256 ||
          await filesystem.hashFile(localPath) != item.sourceSha256) {
        throw StateError('source changed before cleanup; source was preserved');
      }
    } finally {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    }
  }

  Future<LibrarySourceDeleteResult> _deleteSource(
    LibraryScanEntry entry, {
    required LibrarySourceSnapshot expectedSnapshot,
  }) {
    if (_isAndroidSourceEntry(entry)) {
      final access = sourceAccess;
      if (access == null) {
        throw const LibrarySourceAccessException(
          'Android source access is not configured',
        );
      }
      return access.delete(
        entry.sourceLocator,
        expectedSnapshot: expectedSnapshot,
      );
    }
    return LibraryPathSourceAccess(
      filesystem: filesystem,
    ).delete(entry.sourceLocator, expectedSnapshot: expectedSnapshot);
  }

  void _emitProgress(
    LibraryProgressCallback? onProgress, {
    required int itemIndex,
    required int itemCount,
    required String code,
    required String sourceFileName,
    required LibraryImportProgressPhase phase,
    LibraryImportResultState? resultState,
  }) {
    onProgress?.call(
      LibraryImportProgress(
        itemIndex: itemIndex,
        itemCount: itemCount,
        code: code,
        sourceFileName: sourceFileName,
        phase: phase,
        resultState: resultState,
      ),
    );
  }

  Future<String> _portableActressId(
    String name,
    Map<String, String> cache,
  ) async {
    final key = name.trim().toLowerCase();
    final cached = cache[key];
    if (cached != null) {
      return cached;
    }
    final candidates = await repository.findActressCandidates([
      name,
    ], ensurePortableIds: false);
    if (candidates.length > 1) {
      throw StateError('actress name is ambiguous: $name');
    }
    final id = candidates.firstOrNull?.portableId ?? idGenerator.next();
    cache[key] = id;
    return id;
  }

  String _normalizedFileName(LibraryFilenameParseResult parsed, String code) {
    final variant = parsed.variantToken == null
        ? ''
        : '-${parsed.variantToken}';
    final part = parsed.partNumber == null ? '' : '-CD${parsed.partNumber}';
    return '$code$variant$part.${parsed.extension.toLowerCase()}';
  }

  Future<_DestinationCommitState> _validateDestinationBeforeCommit({
    required LibraryImportPlanItem item,
    required String libraryRoot,
    required Directory destinationWork,
  }) async {
    await filesystem.validateNoSymbolicLinks(libraryRoot, destinationWork.path);
    final entityType = await FileSystemEntity.type(
      destinationWork.path,
      followLinks: false,
    );
    if (entityType == FileSystemEntityType.notFound) {
      return const _DestinationCommitState.missing();
    }
    if (entityType != FileSystemEntityType.directory) {
      throw StateError('destination Work path is not a directory');
    }
    final info = File(path.join(destinationWork.path, 'info.json'));
    if (!await info.exists()) {
      throw StateError(
        'destination Work appeared or changed after preflight without portable info.json',
      );
    }
    final existing = await infoStore.read(info);
    if (existing.workId != item.workPortableId ||
        existing.code.trim().toUpperCase() !=
            item.details.code.trim().toUpperCase()) {
      throw StateError('destination Work identity changed after preflight');
    }
    await _validateDestinationMediaIsAbsent(
      item: item,
      destinationWork: destinationWork,
    );
    return const _DestinationCommitState.exists();
  }

  Future<void> _validateDestinationMediaIsAbsent({
    required LibraryImportPlanItem item,
    required Directory destinationWork,
  }) async {
    final destinationMedia = File(
      path.join(destinationWork.path, item.normalizedFileName),
    );
    if (await destinationMedia.exists()) {
      throw StateError(
        'destination media appeared or changed after preflight; import was not allowed to overwrite it',
      );
    }
  }

  LibraryMediaRecord _mediaRecord(
    LibraryImportPlanItem item, {
    required String importOperationId,
  }) => LibraryMediaRecord(
    mediaId: item.mediaPortableId,
    workId: item.workPortableId,
    relativePath: item.normalizedFileName,
    fileName: item.normalizedFileName,
    originalFileName: item.entry.originalFileName,
    variant: item.entry.parseResult.variantToken,
    variantType: item.entry.parseResult.variantType,
    hasChineseSubtitles: item.entry.parseResult.hasChineseSubtitles,
    partNumber: item.entry.parseResult.partNumber,
    partLabel: item.entry.parseResult.partLabel,
    width: item.mediaProbe.width,
    height: item.mediaProbe.height,
    resolutionLabel: item.mediaProbe.resolutionLabel,
    frameRateNumerator: item.mediaProbe.frameRateNumerator,
    frameRateDenominator: item.mediaProbe.frameRateDenominator,
    frameRateDecimal: item.mediaProbe.frameRate,
    durationMs: item.mediaProbe.durationMs,
    container: item.mediaProbe.container,
    codec: item.mediaProbe.codec,
    fileSizeBytes: item.sourceSnapshot.sizeBytes,
    sha256: item.sourceSha256,
    sourceFileCreatedAt: item.sourceSnapshot.createdAt,
    importedAt: DateTime.now().toUtc(),
    probeBackend: item.mediaProbe.backend,
    probeVersion: item.mediaProbe.backendVersion,
    parserVersion: item.entry.parseResult.parserVersion,
    importOperationId: importOperationId,
  );

  Future<LibraryInfoDocument> _documentForItem(
    LibraryImportPlanItem item,
    Directory? existingWork,
  ) async {
    if (existingWork != null) {
      final info = File(path.join(existingWork.path, 'info.json'));
      if (await info.exists()) {
        final existing = await infoStore.read(info);
        if (existing.workId != item.workPortableId) {
          throw StateError('destination Work identity mismatch');
        }
        return existing;
      }
    }
    return LibraryInfoDocument(
      schemaVersion: 1,
      workId: item.workPortableId,
      code: item.details.code.trim().toUpperCase(),
      metadata: {
        'title': item.details.title,
        'releaseDate': item.details.releaseDate,
        'durationMinutes': item.details.durationMinutes,
        'studio': item.details.studio,
        'publisher': item.details.publisher,
        'series': item.details.series,
        'primaryActressName': item.primaryActressName,
      },
      primaryActressId: item.primaryActressId,
      performers: item.performers,
      images: const {},
      media: const [],
      scrape: {
        'source': item.details.source.storageValue,
        'sourceUri': item.details.sourceUri?.toString(),
      },
      libraryRelativePath: item.destinationRelativePath,
    );
  }

  Future<void> _assertWritable(String root) async {
    final directory = Directory(root);
    if (!await directory.exists()) {
      throw LibraryFilesystemException(
        'Library Root does not exist',
        pathValue: root,
      );
    }
    final probe = File(
      path.join(
        root,
        '.__avaca_preflight_${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    await probe.writeAsString('avaca', flush: true);
    await probe.delete();
  }

  Future<void> _moveStagedImages(
    Directory stagingWork,
    Directory destinationWork,
  ) async {
    final stagingImages = Directory(path.join(stagingWork.path, 'images'));
    if (!await stagingImages.exists()) return;
    final destinationImages = Directory(
      path.join(destinationWork.path, 'images'),
    );
    await destinationImages.create(recursive: true);
    await for (final entity in stagingImages.list(followLinks: false)) {
      if (entity is! File) continue;
      final target = File(
        path.join(destinationImages.path, path.basename(entity.path)),
      );
      if (await target.exists()) await target.delete();
      await entity.rename(target.path);
    }
  }

  Future<void> _buildPerformerLinks({
    required LibraryImportPlanItem item,
    required String libraryRoot,
    required Directory destinationWork,
    required int workId,
  }) async {
    if (!shortcutManager.isSupported) return;
    for (final performer in item.performers) {
      final name = performer['name']?.toString().trim() ?? '';
      final actressId = performer['actressId']?.toString();
      if (name.isEmpty ||
          actressId == null ||
          actressId.isEmpty ||
          actressId == item.primaryActressId) {
        continue;
      }
      final linkPath = path.join(
        libraryRoot,
        filesystem.safeSegment(name),
        '${filesystem.safeSegment(item.details.code)}.lnk',
      );
      if (await File(linkPath).exists() || await Directory(linkPath).exists()) {
        continue;
      }
      await shortcutManager.createDirectoryShortcut(
        linkPath: linkPath,
        targetPath: destinationWork.path,
      );
      await repository.recordLibraryLink(
        workId: workId,
        actressPortableId: actressId,
        relativePath: path
            .relative(linkPath, from: libraryRoot)
            .replaceAll('\\', '/'),
        targetRelativePath: path
            .relative(destinationWork.path, from: libraryRoot)
            .replaceAll('\\', '/'),
        state: 'ready',
      );
    }
  }
}

class _DestinationCommitState {
  const _DestinationCommitState.missing() : exists = false;
  const _DestinationCommitState.exists() : exists = true;

  final bool exists;
}
