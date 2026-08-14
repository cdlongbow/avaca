import 'dart:io';

import 'package:avaca/services/javbus/work_image_downloader.dart';
import 'package:avaca/services/javbus/work_image_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  group('image URL policy', () {
    const policy = WorkImagePolicy();

    test('keeps the six approved endpoint forms allowlisted', () {
      expect(
        approvedWorkImageEndpointExamples
            .map(Uri.parse)
            .every(isApprovedWorkImageUri),
        isTrue,
      );
      expect(
        isApprovedWorkImageUri(
          Uri.parse('https://www.javbus.com/pics/cover/ssis00875.jpg'),
        ),
        isFalse,
      );
      expect(
        isApprovedWorkImageUri(
          Uri.parse(
            'https://awsimgsrc.dmm.co.jp/p_package/ssis00875/ssis00875ps.jpg',
          ),
        ),
        isFalse,
      );
    });

    test('maps representative code families to one deterministic token', () {
      const cases = {
        'SONE-833': 'sone00833',
        'SSIS-875': 'ssis00875',
        'SSNI-190': 'ssni00190',
        'SIVR-303': 'sivr00303',
        'IPX-100': 'ipx00100',
        'MIAA-001': 'miaa00001',
        'STARS-859': 'stars00859',
        'START-618': '1start00618',
        'START00023': '1start00023',
        'SDJS-380': '1sdjs00380',
        'DEVR-039': 'h_1711devr00039',
        'REBD-975': 'h_346rebd00975',
      };

      for (final entry in cases.entries) {
        final urls = policy.urlsFor(code: entry.key);
        final path = urls.card.pathSegments;
        expect(path[path.length - 2], entry.value);
        expect(path.last, entry.value + 'ps.jpg');
        expect(isApprovedWorkImageUri(urls.card), isTrue);
        expect(isApprovedWorkImageUri(urls.detail), isTrue);
      }
    });

    test('normalizes separatorless SSIS and START forms without aliases', () {
      expect(
        policy.urlsFor(code: 'SSIS875').card,
        policy.urlsFor(code: 'SSIS-875').card,
      );
      expect(
        policy.urlsFor(code: 'START00023').card,
        policy.urlsFor(code: 'START-023').card,
      );
      expect(
        policy.urlsFor(code: 'SIVR00303').card,
        policy.urlsFor(code: 'SIVR-00303').card,
      );
    });

    test('builds the exact Prestige endpoints without number padding', () {
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

    test(
      'uses the registered Prestige route when studio metadata is missing',
      () {
        final urls = policy.urlsFor(code: 'ABF-183');

        expect(urls.source, WorkImageSource.mgstage);
        expect(
          urls.card.toString(),
          'https://image.mgstage.com/images/prestige/abf/183/'
          'pf_e_abf-183.jpg',
        );
      },
    );

    test('refuses an unregistered publisher prefix instead of guessing', () {
      expect(
        () => policy.urlsFor(code: 'ZZZZ-001'),
        throwsA(isA<FormatException>()),
      );
    });

    test('uses visible work code for local filenames, not network token', () {
      expect(
        policy.fileNameFor(code: 'START-489', variant: WorkImageVariant.card),
        'start00489ps.jpg',
      );
      expect(
        policy.fileNameFor(code: 'REBD-975', variant: WorkImageVariant.detail),
        'rebd00975pl.jpg',
      );
    });
  });

  test(
    'downloads only the selected approved URL and has no fallback',
    () async {
      final valid = image.encodePng(image.Image(width: 300, height: 450));
      final transport = _FakeBinaryTransport([
        BinaryResponse(statusCode: 200, bodyBytes: valid),
      ]);

      final result = await WorkImageDownloader(
        transport: transport,
      ).fetch(code: 'SSIS-875', variant: WorkImageVariant.detail);

      expect(result.bytes, valid);
      expect(transport.requested, hasLength(1));
      expect(
        transport.requested.single.toString(),
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        'ssis00875/ssis00875pl.jpg',
      );
    },
  );

  test(
    'reports one failed approved URL without trying another family',
    () async {
      final transport = _FakeBinaryTransport([
        const BinaryResponse(statusCode: 404, bodyBytes: []),
      ]);

      await expectLater(
        WorkImageDownloader(
          transport: transport,
        ).fetch(code: 'REBD-975', variant: WorkImageVariant.card),
        throwsA(isA<WorkImageDownloadException>()),
      );
      expect(transport.requested, hasLength(1));
      expect(transport.requested.single.toString(), contains('h_346rebd00975'));
    },
  );

  test('rejects placeholder dimensions without fallback', () async {
    final placeholder = image.encodePng(image.Image(width: 90, height: 122));
    final transport = _FakeBinaryTransport([
      BinaryResponse(statusCode: 200, bodyBytes: placeholder),
    ]);

    await expectLater(
      WorkImageDownloader(
        transport: transport,
      ).fetch(code: 'START-196', variant: WorkImageVariant.card),
      throwsA(isA<WorkImageDownloadException>()),
    );
    expect(transport.requested, hasLength(1));
    expect(transport.requested.single.toString(), contains('1start00196'));
  });

  test('writes a downloaded image to the requested local file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca_image_download_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final bytes = image.encodePng(image.Image(width: 300, height: 450));
    final target =
        directory.path +
        Platform.pathSeparator +
        'nested' +
        Platform.pathSeparator +
        'card.png';

    await WorkImageDownloader(
      transport: _FakeBinaryTransport([
        BinaryResponse(statusCode: 200, bodyBytes: bytes),
      ]),
    ).downloadToFile(
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
