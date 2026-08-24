import 'dart:convert';

import 'scrape_exclusion_policy.dart';

class WorkScrapeOptions {
  const WorkScrapeOptions({
    this.syncDetails = true,
    this.replaceActressImage = false,
    this.fillMissingOnly = true,
    this.excludedPrefixes = const [],
    this.retryWorkCodes = const [],
    this.scrapeAliases = false,
    this.managedFamilyModes = const {},
    this.exactAllows = const [],
  });

  final bool syncDetails;
  final bool replaceActressImage;
  final bool fillMissingOnly;
  final List<String> excludedPrefixes;
  final List<String> retryWorkCodes;
  final bool scrapeAliases;
  final Map<String, ManagedFamilyMode> managedFamilyModes;
  final List<ScrapeExactAllowRule> exactAllows;

  WorkScrapeOptions copyWith({
    List<String>? retryWorkCodes,
    bool? scrapeAliases,
    Map<String, ManagedFamilyMode>? managedFamilyModes,
    List<ScrapeExactAllowRule>? exactAllows,
  }) => WorkScrapeOptions(
    syncDetails: syncDetails,
    replaceActressImage: replaceActressImage,
    fillMissingOnly: fillMissingOnly,
    excludedPrefixes: excludedPrefixes,
    retryWorkCodes: retryWorkCodes ?? this.retryWorkCodes,
    scrapeAliases: scrapeAliases ?? this.scrapeAliases,
    managedFamilyModes: managedFamilyModes ?? this.managedFamilyModes,
    exactAllows: exactAllows ?? this.exactAllows,
  );

  String encode() {
    return jsonEncode({
      'syncDetails': syncDetails,
      'replaceActressImage': replaceActressImage,
      'fillMissingOnly': fillMissingOnly,
      'excludedPrefixes': excludedPrefixes,
      'retryWorkCodes': retryWorkCodes,
      'scrapeAliases': scrapeAliases,
      'managedFamilyModes': {
        for (final entry in managedFamilyModes.entries)
          entry.key: entry.value.storageValue,
      },
      'exactAllows': exactAllows.map((item) => item.toJson()).toList(),
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
      final retryCodes = json['retryWorkCodes'];
      final managedModes = <String, ManagedFamilyMode>{};
      if (json['managedFamilyModes'] is Map) {
        for (final entry in (json['managedFamilyModes'] as Map).entries) {
          final family = entry.key.toString().trim().toUpperCase();
          if (family.isNotEmpty) {
            managedModes[family] = ManagedFamilyModeCodec.parse(entry.value);
          }
        }
      }
      final exactAllows = <ScrapeExactAllowRule>[];
      if (json['exactAllows'] is List) {
        for (final item in json['exactAllows'] as List) {
          try {
            exactAllows.add(ScrapeExactAllowRule.fromJson(item));
          } on FormatException {
            // Ignore malformed optional entries while preserving old settings.
          }
        }
      }
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
        scrapeAliases: json['scrapeAliases'] is bool
            ? json['scrapeAliases'] as bool
            : false,
        managedFamilyModes: Map.unmodifiable(managedModes),
        exactAllows: List.unmodifiable(exactAllows),
      );
    } on FormatException {
      return const WorkScrapeOptions();
    }
  }
}
