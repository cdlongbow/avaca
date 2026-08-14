import '../scrape/work_identity.dart';

class PrefixExclusion {
  PrefixExclusion(Iterable<String> prefixes)
    : values = List.unmodifiable(_normalize(prefixes));

  final List<String> values;

  bool matches(String code) {
    final normalizedCode = normalizeScrapeWorkCodeSurface(code) ?? '';
    return values.any(normalizedCode.startsWith);
  }

  static List<String> _normalize(Iterable<String> prefixes) {
    final result = <String>[];
    final seen = <String>{};
    for (final prefix in prefixes) {
      final original = prefix.trim();
      var normalized = normalizeScrapeWorkCodeSurface(original) ?? '';
      if (normalized.isNotEmpty &&
          RegExp(r'[-‐‑‒–—−]$').hasMatch(original) &&
          !normalized.endsWith('-')) {
        normalized = '$normalized-';
      }
      if (normalized.isNotEmpty &&
          RegExp(r'^[-‐‑‒–—−]').hasMatch(original) &&
          !normalized.startsWith('-')) {
        normalized = '-$normalized';
      }
      if (normalized.isNotEmpty && seen.add(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }
}
