enum PlayerSubtitleFormat { ass, ssa, other }

final class PlayerSubtitleTrack {
  const PlayerSubtitleTrack({
    required this.id,
    this.title,
    this.language,
    required this.format,
    this.uri,
  });
  final String id;
  final String? title;
  final String? language;
  final PlayerSubtitleFormat format;
  final Uri? uri;

  String get displayLabel {
    final trimmedTitle = title?.trim();
    if (trimmedTitle?.isNotEmpty == true) return trimmedTitle!;

    final trimmedLanguage = language?.trim();
    if (_isUsableLanguage(trimmedLanguage)) return trimmedLanguage!;

    return 'Subtitle $id';
  }

  bool _isUsableLanguage(String? value) {
    if (value == null || value.isEmpty) return false;
    return switch (value.toLowerCase()) {
      'und' || 'unknown' || 'undetermined' => false,
      _ => true,
    };
  }

  String get label => displayLabel;

  @override
  String toString() =>
      'PlayerSubtitleTrack(id: $id, title: $title, language: $language, '
      'format: $format)';
  @override
  bool operator ==(Object other) =>
      other is PlayerSubtitleTrack &&
      other.id == id &&
      other.title == title &&
      other.language == language &&
      other.format == format &&
      other.uri == uri;
  @override
  int get hashCode => Object.hash(id, label, format, uri);
}
