import 'dart:typed_data';

import 'package:image/image.dart' as image;

bool isSafeDecodableImage(
  Uint8List bytes, {
  int maxDimension = 10000,
  int maxPixels = 25000000,
}) {
  final decoder = image.findDecoderForData(bytes);
  if (decoder == null ||
      (decoder.format != image.ImageFormat.jpg &&
          decoder.format != image.ImageFormat.png &&
          decoder.format != image.ImageFormat.webp)) {
    return false;
  }

  final info = decoder.startDecode(bytes);
  if (info == null ||
      info.width < 1 ||
      info.height < 1 ||
      info.width > maxDimension ||
      info.height > maxDimension ||
      info.width * info.height > maxPixels) {
    return false;
  }

  return decoder.decodeFrame(0) != null;
}
