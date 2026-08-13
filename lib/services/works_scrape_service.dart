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
import 'scrape/work_code_canonicalizer.dart';

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

class WorksScrapeProgress {
  const WorksScrapeProgress({
    required this.current,
    required this.total,
    required this.saved,
    required this.excluded,
    required this.failed,
    this.source,
  });

  final int current;
  final int total;
  final int saved;
  final int excluded;
  final int failed;
  final ScrapeSourceId? source;
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
  });

  final int saved;
  final int excluded;
  final int failed;
  final bool cancelled;
  final ActressImageSyncStatus actressImageStatus;
  final bool partialSuccess;
  final Map<ScrapeSourceId, ScrapeSourceRunResult> sourceResults;
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
    final settings =
        sourceSettings ?? const ScrapeSourceSettings.legacyJavBus();
    final queries = _queries(name, aliases);
    final requestedWorkIds = ScrapeSourceRegistry.resolveWorksSources(
      settings.worksSource,
    );
    final sourceResults = <ScrapeSourceId, ScrapeSourceRunResult>{};
    final collectedById = <ScrapeSourceId, _CollectedSource>{};

    final sourceIdsToCollect = <ScrapeSourceId>[
      ...requestedWorkIds,
      if (!requestedWorkIds.contains(settings.actressDetailsSource))
        settings.actressDetailsSource,
    ];
    for (final sourceId in sourceIdsToCollect) {
      if (_isCancelled(cancellationToken)) {
        break;
      }
      final source = sources[sourceId];
      if (source == null) {
        sourceResults[sourceId] = ScrapeSourceRunResult(
          source: sourceId,
          state: ScrapeSourceRunState.unavailable,
          error: 'Source is not configured.',
        );
        continue;
      }
      final collected = await _collectSource(
        source: source,
        queries: queries,
        cancellationToken: cancellationToken,
        includeWorks: requestedWorkIds.contains(sourceId),
      );
      collectedById[sourceId] = collected;
      if (requestedWorkIds.contains(sourceId) ||
          sourceId == settings.actressDetailsSource) {
        sourceResults[sourceId] = collected.result;
      }
    }

    if (_isCancelled(cancellationToken)) {
      return WorksScrapeResult(
        saved: 0,
        excluded: 0,
        failed: 0,
        cancelled: true,
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

    final detailsSourceId = settings.actressDetailsSource;
    final detailsSource = sources[detailsSourceId];
    final detailsCollection = collectedById[detailsSourceId];
    ActressImageSyncStatus actressImageStatus = options.replaceActressImage
        ? ActressImageSyncStatus.unavailable
        : ActressImageSyncStatus.notRequested;
    if (detailsSource != null &&
        detailsCollection != null &&
        detailsCollection.pages.isNotEmpty) {
      final details = _mergeActressPages(
        detailsCollection.pages.values.toList(growable: false),
        source: detailsSource,
      );
      actressImageStatus = await _syncActress(
        actressId: actressId,
        details: details,
        source: detailsSource,
        options: options,
      );
    }

    final exclusions = PrefixExclusion(options.excludedPrefixes);
    final groups = _buildWorkGroups(
      requestedWorkIds,
      collectedById,
      exclusions,
    );
    var saved = 0;
    var excluded = groups.preExcluded;
    var failed = 0;
    var current = 0;
    final resolvedGroups = <String, _ResolvedWorkGroup>{};

    for (final group in groups.groups) {
      if (_isCancelled(cancellationToken)) {
        break;
      }
      current++;
      final fetched = <ScrapeWorkDetails>[];
      var hadSourceFailure = false;
      for (final candidate in group.candidates) {
        if (_isCancelled(cancellationToken)) {
          break;
        }
        try {
          final source = sources[candidate.source.id];
          if (source == null) {
            hadSourceFailure = true;
            continue;
          }
          final details = await source.fetchWorkDetails(candidate.summary);
          final code = canonicalizeWorkCode(details.code);
          if (code == null ||
              (group.expectedCode != null && code != group.expectedCode)) {
            hadSourceFailure = true;
            continue;
          }
          fetched.add(
            _withCanonicalCode(
              details,
              code,
              fallbackTitle: candidate.summary.title,
              fallbackReleaseDate: candidate.summary.releaseDate,
            ),
          );
        } catch (_) {
          hadSourceFailure = true;
        }
      }
      if (_isCancelled(cancellationToken)) {
        break;
      }
      if (fetched.isEmpty) {
        failed++;
        _notify(
          onProgress,
          current,
          groups.groups.length,
          saved,
          excluded,
          failed,
          source: group.sourceId,
        );
        continue;
      }
      final code = canonicalizeWorkCode(fetched.first.code);
      if (code == null) {
        failed++;
        continue;
      }
      final existing = resolvedGroups[code];
      if (existing == null) {
        resolvedGroups[code] = _ResolvedWorkGroup(
          code: code,
          details: fetched,
          hadSourceFailure: hadSourceFailure,
        );
      } else {
        existing.details.addAll(fetched);
        existing.hadSourceFailure =
            existing.hadSourceFailure || hadSourceFailure;
      }
      _notify(
        onProgress,
        current,
        groups.groups.length,
        saved,
        excluded,
        failed,
        source: group.sourceId,
      );
    }

    for (final resolved in resolvedGroups.values) {
      if (_isCancelled(cancellationToken)) {
        break;
      }
      final code = canonicalizeWorkCode(resolved.code);
      if (code == null) {
        failed++;
        continue;
      }
      if (exclusions.matches(code)) {
        excluded++;
        continue;
      }
      final merged = _mergeWorkDetails(resolved.details, code);
      final maxActressCount = options.maxActressCount;
      if (maxActressCount != null) {
        final performerCount = merged.performerCount;
        if (performerCount == null || performerCount <= 0) {
          failed++;
          continue;
        }
        if (performerCount > maxActressCount) {
          excluded++;
          continue;
        }
      }
      try {
        await _saveWork(
          actressId: actressId,
          details: merged,
          missingOnly: options.fillMissingOnly,
          cancellationToken: cancellationToken,
        );
        saved++;
      } on _ScrapeCancelled {
        break;
      } catch (_) {
        failed++;
      }
    }

    final partial =
        sourceResults.values.any(
          (result) =>
              result.state == ScrapeSourceRunState.failed ||
              result.state == ScrapeSourceRunState.unavailable ||
              result.state == ScrapeSourceRunState.cancelled,
        ) ||
        failed > 0 ||
        resolvedGroups.values.any((group) => group.hadSourceFailure);
    return WorksScrapeResult(
      saved: saved,
      excluded: excluded,
      failed: failed,
      cancelled: _isCancelled(cancellationToken),
      actressImageStatus: actressImageStatus,
      partialSuccess: partial,
      sourceResults: Map.unmodifiable(sourceResults),
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
      final queryKey = query.trim().toLowerCase();
      for (final actress in results.where(
        (result) => result.name.trim().toLowerCase() == queryKey,
      )) {
        matched = true;
        final uriKey = actress.uri.toString();
        if (completedUris.contains(uriKey)) {
          continue;
        }
        matches[uriKey] = actress;
        try {
          final page = await source.fetchActressPage(actress);
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

  _WorkGroups _buildWorkGroups(
    List<ScrapeSourceId> sourceIds,
    Map<ScrapeSourceId, _CollectedSource> collectedById,
    PrefixExclusion exclusions,
  ) {
    final groupsByKey = <String, _WorkGroup>{};
    final groups = <_WorkGroup>[];
    var preExcluded = 0;
    final preExcludedCodes = <String>{};
    for (final sourceId in sourceIds) {
      final collected = collectedById[sourceId];
      if (collected == null) {
        continue;
      }
      for (final summary in collected.summaries) {
        final code = canonicalizeWorkCode(summary.code);
        if (code != null && exclusions.matches(code)) {
          if (preExcludedCodes.add(code)) {
            preExcluded++;
          }
          continue;
        }
        final key = code ?? '${sourceId.storageValue}:${summary.detailUri}';
        final group = groupsByKey[key];
        if (group == null) {
          final created = _WorkGroup(expectedCode: code, sourceId: sourceId);
          created.candidates.add(
            _WorkCandidate(source: collected.source, summary: summary),
          );
          groupsByKey[key] = created;
          groups.add(created);
        } else {
          if (group.candidates.any(
            (candidate) => candidate.source.id == sourceId,
          )) {
            continue;
          }
          group.candidates.add(
            _WorkCandidate(source: collected.source, summary: summary),
          );
        }
      }
    }
    return _WorkGroups(groups: groups, preExcluded: preExcluded);
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
  }) async {
    return db.runManagedImageLifecycle(
      () => _syncActressUnlocked(
        actressId: actressId,
        details: details,
        source: source,
        options: options,
      ),
    );
  }

  Future<ActressImageSyncStatus> _syncActressUnlocked({
    required int actressId,
    required ScrapedActressDetails details,
    required ScrapeSource source,
    required WorkScrapeOptions options,
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
        previousImagePath = (await db.getActressById(
          actressId,
        ))?['img_path']?.toString();
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

  Future<void> _saveWork({
    required int actressId,
    required ScrapeWorkDetails details,
    required bool missingOnly,
    WorksScrapeCancellationToken? cancellationToken,
  }) async {
    await db.runManagedImageLifecycle(
      () => _saveWorkUnlocked(
        actressId: actressId,
        details: details,
        missingOnly: missingOnly,
        cancellationToken: cancellationToken,
      ),
    );
  }

  Future<void> _saveWorkUnlocked({
    required int actressId,
    required ScrapeWorkDetails details,
    required bool missingOnly,
    WorksScrapeCancellationToken? cancellationToken,
  }) async {
    if (_isCancelled(cancellationToken)) {
      throw const _ScrapeCancelled();
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
    );
    work = details.toWork(cardImagePath: cardPath, detailImagePath: detailPath);
    await db.upsertActressWork(
      actressId: actressId,
      work: work,
      missingOnly: missingOnly,
    );
  }

  Future<String?> _downloadWorkImage({
    required ScrapeWorkDetails details,
    required WorkImageVariant variant,
    required String targetPath,
    required String currentPath,
    required bool missingOnly,
  }) async {
    if (missingOnly &&
        currentPath.isNotEmpty &&
        File(currentPath).existsSync()) {
      return currentPath;
    }
    final uriDownloader = imageUriDownloader;
    if (uriDownloader != null) {
      for (final uri in details.imageUris) {
        final source = sources[details.source];
        if (source == null || !source.acceptsImageUri(uri)) {
          continue;
        }
        try {
          return await uriDownloader.download(uri: uri, targetPath: targetPath);
        } catch (_) {
          // Continue to the next source image and then use the legacy image
          // policy as a compatibility fallback.
        }
      }
    }
    try {
      await workImageDownloader.downloadToFile(
        code: details.code,
        studio: details.studio,
        variant: variant,
        targetPath: targetPath,
      );
      return targetPath;
    } catch (_) {
      return currentPath.isEmpty ? null : currentPath;
    }
  }

  ScrapeWorkDetails _withCanonicalCode(
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

  bool _isCancelled(WorksScrapeCancellationToken? token) =>
      token?.isCancelled ?? false;

  void _notify(
    void Function(WorksScrapeProgress progress)? callback,
    int current,
    int total,
    int saved,
    int excluded,
    int failed, {
    ScrapeSourceId? source,
  }) {
    callback?.call(
      WorksScrapeProgress(
        current: current,
        total: total,
        saved: saved,
        excluded: excluded,
        failed: failed,
        source: source,
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

final class _WorkCandidate {
  const _WorkCandidate({required this.source, required this.summary});

  final ScrapeSource source;
  final ScrapeWorkSummary summary;
}

final class _WorkGroup {
  _WorkGroup({required this.expectedCode, required this.sourceId});

  final String? expectedCode;
  final ScrapeSourceId sourceId;
  final candidates = <_WorkCandidate>[];
}

final class _WorkGroups {
  const _WorkGroups({required this.groups, required this.preExcluded});

  final List<_WorkGroup> groups;
  final int preExcluded;
}

final class _ResolvedWorkGroup {
  _ResolvedWorkGroup({
    required this.code,
    required this.details,
    required this.hadSourceFailure,
  });

  final String code;
  final List<ScrapeWorkDetails> details;
  bool hadSourceFailure;
}

class _ScrapeCancelled implements Exception {
  const _ScrapeCancelled();
}
