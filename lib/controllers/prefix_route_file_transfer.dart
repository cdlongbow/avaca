import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

const maxPrefixRouteFileBytes = 5 * 1024 * 1024;

abstract interface class PrefixRouteFilePicker {
  Future<Uint8List?> pickImport({required String dialogTitle});

  Future<String?> saveExport({
    required Uint8List bytes,
    required String fileName,
    required String dialogTitle,
  });
}

class PlatformPrefixRouteFilePicker implements PrefixRouteFilePicker {
  const PlatformPrefixRouteFilePicker();

  @override
  Future<Uint8List?> pickImport({required String dialogTitle}) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final filePath = file.path;
    if (filePath != null && filePath.isNotEmpty) {
      return _bounded(await File(filePath).readAsBytes());
    }
    if (file.bytes != null) return _bounded(file.bytes!);
    final stream = file.readStream;
    if (stream != null) {
      final builder = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in stream) {
        length += chunk.length;
        if (length > maxPrefixRouteFileBytes) {
          throw StateError('The Prefix route file is too large.');
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    }
    throw StateError('The Prefix route file could not be read.');
  }

  @override
  Future<String?> saveExport({
    required Uint8List bytes,
    required String fileName,
    required String dialogTitle,
  }) {
    return FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: _bounded(bytes),
    );
  }

  Uint8List _bounded(List<int> bytes) {
    if (bytes.length > maxPrefixRouteFileBytes) {
      throw StateError('The Prefix route file is too large.');
    }
    return Uint8List.fromList(bytes);
  }
}
