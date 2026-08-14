import 'dart:io';

import 'package:avaca/services/javbus/work_image_downloader.dart';
import 'package:avaca/services/javbus/work_image_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  group('image URL policy', () {
    const policy = WorkImagePolicy();

    test('builds padded lowercase DMM card and detail URLs', () {
      final urls = policy.urlsFor(code: 'SONE-833');

      expect(
        urls.card.toString(),
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        'sone00833/sone00833ps.jpg',
      );
      expect(
        urls.detail.toString(),
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        'sone00833/sone00833pl.jpg',
      );
      expect(urls.source, WorkImageSource.dmm);
    });

    test('builds番號-based local filenames for card and detail images', () {
      expect(
        policy.fileNameFor(code: 'START-489', variant: WorkImageVariant.card),
        'start00489ps.jpg',
      );
      expect(
        policy.fileNameFor(code: 'START-489', variant: WorkImageVariant.detail),
        'start00489pl.jpg',
      );
    });

    test('uses one image identity for leading-one START aliases', () {
      final alias = policy.urlsFor(code: '1start00408');
      final canonical = policy.urlsFor(code: 'START-408');

      expect(alias.card, canonical.card);
      expect(alias.detail, canonical.detail);
      expect(
        policy.fileNameFor(code: '1start00408', variant: WorkImageVariant.card),
        'start00408ps.jpg',
      );
    });

    test('uses one image identity for generic numeric-leading aliases', () {
      final aliasPairs = [
        ('1stzy00017', 'STZY-017'),
        ('3DSVR-1947', 'DSVR-1947'),
        ('SSIS875', 'SSIS-875'),
        ('SIVR00303', 'SIVR-303'),
        ('SONE00687', 'SONE-687'),
        ('RBB00321', 'RBB-321'),
      ];

      for (final (aliasCode, canonicalCode) in aliasPairs) {
        final alias = policy.urlsFor(code: aliasCode);
        final canonical = policy.urlsFor(code: canonicalCode);

        expect(alias.card, canonical.card);
        expect(alias.detail, canonical.detail);
      }
    });

    test('builds the h_346 DMM URLs for REBD codes', () {
      final cases = {
        'REBD-975': 'h_346rebd00975',
        'REBD-1048': 'h_346rebd01048',
      };

      for (final entry in cases.entries) {
        final urls = policy.urlsFor(code: entry.key);
        expect(
          urls.card.toString(),
          'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
          '${entry.value}/${entry.value}ps.jpg',
        );
        expect(
          urls.detail.toString(),
          'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
          '${entry.value}/${entry.value}pl.jpg',
        );
        expect(urls.source, WorkImageSource.dmm);
      }
    });

    test('ignores V T and VT edition suffixes in DMM image codes', () {
      final cases = {
        'STARS-859-V': 'stars00859',
        'STARS-757-T': 'stars00757',
        'STARS-715-VT': 'stars00715',
      };

      for (final entry in cases.entries) {
        final urls = policy.urlsFor(code: entry.key);
        expect(
          urls.detail.toString(),
          'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
          '${entry.value}/${entry.value}pl.jpg',
        );
      }
    });

    test('builds the fourth DMM h2 candidate', () {
      final urls = policy.urlsFor(
        code: 'STARS-685',
        dmmLeadingOne: true,
        dmmTrailingH2: true,
      );

      expect(
        urls.card.toString(),
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        '1stars00685h2/1stars00685h2ps.jpg',
      );
      expect(
        urls.detail.toString(),
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        '1stars00685h2/1stars00685h2pl.jpg',
      );
    });

    test('uses MGStage for Prestige studio without padding the number', () {
      final urls = policy.urlsFor(code: 'ABF-183', studio: 'プレステージ');

      expect(
        urls.card.toString(),
        'https://image.mgstage.com/images/prestige/abf/183/'
        'pf_e_abf-183.jpg',
      );
      expect(
        urls.detail.toString(),
        'https://image.mgstage.com/images/prestige/abf/183/'
        'pb_e_abf-183.jpg',
      );
      expect(urls.source, WorkImageSource.mgstage);
    });
  });

  test(
    'DMM 90x122 placeholder retries with a leading one image code',
    () async {
      final placeholder = image.encodePng(image.Image(width: 90, height: 122));
      final valid = image.encodePng(image.Image(width: 300, height: 450));
      final transport = _FakeBinaryTransport([
        BinaryResponse(statusCode: 200, bodyBytes: placeholder),
        BinaryResponse(statusCode: 200, bodyBytes: valid),
      ]);
      final downloader = WorkImageDownloader(transport: transport);

      final result = await downloader.fetch(
        code: 'START-196',
        variant: WorkImageVariant.card,
      );

      expect(result.bytes, valid);
      expect(
        result.sourceUri.toString(),
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        '1start00196/1start00196ps.jpg',
      );
      expect(transport.requested.map((uri) => uri.toString()), [
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
            'start00196/start00196ps.jpg',
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
            '1start00196/1start00196ps.jpg',
      ]);
    },
  );

  test(
    'DMM retries with a leading one and trailing v as the third candidate',
    () async {
      final placeholder = image.encodePng(image.Image(width: 90, height: 122));
      final valid = image.encodePng(image.Image(width: 1700, height: 1200));
      final transport = _FakeBinaryTransport([
        BinaryResponse(statusCode: 200, bodyBytes: placeholder),
        BinaryResponse(statusCode: 200, bodyBytes: placeholder),
        BinaryResponse(statusCode: 200, bodyBytes: valid),
      ]);
      final downloader = WorkImageDownloader(transport: transport);

      final result = await downloader.fetch(
        code: 'START-135',
        variant: WorkImageVariant.detail,
      );

      expect(result.bytes, valid);
      expect(
        result.sourceUri.toString(),
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        '1start00135v/1start00135vpl.jpg',
      );
      expect(transport.requested.map((uri) => uri.toString()), [
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
            'start00135/start00135pl.jpg',
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
            '1start00135/1start00135pl.jpg',
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
            '1start00135v/1start00135vpl.jpg',
      ]);
    },
  );

  test('DMM retries with h2 as the fourth candidate', () async {
    final placeholder = image.encodePng(image.Image(width: 90, height: 122));
    final valid = image.encodePng(image.Image(width: 2184, height: 1542));
    final transport = _FakeBinaryTransport([
      BinaryResponse(statusCode: 200, bodyBytes: placeholder),
      BinaryResponse(statusCode: 200, bodyBytes: placeholder),
      BinaryResponse(statusCode: 200, bodyBytes: placeholder),
      BinaryResponse(statusCode: 200, bodyBytes: valid),
    ]);

    final result = await WorkImageDownloader(
      transport: transport,
    ).fetch(code: 'STARS-685', variant: WorkImageVariant.detail);

    expect(result.bytes, valid);
    expect(
      result.sourceUri.toString(),
      'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
      '1stars00685h2/1stars00685h2pl.jpg',
    );
    expect(transport.requested.map((uri) => uri.toString()), [
      'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
          'stars00685/stars00685pl.jpg',
      'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
          '1stars00685/1stars00685pl.jpg',
      'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
          '1stars00685v/1stars00685vpl.jpg',
      'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
          '1stars00685h2/1stars00685h2pl.jpg',
    ]);
  });

  test('REBD does not repeat its special DMM URL as fallbacks', () async {
    final transport = _FakeBinaryTransport([
      const BinaryResponse(statusCode: 404, bodyBytes: []),
    ]);
    final downloader = WorkImageDownloader(transport: transport);

    await expectLater(
      downloader.fetch(code: 'REBD-975', variant: WorkImageVariant.card),
      throwsA(isA<WorkImageDownloadException>()),
    );
    expect(transport.requested, hasLength(1));
    expect(
      transport.requested.single.toString(),
      'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
      'h_346rebd00975/h_346rebd00975ps.jpg',
    );
  });

  test('MGStage failure does not guess a DMM URL', () async {
    final transport = _FakeBinaryTransport([
      const BinaryResponse(statusCode: 404, bodyBytes: []),
    ]);
    final downloader = WorkImageDownloader(transport: transport);

    await expectLater(
      downloader.fetch(
        code: 'ABF-183',
        studio: 'プレステージ',
        variant: WorkImageVariant.detail,
      ),
      throwsA(isA<WorkImageDownloadException>()),
    );
    expect(transport.requested, hasLength(1));
    expect(transport.requested.single.host, 'image.mgstage.com');
  });

  test('returns a valid primary image without fallback', () async {
    final valid = image.encodePng(image.Image(width: 300, height: 450));
    final transport = _FakeBinaryTransport([
      BinaryResponse(statusCode: 200, bodyBytes: valid),
    ]);

    final result = await WorkImageDownloader(
      transport: transport,
    ).fetch(code: 'SONE-833', variant: WorkImageVariant.detail);

    expect(result.bytes, valid);
    expect(transport.requested, hasLength(1));
  });

  test(
    'rejects oversized image dimensions before accepting a download',
    () async {
      final oversized = image.encodePng(image.Image(width: 10001, height: 1));
      final valid = image.encodePng(image.Image(width: 300, height: 450));
      final transport = _FakeBinaryTransport([
        BinaryResponse(statusCode: 200, bodyBytes: oversized),
        BinaryResponse(statusCode: 200, bodyBytes: valid),
      ]);

      final result = await WorkImageDownloader(
        transport: transport,
      ).fetch(code: 'SONE-833', variant: WorkImageVariant.card);

      expect(result.bytes, valid);
      expect(transport.requested, hasLength(2));
    },
  );

  test('throws after all DMM attempts return invalid images', () async {
    final invalid = image.encodePng(image.Image(width: 90, height: 122));
    final transport = _FakeBinaryTransport([
      BinaryResponse(statusCode: 200, bodyBytes: invalid),
      const BinaryResponse(statusCode: 500, bodyBytes: []),
      const BinaryResponse(statusCode: 404, bodyBytes: []),
      const BinaryResponse(statusCode: 404, bodyBytes: []),
    ]);

    await expectLater(
      WorkImageDownloader(
        transport: transport,
      ).fetch(code: 'START-196', variant: WorkImageVariant.card),
      throwsA(isA<WorkImageDownloadException>()),
    );
    expect(transport.requested, hasLength(4));
  });

  test('writes downloaded bytes to the requested local file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca_image_download_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final bytes = image.encodePng(image.Image(width: 300, height: 450));
    final target =
        '${directory.path}${Platform.pathSeparator}nested'
        '${Platform.pathSeparator}card.png';
    final downloader = WorkImageDownloader(
      transport: _FakeBinaryTransport([
        BinaryResponse(statusCode: 200, bodyBytes: bytes),
      ]),
    );

    await downloader.downloadToFile(
      code: 'SONE-833',
      variant: WorkImageVariant.card,
      targetPath: target,
    );

    expect(await File(target).readAsBytes(), bytes);
  });
}

class _FakeBinaryTransport implements BinaryTransport {
  _FakeBinaryTransport(this.responses);

  final List<BinaryResponse> responses;
  final List<Uri> requested = [];

  @override
  Future<BinaryResponse> get(Uri uri) async {
    requested.add(uri);
    return responses[requested.length - 1];
  }
}
