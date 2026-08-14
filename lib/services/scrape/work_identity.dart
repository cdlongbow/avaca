// Identity rules used only by the new works scrape pipeline.
//
// This file intentionally does not depend on work_code_canonicalizer.dart.
// The legacy canonicalizer contains alias reconciliation that is still needed
// by a few presentation/image consumers, but it must not decide whether two
// newly scraped works are the same work.

final class ScrapeTitleIdentity {
  const ScrapeTitleIdentity({
    required this.key,
    required this.isUsable,
    required this.isSpecialEdition,
  });

  final String key;
  final bool isUsable;
  final bool isSpecialEdition;
}

const _specialEditionMarkers = <String>['【特典版】', '[特典版]'];

ScrapeTitleIdentity scrapeTitleIdentity(String? title) {
  var value = _normalizeTitleSurface(title);
  var isSpecialEdition = false;

  for (final marker in _specialEditionMarkers) {
    if (value.startsWith(marker)) {
      value = value.substring(marker.length).trim();
      isSpecialEdition = true;
      break;
    }
    if (value.endsWith(marker)) {
      value = value.substring(0, value.length - marker.length).trim();
      isSpecialEdition = true;
      break;
    }
  }

  return ScrapeTitleIdentity(
    key: value.toLowerCase(),
    isUsable: value.isNotEmpty,
    isSpecialEdition: isSpecialEdition,
  );
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

/// Returns true only for the publisher spelling supported by the current
/// parser fixtures/first-party samples. Do not infer this from a work code.
bool isRebeccaPublisher(String? publisher) {
  final normalized = _normalizePublisherSurface(publisher).toLowerCase();
  return normalized == 'rebecca';
}

String _normalizeTitleSurface(String? raw) {
  if (raw == null) {
    return '';
  }
  return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _normalizePublisherSurface(String? raw) {
  if (raw == null) {
    return '';
  }
  return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
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
