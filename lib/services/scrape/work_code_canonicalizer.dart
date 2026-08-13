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

  // DMM-style START codes are sometimes exposed with a leading `1` and
  // zero-padded digits (for example, 1START00408).  That is an alias for
  // START-408, not a different work.  Keep this deliberately narrow: do not
  // split comma-separated codes or apply the rule to unrelated prefixes.
  final startMatch = RegExp(r'^1?START-?0*(\d+)$').firstMatch(normalized);
  if (startMatch != null) {
    final number = startMatch.group(1)!.replaceFirst(RegExp(r'^0+'), '');
    return 'START-${number.isEmpty ? '0' : number}';
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
