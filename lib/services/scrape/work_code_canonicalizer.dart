String? canonicalizeWorkCode(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }

  var normalized = value
      .replaceAll('\u00a0', ' ')
      .replaceAll('\u2010', '-')
      .replaceAll('\u2011', '-')
      .replaceAll('\u2012', '-')
      .replaceAll('\u2013', '-')
      .replaceAll('\u2014', '-')
      .replaceAll('\u2212', '-');

  final buffer = StringBuffer();
  for (final rune in normalized.runes) {
    buffer.writeCharCode(_fullWidthToAscii(rune));
  }
  normalized = buffer.toString().toUpperCase();
  normalized = normalized.replaceAll(RegExp(r'\s+'), '');
  normalized = normalized.replaceAll(RegExp(r'-+'), '-');
  normalized = normalized.replaceAll(RegExp(r'^-+|-+$'), '');
  if (normalized.isEmpty) {
    return null;
  }

  // Scrapers can expose the same JAV code with a numeric alias prefix and
  // without a separator (for example, 1START00023), while the canonical
  // source format is PREFIX-NUMBER.  Match only those complete single-code
  // shapes so complex prefixes such as FC2 or FC2-PPV_123 remain untouched.
  final match =
      RegExp(r'^\d+([A-Z]+)-?(\d+)$').firstMatch(normalized) ??
      RegExp(r'^([A-Z]+)-(\d+)$').firstMatch(normalized);
  if (match != null) {
    final prefix = match.group(1)!;
    final significantDigits = match.group(2)!.replaceFirst(RegExp(r'^0+'), '');
    final number = (significantDigits.isEmpty ? '0' : significantDigits)
        .padLeft(3, '0');
    return '$prefix-$number';
  }

  return normalized;
}

int _fullWidthToAscii(int rune) {
  if (rune == 0x3000) {
    return 0x20;
  }
  if (rune >= 0xff01 && rune <= 0xff5e) {
    return rune - 0xfee0;
  }
  return rune;
}
