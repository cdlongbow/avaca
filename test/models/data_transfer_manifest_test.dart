import 'dart:convert';

import 'package:avaca/models/data_transfer_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v1 manifest round-trips with archive-local identities', () {
    const manifest = DataTransferManifest(
      exportedAt: '2026-08-10T00:00:00Z',
      actresses: [
        DataTransferActress(
          id: 'a000001',
          name: '測試演員',
          avatarAssetId: 'asset000001',
          birthDate: '1999-01-01',
          mainType: '無碼',
          tags: 'tag',
          memo: 'memo',
          height: '160',
          weight: '48',
          bwh: '85-55-85',
          cup: 'F',
          aliases: ['測試別名'],
        ),
      ],
      works: [
        DataTransferWork(
          id: 'w000001',
          code: 'ABC-001',
          title: '測試作品',
          releaseDate: '2026-01-01',
          durationMinutes: 120,
          studio: 'Studio',
          publisher: 'Publisher',
          series: 'Series',
          cardImageAssetId: 'asset000001',
          detailImageAssetId: null,
          createdAt: null,
          modifiedAt: null,
        ),
      ],
      relations: [
        DataTransferRelation(actressId: 'a000001', workId: 'w000001'),
      ],
      assets: [
        DataTransferAsset(
          id: 'asset000001',
          path: 'assets/asset000001.jpg',
          size: 3,
          sha256:
              'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        ),
      ],
    );

    final decoded = DataTransferManifest.fromJson(
      jsonDecode(manifest.encode()),
    );
    expect(decoded.toJson(), manifest.toJson());
  });

  test('rejects future versions and unknown references', () {
    expect(
      () => DataTransferManifest.fromJson({
        'format': DataTransferLimits.format,
        'version': 2,
        'exportedAt': 'now',
        'actresses': [],
        'works': [],
        'relations': [],
        'assets': [],
      }),
      throwsFormatException,
    );

    expect(
      () => DataTransferManifest.fromJson({
        'format': DataTransferLimits.format,
        'version': DataTransferLimits.version,
        'exportedAt': 'now',
        'actresses': [
          {
            'id': 'a000001',
            'name': '演員',
            'avatarAssetId': 'missing',
            'aliases': [],
          },
        ],
        'works': [],
        'relations': [],
        'assets': [],
      }),
      throwsFormatException,
    );
  });
}
