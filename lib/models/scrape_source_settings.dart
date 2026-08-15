import 'dart:convert';

const String scrapeSourceSettingsKey = 'scrape_source_settings';

enum ScrapeSourceId {
  javbus('javbus'),
  minnanoAv('minnanoAv');

  const ScrapeSourceId(this.storageValue);

  final String storageValue;

  static ScrapeSourceId? fromStorage(String? value) {
    for (final source in values) {
      if (source.storageValue == value) {
        return source;
      }
    }
    return null;
  }
}

enum WorksSourceSelection {
  all('all'),
  javbus('javbus'),
  minnanoAv('minnanoAv');

  const WorksSourceSelection(this.storageValue);

  final String storageValue;

  static WorksSourceSelection? fromStorage(String? value) {
    for (final selection in values) {
      if (selection.storageValue == value) {
        return selection;
      }
    }
    return null;
  }
}

final class ScrapeSourceSettings {
  const ScrapeSourceSettings({
    this.actressDetailsSource = ScrapeSourceId.minnanoAv,
    this.worksSource = WorksSourceSelection.javbus,
  });

  const ScrapeSourceSettings.legacyJavBus()
    : actressDetailsSource = ScrapeSourceId.javbus,
      worksSource = WorksSourceSelection.javbus;

  final ScrapeSourceId actressDetailsSource;
  final WorksSourceSelection worksSource;

  String encode() {
    return jsonEncode({
      'actressDetailsSource': actressDetailsSource.storageValue,
      'worksSource': worksSource.storageValue,
    });
  }

  ScrapeSourceSettings copyWith({
    ScrapeSourceId? actressDetailsSource,
    WorksSourceSelection? worksSource,
  }) {
    return ScrapeSourceSettings(
      actressDetailsSource: actressDetailsSource ?? this.actressDetailsSource,
      worksSource: worksSource ?? this.worksSource,
    );
  }

  static ScrapeSourceSettings decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const ScrapeSourceSettings();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const ScrapeSourceSettings();
      }
      final details = ScrapeSourceId.fromStorage(
        decoded['actressDetailsSource']?.toString(),
      );
      final works = WorksSourceSelection.fromStorage(
        decoded['worksSource']?.toString(),
      );
      return ScrapeSourceSettings(
        actressDetailsSource: details ?? ScrapeSourceId.minnanoAv,
        worksSource: works ?? WorksSourceSelection.javbus,
      );
    } on Object {
      return const ScrapeSourceSettings();
    }
  }
}
