import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:avaca/library/library_models.dart';

void main() {
  test('portable ids are RFC 4122 version 4 shaped', () {
    final id = PortableIdGenerator(random: Random(7)).next();
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(id),
      isTrue,
    );
  });

  test('resolution labels use stream height and rational fps', () {
    const probe = MediaProbeResult(
      width: 1920,
      height: 1080,
      frameRateNumerator: 30000,
      frameRateDenominator: 1001,
      durationMs: 60000,
      container: 'matroska',
      codec: 'h264',
      backend: 'test',
      backendVersion: '1',
      selectedStreamIndex: 0,
    );
    expect(probe.resolutionLabel, '1080p');
    expect(probe.frameRate, closeTo(29.970029, 0.000001));
    expect(probe.isUsable, isTrue);
  });

  test('info schema round trips relative media paths', () {
    final document = LibraryInfoDocument(
      schemaVersion: 1,
      workId: 'work-id',
      code: 'ABC-123',
      metadata: const {'title': 'Title'},
      primaryActressId: 'actress-id',
      performers: const [
        {'actressId': 'actress-id', 'name': 'Actress'},
      ],
      images: const {'cover': 'images/cover.jpg'},
      media: [
        LibraryMediaRecord(
          mediaId: 'media-id',
          workId: 'work-id',
          relativePath: 'ABC-123-RUC-CD1.mp4',
          fileName: 'ABC-123-RUC-CD1.mp4',
          originalFileName: '[FHD] ABC00123-RUC-CD1.mp4',
          variant: 'RUC',
          variantType: 'leak',
          hasChineseSubtitles: true,
          partNumber: 1,
          partLabel: 'CD1',
          width: 1920,
          height: 1080,
          resolutionLabel: '1080p',
          frameRateNumerator: 30000,
          frameRateDenominator: 1001,
          frameRateDecimal: 29.970029,
          durationMs: 1000,
          container: 'mp4',
          codec: 'h264',
          fileSizeBytes: 10,
          sha256: 'hash',
          sourceFileCreatedAt: DateTime.utc(2026, 8, 21),
          importedAt: DateTime.utc(2026, 8, 28),
          probeBackend: 'test',
          probeVersion: '1',
          parserVersion: 1,
        ),
      ],
      scrape: const {'source': 'test'},
      libraryRelativePath: 'Actress/ABC-123',
    );
    final decoded = LibraryInfoDocument.fromJson(document.toJson());

    expect(decoded.libraryRelativePath, 'Actress/ABC-123');
    expect(decoded.media.single.relativePath, 'ABC-123-RUC-CD1.mp4');
    expect(decoded.media.single.originalFileName, '[FHD] ABC00123-RUC-CD1.mp4');
  });
}
