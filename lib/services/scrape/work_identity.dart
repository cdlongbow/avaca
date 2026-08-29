// Identity rules shared by filename parsing and exact work lookup.
//
// This file intentionally does not depend on work_code_canonicalizer.dart.
// The legacy canonicalizer contains alias reconciliation that is still needed
// by a few presentation/image consumers, but it must not decide whether two
// a filename or source response is the same work.

import 'scrape_models.dart';

/// The conservative work identity used by the folder-import lookup path.
///
/// This is intentionally separate from work_code_canonicalizer.dart. A
/// source image token can look code-like (for example ssis00875 or
/// h_346rebd00975), but it is not a work code and must never enter this
/// parser.
final class ScrapeWorkCodeIdentity {
  const ScrapeWorkCodeIdentity({
    required this.surface,
    required this.key,
    required this.displayCode,
    required this.isStructured,
    this.isSpecialEdition = false,
  });

  final String surface;
  final String key;
  final String displayCode;
  final bool isStructured;
  final bool isSpecialEdition;
}

/// Optional source-declared context for edition and cross-platform identity
/// resolution. It is intentionally not a generic prefix/number grammar.
final class ScrapeWorkIdentityEvidence {
  const ScrapeWorkIdentityEvidence({
    this.canonicalCode,
    this.makerCode,
    this.manufacturer,
    this.label,
    this.series,
    this.aliases = const [],
    this.platformIds = const {},
  });

  final String? canonicalCode;
  final String? makerCode;
  final String? manufacturer;
  final String? label;
  final String? series;
  final List<String> aliases;
  final Map<String, String> platformIds;

  Iterable<String> get declaredCodes sync* {
    for (final value in <String?>[canonicalCode, makerCode]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) yield trimmed;
    }
    yield* aliases
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    yield* platformIds.values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
  }
}

/// Normalizes only code surface differences for new cross-source matching.
///
/// In particular, this deliberately preserves numeric prefixes, number
/// padding, and separator presence. It must not turn a legacy alias such as
/// `1STZY00017` into `STZY-017`.
String? normalizeScrapeWorkCodeSurface(String? raw) {
  final value = _normalizeCodeSurface(raw).replaceAll(RegExp(r'\s+'), '');
  if (value.isEmpty) {
    return null;
  }
  return value.toUpperCase();
}

/// Parses only the safe work-code forms supported by the current lookup
/// contract. Numeric padding is preserved for identity comparison. The only
/// source-specific padding rule is the observed START separatorless
/// representation (START00023 == START-023). It is deliberately not a
/// global zero-trimming rule, so SIVR00303 remains different from SIVR-303.
ScrapeWorkCodeIdentity? parseScrapeWorkCodeIdentity(
  String? raw, {
  ScrapeWorkIdentityEvidence? evidence,
}) {
  final surface = normalizeScrapeWorkCodeSurface(raw);
  if (surface == null) {
    return null;
  }

  // V/T/VT/VT2/EC and BD are edition markers only inside the explicitly
  // supported SOD product-line grammar. A code such as FOO-123-EC remains a
  // distinct surface; no global suffix or prefix rule changes its identity.
  final edition = _scopedSodEdition(surface, evidence);
  final baseSurface = edition?.baseSurface ?? surface;
  final parsed = _parseScrapeWorkCodeIdentitySurface(baseSurface);
  if (parsed.isStructured) {
    final scoped = _scopedSodIdentity(
      parsed,
      evidence,
      isSpecialEdition: edition != null,
    );
    return ScrapeWorkCodeIdentity(
      surface: surface,
      key: scoped?.key ?? parsed.key,
      displayCode: scoped?.displayCode ?? parsed.displayCode,
      isStructured: true,
      isSpecialEdition: edition != null,
    );
  }
  return parsed;
}

ScrapeWorkCodeIdentity? _scopedSodIdentity(
  ScrapeWorkCodeIdentity identity,
  ScrapeWorkIdentityEvidence? evidence, {
  required bool isSpecialEdition,
}) {
  if (!_hasSodContext(evidence)) return null;
  final match = RegExp(
    r'^(START|STARS)-(\d+)$',
  ).firstMatch(identity.displayCode);
  if (match == null) return null;
  final prefix = match.group(1)!;
  final digits = match.group(2)!.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return ScrapeWorkCodeIdentity(
    surface: identity.surface,
    key: '${prefix.toLowerCase()}$digits',
    displayCode: '$prefix-${_formatSodDigits(digits)}',
    isStructured: true,
    isSpecialEdition: isSpecialEdition,
  );
}

String _formatSodDigits(String digits) {
  final normalized = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return normalized.padLeft(3, '0');
}

({String baseSurface, bool isSpecial})? _scopedSodEdition(
  String surface,
  ScrapeWorkIdentityEvidence? evidence,
) {
  if (!_hasSodContext(evidence)) return null;
  final terminalEdition = RegExp(
    r'^(.+?)-?(VT2|VT|V|T)(?:-?EC)?$',
  ).firstMatch(surface);
  if (terminalEdition != null && _isScopedSodBase(terminalEdition.group(1)!)) {
    return (baseSurface: terminalEdition.group(1)!, isSpecial: true);
  }
  final ecEdition = RegExp(r'^(.+?)-EC$').firstMatch(surface);
  if (ecEdition != null && _isScopedSodBase(ecEdition.group(1)!)) {
    return (baseSurface: ecEdition.group(1)!, isSpecial: true);
  }

  // STARSBD-859 is accepted only when the same source also identifies the
  // product line as SOD. Without that evidence it remains STARSBD-859.
  final bdVariant = RegExp(r'^(STARS)BD-(\d+)$').firstMatch(surface);
  if (bdVariant != null && _hasSodContext(evidence)) {
    return (
      baseSurface: '${bdVariant.group(1)}-${bdVariant.group(2)}',
      isSpecial: true,
    );
  }
  return null;
}

bool _isScopedSodBase(String surface) {
  return RegExp(r'^(START|STARS)-\d+$').hasMatch(surface);
}

bool _hasSodContext(ScrapeWorkIdentityEvidence? evidence) {
  if (evidence == null) return false;
  final text = [
    evidence.manufacturer,
    evidence.label,
    evidence.series,
  ].whereType<String>().join(' ').toLowerCase();
  return RegExp(r'\bsod\b|sodクリエイト|sod create').hasMatch(text);
}

ScrapeWorkCodeIdentity _parseScrapeWorkCodeIdentitySurface(String surface) {
  final separated = RegExp(r'^([A-Z0-9][A-Z0-9]*)-(\d+)$').firstMatch(surface);
  if (separated != null) {
    final prefix = separated.group(1)!;
    final digits = separated.group(2)!;
    return ScrapeWorkCodeIdentity(
      surface: surface,
      key: '${prefix.toLowerCase()}$digits',
      displayCode: '$prefix-$digits',
      isStructured: true,
    );
  }

  // A separatorless form is only accepted when the prefix is alphabetic and
  // the numeric part is long enough to be a real product number. This keeps
  // short opaque values such as AB12 and compound values such as
  // FC2-PPV_123-999 out of the structured grammar.
  final separatorless = RegExp(r'^([A-Z]{2,})(\d+)$').firstMatch(surface);
  if (separatorless != null && separatorless.group(2)!.length >= 3) {
    final prefix = separatorless.group(1)!;
    final digits = separatorless.group(2)!;
    if (prefix == 'START' && digits.length == 5 && digits.startsWith('00')) {
      final startDigits = digits.substring(2);
      return ScrapeWorkCodeIdentity(
        surface: surface,
        key: 'start$startDigits',
        displayCode: 'START-$startDigits',
        isStructured: true,
      );
    }
    return ScrapeWorkCodeIdentity(
      surface: surface,
      key: '${prefix.toLowerCase()}$digits',
      displayCode: '$prefix-$digits',
      isStructured: true,
    );
  }

  return ScrapeWorkCodeIdentity(
    surface: surface,
    key: 'opaque:${surface.toLowerCase()}',
    displayCode: surface,
    isStructured: false,
  );
}

bool scrapeWorkCodesEqual(
  String? left,
  String? right, {
  ScrapeWorkIdentityEvidence? evidence,
}) {
  final leftKey = parseScrapeWorkCodeIdentity(left, evidence: evidence)?.key;
  final rightKey = parseScrapeWorkCodeIdentity(right, evidence: evidence)?.key;
  return leftKey != null && leftKey == rightKey;
}

String? scrapeWorkResolvedIdentityKey({
  required String? rawCode,
  ScrapeExternalWorkIdentity? externalIdentity,
  ScrapeWorkIdentityEvidence? identityEvidence,
  required String fallback,
}) {
  final evidence = identityEvidence ?? _identityEvidence(externalIdentity);
  final bridgeKey = _declaredScopedBridgeKey(
    externalIdentity,
    evidence: evidence,
  );
  if (bridgeKey != null) return 'code:$bridgeKey';
  final identity = parseScrapeWorkCodeIdentity(rawCode, evidence: evidence);
  if (identity != null) return 'code:${identity.key}';
  final canonical =
      externalIdentity?.canonicalCode ?? externalIdentity?.makerCode;
  final canonicalIdentity = parseScrapeWorkCodeIdentity(
    canonical,
    evidence: evidence,
  );
  if (canonicalIdentity != null) return 'code:${canonicalIdentity.key}';
  return fallback;
}

ScrapeWorkIdentityEvidence? _identityEvidence(
  ScrapeExternalWorkIdentity? identity,
) {
  if (identity == null || identity.isEmpty) return null;
  return ScrapeWorkIdentityEvidence(
    canonicalCode: identity.canonicalCode,
    makerCode: identity.makerCode,
    manufacturer: identity.manufacturer,
    label: identity.label,
    series: identity.series,
    aliases: identity.aliases,
    platformIds: identity.platformIds,
  );
}

String? _declaredScopedBridgeKey(
  ScrapeExternalWorkIdentity? identity, {
  ScrapeWorkIdentityEvidence? evidence,
}) {
  if (identity == null) return null;
  final declared = identity.declaredCodes.toList(growable: false);
  final startNumbers = <String>{};
  final starsNumbers = <String>{};
  for (final raw in declared) {
    final normalized = normalizeScrapeWorkCodeSurface(raw);
    if (normalized == null) continue;
    final compact = normalized.replaceAll('-', '');
    final start = RegExp(r'^(?:107|1)?START0*(\d+)$').firstMatch(compact);
    if (start != null) startNumbers.add(start.group(1)!);
    final stars = RegExp(r'^STARS(?:BD)?0*(\d+)$').firstMatch(compact);
    if (stars != null) starsNumbers.add(stars.group(1)!);
  }
  if (startNumbers.length == 1 && starsNumbers.isEmpty) {
    return 'start${startNumbers.single}';
  }
  if (starsNumbers.length == 1 &&
      startNumbers.isEmpty &&
      _hasSodContext(evidence)) {
    return 'stars${starsNumbers.single}';
  }
  return null;
}

String _normalizeCodeSurface(String? raw) {
  if (raw == null) {
    return '';
  }
  final folded = raw.runes.map((rune) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      return String.fromCharCode(rune - 0xFEE0);
    }
    if (rune == 0x3000) {
      return ' ';
    }
    return String.fromCharCode(rune);
  }).join();
  return folded
      .replaceAll(RegExp(r'[‐‑‒–—−﹘﹣－]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
