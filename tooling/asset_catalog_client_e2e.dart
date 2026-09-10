import 'dart:io';

import 'package:avaca_client/avaca_client.dart';
import 'package:avaca_domain/avaca_domain.dart';
import 'package:avaca_remote_core/avaca_remote_core.dart';

const _serverId = 'e2e-server-v2';
const _clientId = 'e2e-client-v2';
const _workId = AvacaWorkId('work-e2e');
const _missingMediaId = AvacaMediaId('media-e2e-missing');
const _coverAssetId = 'asset-e2e-cover';

Future<void> main(List<String> args) async {
  if (!Platform.isWindows || args.length != 2) {
    stderr.writeln(
      'usage: dart tooling/asset_catalog_client_e2e.dart '
      '<server-leaf-sha256-64-hex> <port>',
    );
    exitCode = 2;
    return;
  }

  final serverPin = _parseHex(args[0], 32, 'server leaf SHA-256');
  final port = int.parse(args[1]);
  final pairingSecret = List<int>.generate(
    32,
    (index) => (0x40 + index) & 0xff,
  );
  final transport = AvacaMsQuicTransport.client(
    certificateSha256Pin: serverPin,
  );
  AvacaRemoteCatalogClient? catalog;
  try {
    catalog = await AvacaRemoteCatalogClient.connect(
      transport: transport,
      endpoint: AvacaRemoteEndpoint(host: '127.0.0.1', port: port),
      clientId: _clientId,
      expectedServerId: _serverId,
      pairingSecret: pairingSecret,
    );
    final detail = await catalog.getWorkDetail(_workId);
    final missing = detail.media.where(
      (media) => media.mediaId == _missingMediaId,
    );
    if (detail.coverResourceId != _coverAssetId ||
        missing.length != 1 ||
        missing.single.availability != AvacaMediaAvailability.unavailable) {
      throw StateError('asset/missing media detail was not preserved');
    }
    stdout.writeln('CHILD_ASSET_DETAIL_PASS');

    final opened = await catalog.openAsset(
      _coverAssetId,
      revision: 0,
      offset: 1,
      length: 3,
    );
    if (opened.assetId != _coverAssetId ||
        opened.revision != 0 ||
        opened.offset != 1 ||
        opened.mimeType != 'image/jpeg' ||
        opened.eof ||
        opened.bytes.length != 3 ||
        opened.bytes[0] != 0xd8 ||
        opened.bytes[1] != 0xff ||
        opened.bytes[2] != 0xe0) {
      throw StateError('opaque artwork range response was invalid');
    }
    stdout.writeln('CHILD_ASSET_RANGE_PASS');

    try {
      await catalog.createPlaybackSession(_missingMediaId);
      throw StateError('missing media unexpectedly opened for playback');
    } on AvacaRemoteException {
      stdout.writeln('CHILD_MISSING_MEDIA_REJECTED');
    }
  } finally {
    await catalog?.close();
    await transport.close();
    pairingSecret.fillRange(0, pairingSecret.length, 0);
    serverPin.fillRange(0, serverPin.length, 0);
  }
}

List<int> _parseHex(String value, int expectedBytes, String label) {
  if (value.length != expectedBytes * 2 ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
    throw FormatException('$label must contain $expectedBytes bytes of hex');
  }
  return List<int>.generate(
    expectedBytes,
    (index) => int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
  );
}
