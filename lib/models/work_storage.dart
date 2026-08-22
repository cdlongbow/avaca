enum WorkStorageFilter { all, stored, notStored }

class WorkStorageRecord {
  const WorkStorageRecord({
    this.isStored = false,
    this.quality = defaultQuality,
    this.frameRate = defaultFrameRate,
  });

  static const qualities = <String>['2K', '1080', '720'];
  static const frameRates = <int>[30, 60];
  static const defaultQuality = '1080';
  static const defaultFrameRate = 60;

  final bool isStored;
  final String quality;
  final int frameRate;

  String get compactLabel => '$quality/$frameRate';

  WorkStorageRecord copyWith({
    bool? isStored,
    String? quality,
    int? frameRate,
  }) {
    return WorkStorageRecord(
      isStored: isStored ?? this.isStored,
      quality: quality ?? this.quality,
      frameRate: frameRate ?? this.frameRate,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkStorageRecord &&
        other.isStored == isStored &&
        other.quality == quality &&
        other.frameRate == frameRate;
  }

  @override
  int get hashCode => Object.hash(isStored, quality, frameRate);

  Map<String, Object?> toDatabaseMap() {
    return {
      'is_stored': isStored ? 1 : 0,
      'storage_quality': quality,
      'storage_frame_rate': frameRate,
    };
  }

  static WorkStorageRecord fromDatabase(Map<String, Object?> data) {
    final rawStored = data['is_stored'];
    final isStored = switch (rawStored) {
      true => true,
      num value => value != 0,
      String value => value == '1' || value.toLowerCase() == 'true',
      _ => false,
    };
    final rawQuality = data['storage_quality']?.toString();
    final quality = qualities.contains(rawQuality)
        ? rawQuality!
        : defaultQuality;
    final rawFrameRate = data['storage_frame_rate'];
    final frameRate = rawFrameRate is num && frameRates.contains(rawFrameRate)
        ? rawFrameRate.toInt()
        : defaultFrameRate;
    return WorkStorageRecord(
      isStored: isStored,
      quality: quality,
      frameRate: frameRate,
    );
  }
}
