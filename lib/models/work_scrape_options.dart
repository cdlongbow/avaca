import 'dart:convert';

class WorkScrapeOptions {
  const WorkScrapeOptions({
    this.syncDetails = true,
    this.replaceActressImage = false,
    this.fillMissingOnly = true,
    this.maxActressCount,
    this.excludedPrefixes = const [],
    this.retryWorkCodes = const [],
  }) : assert(maxActressCount == null || maxActressCount > 0);

  final bool syncDetails;
  final bool replaceActressImage;
  final bool fillMissingOnly;
  final int? maxActressCount;
  final List<String> excludedPrefixes;
  final List<String> retryWorkCodes;

  WorkScrapeOptions copyWith({List<String>? retryWorkCodes}) =>
      WorkScrapeOptions(
        syncDetails: syncDetails,
        replaceActressImage: replaceActressImage,
        fillMissingOnly: fillMissingOnly,
        maxActressCount: maxActressCount,
        excludedPrefixes: excludedPrefixes,
        retryWorkCodes: retryWorkCodes ?? this.retryWorkCodes,
      );

  String encode() {
    return jsonEncode({
      'syncDetails': syncDetails,
      'replaceActressImage': replaceActressImage,
      'fillMissingOnly': fillMissingOnly,
      'maxActressCount': maxActressCount,
      'excludedPrefixes': excludedPrefixes,
      'retryWorkCodes': retryWorkCodes,
    });
  }

  static WorkScrapeOptions decode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const WorkScrapeOptions();
    }

    try {
      final json = jsonDecode(value);
      if (json is! Map<String, dynamic>) {
        return const WorkScrapeOptions();
      }
      final prefixes = json['excludedPrefixes'];
      final rawMaxActressCount = json['maxActressCount'];
      final retryCodes = json['retryWorkCodes'];
      return WorkScrapeOptions(
        syncDetails: json['syncDetails'] is bool
            ? json['syncDetails'] as bool
            : true,
        replaceActressImage: json['replaceActressImage'] is bool
            ? json['replaceActressImage'] as bool
            : false,
        fillMissingOnly: json['fillMissingOnly'] is bool
            ? json['fillMissingOnly'] as bool
            : true,
        maxActressCount: rawMaxActressCount is int && rawMaxActressCount > 0
            ? rawMaxActressCount
            : null,
        excludedPrefixes: prefixes is List
            ? prefixes
                  .whereType<String>()
                  .map((value) => value.trim().toUpperCase())
                  .where((value) => value.isNotEmpty)
                  .toSet()
                  .toList(growable: false)
            : const [],
        retryWorkCodes: retryCodes is List
            ? retryCodes
                  .whereType<String>()
                  .map((value) => value.trim().toUpperCase())
                  .where((value) => value.isNotEmpty)
                  .toSet()
                  .toList(growable: false)
            : const [],
      );
    } on FormatException {
      return const WorkScrapeOptions();
    }
  }
}
