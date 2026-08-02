class Work {
  const Work({
    required this.code,
    required this.title,
    this.releaseDate,
    this.durationMinutes,
    this.studio,
    this.publisher,
    this.series,
    this.cardImagePath,
    this.detailImagePath,
  });

  final String code;
  final String title;
  final String? releaseDate;
  final int? durationMinutes;
  final String? studio;
  final String? publisher;
  final String? series;
  final String? cardImagePath;
  final String? detailImagePath;

  Map<String, Object?> toDatabaseMap() {
    return {
      'code': code.trim().toUpperCase(),
      'title': title.trim(),
      'release_date': _clean(releaseDate),
      'duration_minutes': durationMinutes,
      'studio': _clean(studio),
      'publisher': _clean(publisher),
      'series': _clean(series),
      'card_image_path': _clean(cardImagePath),
      'detail_image_path': _clean(detailImagePath),
    };
  }

  static String? _clean(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}
