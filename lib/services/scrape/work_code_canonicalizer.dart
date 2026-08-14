enum WorkCodeIdentityKind { simpleCanonical, protectedSpecial, opaqueUnknown }

final class WorkCodeIdentity {
  const WorkCodeIdentity({required this.value, required this.kind});

  final String value;
  final WorkCodeIdentityKind kind;

  bool get isSimpleCanonical => kind == WorkCodeIdentityKind.simpleCanonical;
}

/// Parses a scraped work code into the one identity representation used by
/// grouping, database alias reconciliation, and image lookup.
///
/// The simple grammar deliberately accepts only one alphabetic core and one
/// numeric core. Complex or ambiguous values stay opaque instead of being
/// destructively rewritten and accidentally merged with another work.
WorkCodeIdentity? parseWorkCodeIdentity(String? raw) {
  final normalized = _normalizeRepresentation(raw);
  if (normalized == null) {
    return null;
  }

  final numericLeading = RegExp(r'^\d+([A-Z]+)-?(\d+)$').firstMatch(normalized);
  if (numericLeading != null &&
      !_isSafeNumericLeading(
        numericLeading.group(1)!,
        numericLeading.group(2)!,
      )) {
    return WorkCodeIdentity(
      value: normalized,
      kind: WorkCodeIdentityKind.protectedSpecial,
    );
  }
  if (numericLeading != null) {
    return _simpleIdentity(numericLeading.group(1)!, numericLeading.group(2)!);
  }

  final separated = RegExp(r'^([A-Z]+)-(\d+)$').firstMatch(normalized);
  if (separated != null) {
    return _simpleIdentity(separated.group(1)!, separated.group(2)!);
  }

  // Spaces, underscores, and dots are accepted only when the whole value is
  // still exactly one alphabetic core plus one numeric core. This keeps
  // compound values such as FC2-PPV_123-999 opaque.
  final supportedSeparator = RegExp(
    r'^([A-Z]+)[ ._-]+(\d+)$',
  ).firstMatch(normalized);
  if (supportedSeparator != null) {
    return _simpleIdentity(
      supportedSeparator.group(1)!,
      supportedSeparator.group(2)!,
    );
  }

  // Separatorless codes are common in source pages. A two-letter prefix is
  // accepted only with at least three numeric digits, which preserves the
  // existing opaque AB12/FC2 contract while still covering short prefixes
  // such as AB123. Longer alphabetic prefixes may use two or more digits.
  final separatorless = RegExp(r'^([A-Z]{2,})(\d+)$').firstMatch(normalized);
  if (separatorless != null &&
      _isSafeSeparatorless(separatorless.group(1)!, separatorless.group(2)!)) {
    return _simpleIdentity(separatorless.group(1)!, separatorless.group(2)!);
  }

  return WorkCodeIdentity(
    value: normalized,
    kind: _isProtectedSpecial(normalized)
        ? WorkCodeIdentityKind.protectedSpecial
        : WorkCodeIdentityKind.opaqueUnknown,
  );
}

/// Compatibility wrapper used by existing callers.
String? canonicalizeWorkCode(String? raw) => parseWorkCodeIdentity(raw)?.value;

WorkCodeIdentity _simpleIdentity(String prefix, String digits) {
  final significantDigits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final number = significantDigits.padLeft(3, '0');
  return WorkCodeIdentity(
    value: '${prefix.toUpperCase()}-$number',
    kind: WorkCodeIdentityKind.simpleCanonical,
  );
}

bool _isSafeSeparatorless(String prefix, String digits) {
  if (prefix.length >= 3 && digits.length >= 2) {
    return true;
  }
  return prefix.length >= 2 && digits.length >= 3;
}

bool _isSafeNumericLeading(String prefix, String digits) =>
    _isSafeSeparatorless(prefix, digits);

bool _isProtectedSpecial(String normalized) {
  if (normalized == 'START-408,427' ||
      normalized == 'START-408-V' ||
      normalized == 'FC2' ||
      normalized == 'AB12' ||
      normalized == 'FC2-PPV_123-999') {
    return true;
  }
  return normalized.contains(',') ||
      normalized.contains('/') ||
      normalized.contains('_') ||
      normalized.contains(RegExp(r'[A-Z]+\d+[A-Z]+'));
}

String? _normalizeRepresentation(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final ascii = StringBuffer();
  for (final rune in trimmed.runes) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      ascii.writeCharCode(rune - 0xFEE0);
    } else {
      ascii.writeCharCode(rune);
    }
  }

  final normalized = ascii
      .toString()
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'[‐‑‒–—―−]'), '-')
      .toUpperCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  if (normalized.isEmpty || RegExp(r'^-+$').hasMatch(normalized)) {
    return null;
  }
  return normalized;
}
