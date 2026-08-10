import 'dart:typed_data';

import 'data_transfer_manifest.dart';

enum DataTransferPhase {
  idle,
  preparing,
  reviewingDuplicates,
  writing,
  success,
  error,
}

enum DataTransferDuplicateResolution { keepExisting, useImported }

class DataTransferProgress {
  const DataTransferProgress({required this.phase, this.completed, this.total});

  final DataTransferPhase phase;
  final int? completed;
  final int? total;

  double? get value {
    final current = completed;
    final maximum = total;
    if (current == null || maximum == null || maximum <= 0) return null;
    return (current / maximum).clamp(0, 1).toDouble();
  }
}

class DataTransferSummary {
  const DataTransferSummary({
    this.actresses = 0,
    this.works = 0,
    this.images = 0,
    this.duplicatesResolved = 0,
    this.skippedImages = 0,
    this.destinationPath,
  });

  final int actresses;
  final int works;
  final int images;
  final int duplicatesResolved;
  final int skippedImages;
  final String? destinationPath;
}

class DataTransferDuplicateCandidate {
  const DataTransferDuplicateCandidate({
    required this.imported,
    required this.existingActressId,
    required this.existingName,
    required this.existingImagePath,
    required this.existingWorkCount,
    required this.importedWorkCount,
    required this.importedAvatarBytes,
  });

  final DataTransferActress imported;
  final int existingActressId;
  final String existingName;
  final String? existingImagePath;
  final int existingWorkCount;
  final int importedWorkCount;
  final Uint8List? importedAvatarBytes;
}

class DataTransferException implements Exception {
  const DataTransferException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'DataTransferException($code): $message';
}

class DataTransferCancelled implements Exception {
  const DataTransferCancelled();

  @override
  String toString() => 'Data transfer cancelled.';
}

class DataTransferOperationResult {
  const DataTransferOperationResult({
    required this.cancelled,
    this.summary,
    this.error,
  });

  final bool cancelled;
  final DataTransferSummary? summary;
  final DataTransferException? error;

  bool get succeeded => !cancelled && error == null;
}
