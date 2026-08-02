import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../core/database.dart';
import '../models/scraped_actress_details.dart';
import '../models/work_scrape_options.dart';
import 'javbus/javbus_client.dart';
import 'javbus/javbus_models.dart';
import 'javbus/prefix_exclusion.dart';
import 'javbus/work_image_downloader.dart';
import 'javbus/work_image_policy.dart';
import 'safe_image.dart';

abstract interface class ActressImageDownloader {
  Future<String> download(Uri uri, String targetPath);
}

class HttpActressImageDownloader implements ActressImageDownloader {
  HttpActressImageDownloader({BinaryTransport? transport})
    : _transport =
          transport ??
          HttpBinaryTransport(
            allowedHosts: const {'www.javbus.com'},
            maxBytes: 5 * 1024 * 1024,
          );

  final BinaryTransport _transport;

  @override
  Future<String> download(Uri uri, String targetPath) async {
    final response = await _transport.get(uri);
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
  });

  final int current;
  final int total;
  final int saved;
  final int excluded;
  final int failed;
}

class WorksScrapeResult {
  const WorksScrapeResult({
    required this.saved,
    required this.excluded,
    required this.failed,
    required this.cancelled,
  });

  final int saved;
  final int excluded;
  final int failed;
  final bool cancelled;
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
    required this.client,
    WorkImageDownloader? workImageDownloader,
    ActressImageDownloader? actressImageDownloader,
    String? imageDirectory,
  }) : workImageDownloader = workImageDownloader ?? WorkImageDownloader(),
       actressImageDownloader =
           actressImageDownloader ?? HttpActressImageDownloader(),
       imageDirectory = imageDirectory ?? path.join(db.imgDir, 'scraped');

  final AppDatabase db;
  final JavBusClient client;
  final WorkImageDownloader workImageDownloader;
  final ActressImageDownloader actressImageDownloader;
  final String imageDirectory;

  void close() {
    client.close();
    workImageDownloader.close();
    final downloader = actressImageDownloader;
    if (downloader is HttpActressImageDownloader) {
      downloader.close();
    }
  }

  Future<WorksScrapeResult> scrape({
    required int actressId,
    required String actressName,
    required WorkScrapeOptions options,
    WorksScrapeCancellationToken? cancellationToken,
    void Function(WorksScrapeProgress progress)? onProgress,
  }) async {
    final name = actressName.trim();
    if (name.isEmpty) {
      throw const WorksScrapeException('Actress name is empty.');
    }

    final searchResults = await client.searchActresses(name);
    if (cancellationToken?.isCancelled ?? false) {
      return const WorksScrapeResult(
        saved: 0,
        excluded: 0,
        failed: 0,
        cancelled: true,
      );
    }
    if (searchResults.isEmpty) {
      throw WorksScrapeException('Actress was not found: $name');
    }
    final exactMatches = searchResults
        .where((result) => result.name.trim() == name)
        .toList(growable: false);
    if (exactMatches.isEmpty) {
      throw WorksScrapeException('Exact actress was not found: $name');
    }
    if (exactMatches.length > 1) {
      throw WorksScrapeException('Actress name is ambiguous: $name');
    }
    final actress = exactMatches.first;
    final actressPage = await client.fetchActressPage(actress.uri);
    if (cancellationToken?.isCancelled ?? false) {
      return const WorksScrapeResult(
        saved: 0,
        excluded: 0,
        failed: 0,
        cancelled: true,
      );
    }
    await _syncActress(
      actressId: actressId,
      page: actressPage,
      options: options,
    );

    final exclusions = PrefixExclusion(options.excludedPrefixes);
    final summaries = await client.fetchAllActressWorks(
      actress.uri,
      isCancelled: () => cancellationToken?.isCancelled ?? false,
    );
    var saved = 0;
    var excluded = 0;
    var failed = 0;
    var current = 0;

    for (final summary in summaries) {
      if (cancellationToken?.isCancelled ?? false) {
        break;
      }
      current++;
      if (exclusions.matches(summary.code)) {
        excluded++;
        _notify(onProgress, current, summaries.length, saved, excluded, failed);
        continue;
      }

      try {
        final details = await client.fetchWorkDetails(summary.detailUri);
        if (cancellationToken?.isCancelled ?? false) {
          break;
        }
        await _saveWork(
          actressId: actressId,
          details: details,
          missingOnly: options.fillMissingOnly,
          cancellationToken: cancellationToken,
        );
        saved++;
      } on _ScrapeCancelled {
        break;
      } catch (_) {
        failed++;
      }
      _notify(onProgress, current, summaries.length, saved, excluded, failed);
    }

    return WorksScrapeResult(
      saved: saved,
      excluded: excluded,
      failed: failed,
      cancelled: cancellationToken?.isCancelled ?? false,
    );
  }

  Future<void> _syncActress({
    required int actressId,
    required JavBusActressPage page,
    required WorkScrapeOptions options,
  }) async {
    await db.runManagedImageLifecycle(
      () => _syncActressUnlocked(
        actressId: actressId,
        page: page,
        options: options,
      ),
    );
  }

  Future<void> _syncActressUnlocked({
    required int actressId,
    required JavBusActressPage page,
    required WorkScrapeOptions options,
  }) async {
    String? imagePath;
    String? previousImagePath;
    if (options.replaceActressImage && page.details.avatarUrl != null) {
      try {
        previousImagePath = (await db.getActressById(
          actressId,
        ))?['img_path']?.toString();
        final version = DateTime.now().microsecondsSinceEpoch;
        imagePath = await actressImageDownloader.download(
          page.details.avatarUrl!,
          path.join(
            imageDirectory,
            'actresses',
            'actress_${actressId}_$version.jpg',
          ),
        );
      } catch (_) {
        imagePath = null;
      }
    }

    if (!options.syncDetails && imagePath == null) {
      return;
    }

    final source = page.details;
    final details = ScrapedActressDetails(
      name: options.syncDetails ? source.name : null,
      imagePath: imagePath,
      birthDate: options.syncDetails ? source.birthDate : null,
      height: options.syncDetails ? source.height : null,
      cup: options.syncDetails ? source.cup : null,
      bust: options.syncDetails ? source.bust : null,
      waist: options.syncDetails ? source.waist : null,
      hip: options.syncDetails ? source.hip : null,
    );
    final updated = await db.syncActressDetails(
      actressId: actressId,
      details: details,
      missingOnly: options.fillMissingOnly,
      replaceImage: options.replaceActressImage,
    );
    if (!updated && imagePath != null) {
      final file = File(imagePath);
      if (file.existsSync()) {
        await file.delete();
      }
    } else if (updated && imagePath != null) {
      await _deletePreviousManagedAvatar(previousImagePath, imagePath);
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

  Future<void> _saveWork({
    required int actressId,
    required JavBusWorkDetails details,
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
    required JavBusWorkDetails details,
    required bool missingOnly,
    WorksScrapeCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
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
    final safeCode = base64Url
        .encode(utf8.encode(details.code.trim().toUpperCase()))
        .replaceAll('=', '');

    if (cancellationToken?.isCancelled ?? false) {
      throw const _ScrapeCancelled();
    }
    final cardPath = await _downloadWorkImage(
      code: details.code,
      studio: details.studio,
      variant: WorkImageVariant.card,
      targetPath: path.join(imageDirectory, 'works', '${safeCode}_card.jpg'),
      currentPath: currentCard,
      missingOnly: missingOnly,
    );
    if (cancellationToken?.isCancelled ?? false) {
      throw const _ScrapeCancelled();
    }
    final detailPath = await _downloadWorkImage(
      code: details.code,
      studio: details.studio,
      variant: WorkImageVariant.detail,
      targetPath: path.join(imageDirectory, 'works', '${safeCode}_detail.jpg'),
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
    required String code,
    required String? studio,
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
    try {
      await workImageDownloader.downloadToFile(
        code: code,
        studio: studio,
        variant: variant,
        targetPath: targetPath,
      );
      return targetPath;
    } catch (_) {
      return currentPath.isEmpty ? null : currentPath;
    }
  }

  void _notify(
    void Function(WorksScrapeProgress progress)? callback,
    int current,
    int total,
    int saved,
    int excluded,
    int failed,
  ) {
    callback?.call(
      WorksScrapeProgress(
        current: current,
        total: total,
        saved: saved,
        excluded: excluded,
        failed: failed,
      ),
    );
  }
}

class _ScrapeCancelled implements Exception {
  const _ScrapeCancelled();
}
