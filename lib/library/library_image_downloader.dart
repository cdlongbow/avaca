import '../services/javbus/work_image_downloader.dart';
import '../services/javbus/work_image_policy.dart';
import '../services/scrape/scrape_models.dart';

class LibraryImageDownloadResult {
  const LibraryImageDownloadResult({this.coverSource, this.posterSource});

  final Uri? coverSource;
  final Uri? posterSource;
}

abstract interface class LibraryImageDownloader {
  Future<LibraryImageDownloadResult> download({
    required ScrapeWorkDetails details,
    required String destinationDirectory,
  });

  void close();
}

/// Adapts AVACA's existing, policy-checked work-image routes to portable
/// library image files.  The importer only calls it when the scraper supplied
/// image evidence; an absent image is therefore a valid null result.
class WorkImageLibraryDownloader implements LibraryImageDownloader {
  WorkImageLibraryDownloader({WorkImageDownloader? downloader})
    : _downloader = downloader ?? WorkImageDownloader();

  final WorkImageDownloader _downloader;

  @override
  Future<LibraryImageDownloadResult> download({
    required ScrapeWorkDetails details,
    required String destinationDirectory,
  }) async {
    final evidence = <Uri>{
      ...details.imageUris,
      ...details.originalImageEvidenceUris,
    }.toList(growable: false);
    if (evidence.isEmpty) return const LibraryImageDownloadResult();
    final cover = await _downloader.downloadToFile(
      code: details.code,
      studio: details.studio,
      publisher: details.publisher,
      originalImageEvidenceUris: evidence,
      variant: WorkImageVariant.card,
      targetPath: '$destinationDirectory/images/cover.jpg',
    );
    final poster = await _downloader.downloadToFile(
      code: details.code,
      studio: details.studio,
      publisher: details.publisher,
      originalImageEvidenceUris: evidence,
      variant: WorkImageVariant.detail,
      targetPath: '$destinationDirectory/images/poster.jpg',
    );
    return LibraryImageDownloadResult(
      coverSource: cover.sourceUri,
      posterSource: poster.sourceUri,
    );
  }

  @override
  void close() => _downloader.close();
}

class NoopLibraryImageDownloader implements LibraryImageDownloader {
  const NoopLibraryImageDownloader();

  @override
  Future<LibraryImageDownloadResult> download({
    required ScrapeWorkDetails details,
    required String destinationDirectory,
  }) async => const LibraryImageDownloadResult();

  @override
  void close() {}
}
