import '../scrape/work_identity.dart';
import 'work_image_route_resolver.dart';

enum WorkImageSource { dmm, mgstage }

enum WorkImageVariant { card, detail }

enum WorkImageTokenFamily {
  standardDmm,
  leadingOneDmm,
  h1711Dmm,
  rebeccaH346Dmm,
}

const approvedWorkImageEndpointExamples = <String>[
  'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
      'sone00833/sone00833ps.jpg',
  'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
      'sone00833/sone00833pl.jpg',
  'https://image.mgstage.com/images/prestige/abf/183/'
      'pf_e_abf-183.jpg',
  'https://image.mgstage.com/images/prestige/abf/183/'
      'pb_e_abf-183.jpg',
  'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
      'h_346rebd00975/h_346rebd00975pl.jpg',
  'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
      'h_346rebd00975/h_346rebd00975ps.jpg',
];

class WorkImageUrls {
  const WorkImageUrls({
    required this.card,
    required this.detail,
    required this.source,
  });

  final Uri card;
  final Uri detail;
  final WorkImageSource source;

  Uri forVariant(WorkImageVariant variant) {
    return variant == WorkImageVariant.card ? card : detail;
  }
}

/// The only image URL families that the scrape pipeline may request.
///
/// Each family has exactly two approved variants:
/// DMM ps/pl, Prestige pf/pb, and Rebecca h_346 ps/pl. The matcher is kept
/// next to the formatter so a future caller cannot silently reintroduce a
/// seventh CDN path.
bool isApprovedWorkImageUri(Uri uri) {
  if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return false;
  }
  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  if (host == 'awsimgsrc.dmm.co.jp') {
    return RegExp(
          r'^/pics_dig/digital/video/(?:[a-z0-9]+|h_1711[a-z0-9]+)\d{5}/'
          r'(?:[a-z0-9]+|h_1711[a-z0-9]+)\d{5}(?:ps|pl)\.jpg$',
        ).hasMatch(path) ||
        RegExp(
          r'^/pics_dig/digital/video/h_346rebd\d{5}/'
          r'h_346rebd\d{5}(?:ps|pl)\.jpg$',
        ).hasMatch(path);
  }
  if (host == 'image.mgstage.com') {
    return RegExp(
      r'^/images/[a-z0-9]+/[a-z0-9]+/\d+/p(?:f|b)_e_[a-z0-9]+-\d+\.jpg$',
    ).hasMatch(path);
  }
  return false;
}

class WorkImagePolicy {
  const WorkImagePolicy();

  /// Returns the local filename used for a work image.
  ///
  /// Keep this aligned with the approved DMM token so a work such as START
  /// 489 is stored as start00489ps.jpg (card) or start00489pl.jpg (detail).
  String fileNameFor({
    required String code,
    required WorkImageVariant variant,
  }) {
    final imageCode = _localImageCode(code);
    final suffix = variant == WorkImageVariant.card ? 'ps' : 'pl';
    return imageCode + suffix + '.jpg';
  }

  WorkImageUrls urlsFor({
    required String code,
    String? studio,
    String? publisher,
    // Retained for compatibility with older callers. Route selection is
    // intentionally metadata-only and never inspects source image URLs.
    List<Uri> evidenceUris = const [],
    WorkImageRouteResolution? route,
  }) {
    final resolved =
        route ??
        const WorkImageRouteResolver().resolve(
          studio: studio,
          publisher: publisher,
        );
    if (!resolved.isResolved) {
      throw WorkImageRouteException(code, resolved.failureReason!);
    }
    return urlsForFamily(code: code, family: resolved.family!);
  }

  /// Builds URLs for one of the explicitly supported image families.
  ///
  /// Route selection belongs to PrefixRouteRepository/WorkImageDownloader;
  /// this method is intentionally only a formatter plus the existing host
  /// and path safety assertion.
  WorkImageUrls urlsForFamily({
    required String code,
    required WorkImageNormalizationFamily family,
  }) {
    final parts = _parseCode(code);
    if (family == WorkImageNormalizationFamily.mgstagePrestige) {
      final normalizedCode = parts.prefix + '-' + parts.number;
      final base =
          'https://image.mgstage.com/images/prestige/' +
          parts.prefix +
          '/' +
          parts.number;
      final urls = WorkImageUrls(
        card: Uri.parse(base + '/pf_e_' + normalizedCode + '.jpg'),
        detail: Uri.parse(base + '/pb_e_' + normalizedCode + '.jpg'),
        source: WorkImageSource.mgstage,
      );
      _assertApproved(urls);
      return urls;
    }
    if (family == WorkImageNormalizationFamily.mgstageSeikyouiku) {
      final tokenPrefix = '502' + parts.prefix;
      final token = tokenPrefix + '-' + parts.number;
      final base =
          'https://image.mgstage.com/images/seikyouiku/' +
          tokenPrefix +
          '/' +
          parts.number;
      final urls = WorkImageUrls(
        card: Uri.parse(base + '/pf_e_' + token + '.jpg'),
        detail: Uri.parse(base + '/pb_e_' + token + '.jpg'),
        source: WorkImageSource.mgstage,
      );
      _assertApproved(urls);
      return urls;
    }

    final imageCode = _dmmImageCode(parts, family);
    final base =
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/' +
        imageCode +
        '/' +
        imageCode;
    final urls = WorkImageUrls(
      card: Uri.parse(base + 'ps.jpg'),
      detail: Uri.parse(base + 'pl.jpg'),
      source: WorkImageSource.dmm,
    );
    _assertApproved(urls);
    return urls;
  }

  String _dmmImageCode(
    ({String prefix, String number}) parts,
    WorkImageNormalizationFamily family,
  ) {
    final paddedNumber = parts.number.padLeft(5, '0');
    return switch (family) {
      WorkImageNormalizationFamily.dmmStandard => parts.prefix + paddedNumber,
      WorkImageNormalizationFamily.dmmLeadingOne =>
        '1' + parts.prefix + paddedNumber,
      WorkImageNormalizationFamily.dmmH1711 =>
        'h_1711' + parts.prefix + paddedNumber,
      WorkImageNormalizationFamily.dmmRebeccaH346 =>
        parts.prefix == 'rebd'
            ? 'h_346' + parts.prefix + paddedNumber
            : throw FormatException(
                'Rebecca H346 is not applicable to ${parts.prefix}.',
              ),
      WorkImageNormalizationFamily.mgstagePrestige ||
      WorkImageNormalizationFamily.mgstageSeikyouiku => throw StateError(
        'MGStage route must not format a DMM URL.',
      ),
    };
  }

  WorkImageTokenFamily? tokenFamilyFor(
    String code, {
    String? studio,
    String? publisher,
    // Retained for compatibility with older callers. Route selection is
    // intentionally metadata-only and never inspects source image URLs.
    List<Uri> evidenceUris = const [],
  }) {
    try {
      final route = const WorkImageRouteResolver().resolve(
        studio: studio,
        publisher: publisher,
      );
      if (!route.isResolved) {
        return null;
      }
      return switch (route.family!) {
        WorkImageNormalizationFamily.dmmStandard =>
          WorkImageTokenFamily.standardDmm,
        WorkImageNormalizationFamily.dmmLeadingOne =>
          WorkImageTokenFamily.leadingOneDmm,
        WorkImageNormalizationFamily.dmmH1711 => WorkImageTokenFamily.h1711Dmm,
        WorkImageNormalizationFamily.dmmRebeccaH346 =>
          WorkImageTokenFamily.rebeccaH346Dmm,
        WorkImageNormalizationFamily.mgstagePrestige ||
        WorkImageNormalizationFamily.mgstageSeikyouiku => null,
      };
    } on FormatException {
      return null;
    }
  }

  String _localImageCode(String code) {
    try {
      final parts = _parseCode(code);
      // Local filenames intentionally use the visible work code family. The
      // network token (1start..., h_1711..., h_346...) is only for its
      // approved endpoint and must not become a second work identity.
      return parts.prefix + parts.number.padLeft(5, '0');
    } on FormatException {
      final normalized = normalizeScrapeWorkCodeSurface(code)
          ?.toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      return normalized == null || normalized.isEmpty ? 'work' : normalized;
    }
  }

  ({String prefix, String number}) _parseCode(String code) {
    final identity = parseScrapeWorkCodeIdentity(code);
    if (identity == null || !identity.isStructured) {
      throw FormatException('Unsupported work code: ' + code);
    }
    final match = RegExp(
      r'^([A-Z0-9][A-Z0-9]*)-(\d+)$',
      caseSensitive: false,
    ).firstMatch(identity.displayCode);
    if (match == null) {
      throw FormatException('Unsupported work code: ' + code);
    }
    return (prefix: match.group(1)!.toLowerCase(), number: match.group(2)!);
  }

  void _assertApproved(WorkImageUrls urls) {
    if (!isApprovedWorkImageUri(urls.card) ||
        !isApprovedWorkImageUri(urls.detail)) {
      throw StateError('Work image policy generated an unapproved endpoint.');
    }
  }
}
