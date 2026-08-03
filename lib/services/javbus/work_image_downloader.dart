import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image;

import '../http_safety.dart';
import '../safe_image.dart';
import 'work_image_policy.dart';

class BinaryResponse {
  const BinaryResponse({required this.statusCode, required this.bodyBytes});

  final int statusCode;
  final List<int> bodyBytes;
}

abstract interface class BinaryTransport {
  Future<BinaryResponse> get(Uri uri);
}

class HttpBinaryTransport implements BinaryTransport {
  HttpBinaryTransport({
    http.Client? client,
    Set<String> allowedHosts = const {
      'awsimgsrc.dmm.co.jp',
      'image.mgstage.com',
    },
    Duration timeout = const Duration(seconds: 20),
    int maxBytes = 15 * 1024 * 1024,
  }) : _fetcher = SafeHttpFetcher(
         client: client,
         allowedHosts: allowedHosts,
         timeout: timeout,
         maxBytes: maxBytes,
       );

  final SafeHttpFetcher _fetcher;

  @override
  Future<BinaryResponse> get(Uri uri) async {
    final response = await _fetcher.get(uri);
    return BinaryResponse(
      statusCode: response.statusCode,
      bodyBytes: response.bodyBytes,
    );
  }

  void close() {
    _fetcher.close();
  }
}

class DownloadedWorkImage {
  const DownloadedWorkImage({required this.bytes, required this.sourceUri});

  final Uint8List bytes;
  final Uri sourceUri;
}

class WorkImageDownloadException implements Exception {
  const WorkImageDownloadException(this.uri);

  final Uri uri;

  @override
  String toString() => 'Could not download a valid work image: $uri';
}

class WorkImageDownloader {
  WorkImageDownloader({
    BinaryTransport? transport,
    WorkImagePolicy policy = const WorkImagePolicy(),
  }) : _transport = transport ?? HttpBinaryTransport(),
       _policy = policy;

  final BinaryTransport _transport;
  final WorkImagePolicy _policy;

  void close() {
    final transport = _transport;
    if (transport is HttpBinaryTransport) {
      transport.close();
    }
  }

  Future<DownloadedWorkImage> fetch({
    required String code,
    String? studio,
    required WorkImageVariant variant,
  }) async {
    final urls = _policy.urlsFor(code: code, studio: studio);
    final primaryUri = urls.forVariant(variant);
    final primary = await _transport.get(primaryUri);
    if (_isValid(primary)) {
      return DownloadedWorkImage(
        bytes: Uint8List.fromList(primary.bodyBytes),
        sourceUri: primaryUri,
      );
    }

    if (urls.source == WorkImageSource.dmm) {
      final fallbackUri = _policy
          .urlsFor(code: code, studio: studio, dmmLeadingOne: true)
          .forVariant(variant);
      final fallback = await _transport.get(fallbackUri);
      if (_isValid(fallback)) {
        return DownloadedWorkImage(
          bytes: Uint8List.fromList(fallback.bodyBytes),
          sourceUri: fallbackUri,
        );
      }
      final trailingVUri = _policy
          .urlsFor(
            code: code,
            studio: studio,
            dmmLeadingOne: true,
            dmmTrailingV: true,
          )
          .forVariant(variant);
      final trailingV = await _transport.get(trailingVUri);
      if (_isValid(trailingV)) {
        return DownloadedWorkImage(
          bytes: Uint8List.fromList(trailingV.bodyBytes),
          sourceUri: trailingVUri,
        );
      }
      final trailingH2Uri = _policy
          .urlsFor(
            code: code,
            studio: studio,
            dmmLeadingOne: true,
            dmmTrailingH2: true,
          )
          .forVariant(variant);
      final trailingH2 = await _transport.get(trailingH2Uri);
      if (_isValid(trailingH2)) {
        return DownloadedWorkImage(
          bytes: Uint8List.fromList(trailingH2.bodyBytes),
          sourceUri: trailingH2Uri,
        );
      }
      throw WorkImageDownloadException(trailingH2Uri);
    }

    throw WorkImageDownloadException(primaryUri);
  }

  Future<DownloadedWorkImage> downloadToFile({
    required String code,
    String? studio,
    required WorkImageVariant variant,
    required String targetPath,
  }) async {
    final downloaded = await fetch(
      code: code,
      studio: studio,
      variant: variant,
    );
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(downloaded.bytes, flush: true);
    return downloaded;
  }

  bool _isValid(BinaryResponse response) {
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        response.bodyBytes.isEmpty) {
      return false;
    }
    final bytes = Uint8List.fromList(response.bodyBytes);
    if (!isSafeDecodableImage(bytes)) {
      return false;
    }
    final decoder = image.findDecoderForData(bytes)!;
    final info = decoder.startDecode(bytes)!;
    return info.width != 90 || info.height != 122;
  }
}
