import '../scrape/work_identity.dart';

enum WorkImagePlatform { dmm, mgstage }

enum WorkImageNormalizationFamily {
  dmmStandard,
  dmmLeadingOne,
  dmmH1711,
  dmmRebeccaH346,
  mgstagePrestige,
}

enum WorkImageRouteFailureReason {
  metadataMissing,
  metadataUnmapped,
  metadataAmbiguous,
  metadataConflict,
  evidenceMismatch,
  evidenceConflict,
}

final class WorkImageRouteResolution {
  const WorkImageRouteResolution.resolved({
    required this.platform,
    required this.family,
  }) : failureReason = null;

  const WorkImageRouteResolution.unclassified(this.failureReason)
    : platform = null,
      family = null;

  final WorkImagePlatform? platform;
  final WorkImageNormalizationFamily? family;
  final WorkImageRouteFailureReason? failureReason;

  bool get isResolved => platform != null && family != null;
}

final class WorkImageRouteException implements Exception {
  const WorkImageRouteException(this.code, this.reason);

  final String code;
  final WorkImageRouteFailureReason reason;

  @override
  String toString() =>
      'Work image route is unclassified for $code: ${reason.name}';
}

/// Resolves the image platform from verified producer/label identity.
///
/// A work-code prefix is deliberately absent from this decision. It is only
/// used later by WorkImagePolicy to format the token after a route is known.
final class WorkImageRouteResolver {
  const WorkImageRouteResolver();

  WorkImageRouteResolution resolve({
    required String code,
    String? studio,
    String? publisher,
    List<Uri> evidenceUris = const [],
  }) {
    final makerCandidates = _candidatesFor(studio, publisher: false);
    final publisherCandidates = _candidatesFor(publisher, publisher: true);
    final evidence = _evidenceCandidates(code, evidenceUris);

    if (evidence.failureReason != null) {
      return WorkImageRouteResolution.unclassified(evidence.failureReason!);
    }

    final evidenceCandidates = evidence.candidates;
    Set<_RouteCandidate> candidates;
    if (makerCandidates.isNotEmpty && publisherCandidates.isNotEmpty) {
      candidates = makerCandidates.intersection(publisherCandidates);
      if (candidates.isEmpty) {
        return const WorkImageRouteResolution.unclassified(
          WorkImageRouteFailureReason.metadataConflict,
        );
      }
    } else if (makerCandidates.isNotEmpty) {
      candidates = makerCandidates;
    } else if (publisherCandidates.isNotEmpty) {
      candidates = publisherCandidates;
    } else if (evidenceCandidates.isNotEmpty) {
      candidates = evidenceCandidates;
    } else if (_hasIdentity(studio) || _hasIdentity(publisher)) {
      return const WorkImageRouteResolution.unclassified(
        WorkImageRouteFailureReason.metadataUnmapped,
      );
    } else {
      return const WorkImageRouteResolution.unclassified(
        WorkImageRouteFailureReason.metadataMissing,
      );
    }

    if (candidates.length != 1) {
      return const WorkImageRouteResolution.unclassified(
        WorkImageRouteFailureReason.metadataAmbiguous,
      );
    }

    final selected = candidates.single;
    if (evidenceCandidates.isNotEmpty &&
        (evidenceCandidates.length != 1 ||
            !evidenceCandidates.contains(selected))) {
      return const WorkImageRouteResolution.unclassified(
        WorkImageRouteFailureReason.evidenceConflict,
      );
    }
    return WorkImageRouteResolution.resolved(
      platform: selected.platform,
      family: selected.family,
    );
  }

  Set<_RouteCandidate> _candidatesFor(
    String? value, {
    required bool publisher,
  }) {
    final normalized = _normalize(value);
    if (normalized.isEmpty) {
      return <_RouteCandidate>{};
    }

    if (_s1Aliases.contains(normalized) ||
        _standardDmmAliases.contains(normalized)) {
      return {_RouteCandidate.dmmStandard};
    }
    if (_leadingOneAliases.contains(normalized)) {
      return {_RouteCandidate.dmmLeadingOne};
    }
    if (_prestigeAliases.contains(normalized)) {
      return {_RouteCandidate.mgstagePrestige};
    }
    if (_rebeccaAliases.contains(normalized)) {
      return {_RouteCandidate.dmmRebeccaH346};
    }
    if (_h1711Aliases.contains(normalized)) {
      return {_RouteCandidate.dmmH1711};
    }

    // JavBus is a commonly observed publisher but is intentionally not a
    // route rule: it spans DMM and MGStage families.
    if (publisher && normalized == 'javbus') {
      return <_RouteCandidate>{};
    }
    return <_RouteCandidate>{};
  }

  _EvidenceResult _evidenceCandidates(String code, List<Uri> uris) {
    final candidates = <_RouteCandidate>{};
    for (final uri in uris) {
      final host = uri.host.toLowerCase();
      final path = uri.path.toLowerCase();
      if (!_isApprovedEvidenceHost(host, path)) {
        continue;
      }
      if (!_evidenceMatchesCode(uri, code)) {
        return const _EvidenceResult(
          failureReason: WorkImageRouteFailureReason.evidenceMismatch,
        );
      }
      if (host == 'image.mgstage.com') {
        candidates.add(_RouteCandidate.mgstagePrestige);
      } else if (path.contains('/h_346rebd')) {
        candidates.add(_RouteCandidate.dmmRebeccaH346);
      } else if (path.contains('/h_1711')) {
        candidates.add(_RouteCandidate.dmmH1711);
      } else {
        final token = RegExp(
          r'/digital/video/([^/]+)/',
        ).firstMatch(path)?.group(1);
        final identity = parseScrapeWorkCodeIdentity(code);
        final expected = identity == null || !identity.isStructured
            ? null
            : identity.displayCode.split('-').first.toLowerCase() +
                  identity.displayCode.split('-').last.padLeft(5, '0');
        candidates.add(
          token != null && expected != null && token == '1$expected'
              ? _RouteCandidate.dmmLeadingOne
              : _RouteCandidate.dmmStandard,
        );
      }
    }
    return _EvidenceResult(candidates: candidates);
  }

  bool _isApprovedEvidenceHost(String host, String path) {
    if (host == 'awsimgsrc.dmm.co.jp' || host == 'pics.dmm.co.jp') {
      return path.contains('/digital/video/') && path.endsWith('.jpg');
    }
    return host == 'image.mgstage.com' &&
        path.contains('/images/') &&
        path.endsWith('.jpg');
  }

  bool _evidenceMatchesCode(Uri uri, String code) {
    final identity = parseScrapeWorkCodeIdentity(code);
    if (identity == null || !identity.isStructured) {
      return false;
    }
    final compactUri = uri.toString().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '',
    );
    final compactPrefix = identity.displayCode.split('-').first.toLowerCase();
    final digits = identity.displayCode.split('-').last;
    final isMgStage = uri.host.toLowerCase() == 'image.mgstage.com';
    return compactUri.contains(compactPrefix) &&
        compactUri.contains(isMgStage ? digits : digits.padLeft(5, '0'));
  }

  bool _hasIdentity(String? value) => _normalize(value).isNotEmpty;

  String _normalize(String? value) {
    return (value ?? '').trim().toLowerCase().replaceAll(
      RegExp(r'[\s\-_.／/（）(),，、&]+'),
      '',
    );
  }
}

final class _EvidenceResult {
  const _EvidenceResult({
    this.candidates = const <_RouteCandidate>{},
    this.failureReason,
  });

  final Set<_RouteCandidate> candidates;
  final WorkImageRouteFailureReason? failureReason;
}

final class _RouteCandidate {
  const _RouteCandidate(this.platform, this.family);

  static const dmmStandard = _RouteCandidate(
    WorkImagePlatform.dmm,
    WorkImageNormalizationFamily.dmmStandard,
  );
  static const dmmH1711 = _RouteCandidate(
    WorkImagePlatform.dmm,
    WorkImageNormalizationFamily.dmmH1711,
  );
  static const dmmLeadingOne = _RouteCandidate(
    WorkImagePlatform.dmm,
    WorkImageNormalizationFamily.dmmLeadingOne,
  );
  static const dmmRebeccaH346 = _RouteCandidate(
    WorkImagePlatform.dmm,
    WorkImageNormalizationFamily.dmmRebeccaH346,
  );
  static const mgstagePrestige = _RouteCandidate(
    WorkImagePlatform.mgstage,
    WorkImageNormalizationFamily.mgstagePrestige,
  );

  final WorkImagePlatform platform;
  final WorkImageNormalizationFamily family;

  @override
  bool operator ==(Object other) =>
      other is _RouteCandidate &&
      other.platform == platform &&
      other.family == family;

  @override
  int get hashCode => Object.hash(platform, family);
}

const _s1Aliases = <String>{'s1', 's1no1style', 'エスワン', 'エスワンナンバーワンスタイル'};

const _leadingOneAliases = <String>{
  'sod',
  'sodcreate',
  'sodstar',
  'sodクリエイト',
};

const _prestigeAliases = <String>{'prestige', 'プレステージ'};

const _rebeccaAliases = <String>{'rebecca', 'レベッカ', 'rebeccapremium'};

const _h1711Aliases = <String>{'document', 'ドキュメント', 'documentary'};

const _standardDmmAliases = <String>{
  'ideaポケット',
  'ideapocket',
  'アイデアポケット',
  'aircontrol',
  'エアコントロール',
  'crystal',
  'クリスタル映像',
  'crystalnext',
  'eキス',
  'ekiss',
  'million',
  'ミリオン',
  'ケイエムプロデュース',
  'bazooka',
  'バズーカ',
  'royal',
  'ロイヤル',
  'hhhグループ',
  'アタッカーズ',
  '大人のドラマ',
  'realworks',
  'レアルワークス',
  'real',
  'sodクリエイト',
};
