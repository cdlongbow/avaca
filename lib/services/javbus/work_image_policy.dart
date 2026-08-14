import '../scrape/work_identity.dart';

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

/// Explicitly registered DMM token families observed in the source samples
/// and the high-volume publisher families used by the app. This is a lookup
/// table, not a prefix-shaped fallback: a prefix outside this set is rejected
/// until its token format is verified and added deliberately.
const registeredLeadingOneDmmPrefixes = <String>{
  'mist',
  'sdab',
  'sdjs',
  'sdnm',
  'start',
};

const registeredH1711DmmPrefixes = <String>{'devr'};

/// Prefixes whose verified package images are hosted by Prestige/MGStage.
/// Keep this explicit: a missing studio field must not silently send an ABF
/// work to a guessed DMM token.
const registeredPrestigePrefixes = <String>{'abf'};

const registeredStandardDmmPrefixes = <String>{
  '300mium',
  '3dsvr',
  'abw',
  'abf',
  'aquco',
  'aqumam',
  'atkd',
  'dsvr',
  'dsuvr',
  'hez',
  'hsm',
  'ipx',
  'jdh',
  'jul',
  'juf',
  'jufe',
  'juq',
  'ktra',
  'mfcw',
  'meyd',
  'miaa',
  'mida',
  'mide',
  'midv',
  'mmraa',
  'oae',
  'ofje',
  'pred',
  'pxvrg',
  'rbd',
  'saba',
  'savr',
  'scute',
  'siro',
  'sivr',
  'snis',
  'sone',
  'stars',
  'ssis',
  'ssni',
  'svvrt',
  'vrkm',
  'vrprd',
};

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
      r'^/images/prestige/[a-z0-9]+/\d+/p(?:f|b)_e_[a-z0-9]+-\d+\.jpg$',
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

  WorkImageUrls urlsFor({required String code, String? studio}) {
    final parts = _parseCode(code);
    if (_isPrestige(studio) ||
        registeredPrestigePrefixes.contains(parts.prefix)) {
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

    final imageCode = _dmmImageCode(parts);
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

  String _dmmImageCode(({String prefix, String number}) parts) {
    final paddedNumber = parts.number.padLeft(5, '0');
    return switch (_tokenFamilyForPrefix(parts.prefix)) {
      WorkImageTokenFamily.standardDmm => parts.prefix + paddedNumber,
      WorkImageTokenFamily.leadingOneDmm => '1' + parts.prefix + paddedNumber,
      WorkImageTokenFamily.h1711Dmm => 'h_1711' + parts.prefix + paddedNumber,
      WorkImageTokenFamily.rebeccaH346Dmm =>
        'h_346' + parts.prefix + paddedNumber,
    };
  }

  WorkImageTokenFamily? tokenFamilyFor(String code) {
    try {
      final parts = _parseCode(code);
      return _tokenFamilyForPrefix(parts.prefix);
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

  bool _isPrestige(String? studio) {
    final normalized = studio?.trim().toLowerCase();
    return normalized == 'プレステージ' || normalized == 'prestige';
  }

  WorkImageTokenFamily _tokenFamilyForPrefix(String prefix) {
    if (prefix == 'rebd') {
      return WorkImageTokenFamily.rebeccaH346Dmm;
    }
    if (registeredLeadingOneDmmPrefixes.contains(prefix)) {
      return WorkImageTokenFamily.leadingOneDmm;
    }
    if (registeredH1711DmmPrefixes.contains(prefix)) {
      return WorkImageTokenFamily.h1711Dmm;
    }
    if (registeredStandardDmmPrefixes.contains(prefix)) {
      return WorkImageTokenFamily.standardDmm;
    }
    throw FormatException(
      'No approved image token family for prefix: ' + prefix,
    );
  }

  void _assertApproved(WorkImageUrls urls) {
    if (!isApprovedWorkImageUri(urls.card) ||
        !isApprovedWorkImageUri(urls.detail)) {
      throw StateError('Work image policy generated an unapproved endpoint.');
    }
  }
}
