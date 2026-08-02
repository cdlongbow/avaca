class PrefixExclusion {
  PrefixExclusion(Iterable<String> prefixes)
    : values = List.unmodifiable(_normalize(prefixes));

  final List<String> values;

  bool matches(String code) {
    final normalizedCode = code.trim().toUpperCase();
    return values.any(normalizedCode.startsWith);
  }

  static List<String> _normalize(Iterable<String> prefixes) {
    final result = <String>[];
    final seen = <String>{};
    for (final prefix in prefixes) {
      final normalized = prefix.trim().toUpperCase();
      if (normalized.isNotEmpty && seen.add(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }
}
