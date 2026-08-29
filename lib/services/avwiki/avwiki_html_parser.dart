import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../models/scrape_source_id.dart';
import '../../models/work.dart';
import '../scrape/provenance_semantics.dart';
import '../scrape/scrape_models.dart';
import '../scrape/work_identity.dart';
import 'avwiki_models.dart';

final class _AvWikiWorkSearchHit {
  const _AvWikiWorkSearchHit({
    required this.code,
    required this.detailUri,
    this.externalIdentity,
  });

  final String? code;
  final Uri detailUri;
  final ScrapeExternalWorkIdentity? externalIdentity;
}

final class AvWikiHtmlParser {
  AvWikiWorkDetails parseWorkPage(String source, {required Uri pageUri}) {
    final document = html.parse(source);
    final article =
        document.querySelector('main article') ??
        document.querySelector('article') ??
        document.body ??
        Element.tag('article');
    final fields = _detailFields(article);
    final heading = article.querySelector('h1');
    final subtitle = _clean(heading?.querySelector('.entry-subtitle')?.text);
    final headingText = _clean(heading?.text) ?? '';
    final makerCode = _firstField(fields, const [
      'メーカー品番',
      'メーカー番号',
      '作品番号',
      '品番',
    ]);
    final code =
        _clean(makerCode) ??
        _extractCode(subtitle) ??
        _extractCode(headingText) ??
        _codeFromPath(pageUri) ??
        '';
    final title = _titleWithoutCode(headingText, subtitle, code);
    final manufacturer = _firstField(fields, const ['メーカー', '製作メーカー']);
    final label = _firstField(fields, const ['レーベル', '発売元']);
    final series = _firstField(fields, const ['シリーズ']);
    final platformIds = <String, String>{
      ..._platformFields(fields),
      ..._platformIdsFromLinks(article),
    };
    final performers = _performers(_firstField(fields, const ['AV女優名', '出演者']));
    final description = _description(article);
    final tags = _tags(article);
    final genres = <String>{
      ..._fieldValues(fields, const ['ジャンル', '類別', '類型']),
      ...tags,
    }.toList(growable: false);
    final facts = _provenanceFacts(
      article: article,
      fields: fields,
      title: title,
      description: description,
      tags: tags,
      pageUri: pageUri,
      genres: genres,
    );
    final externalIdentity = ScrapeExternalWorkIdentity(
      canonicalCode: code,
      makerCode: code,
      manufacturer: manufacturer,
      label: label,
      series: series,
      platformIds: platformIds,
    );
    final catalogEvidence = ScrapeCatalogWorkEvidence.fromDetails(
      source: ScrapeSourceId.avwiki,
      code: code,
      title: title,
      manufacturer: manufacturer,
      label: label,
      series: series,
      description: description,
      provenanceFacts: facts,
    );
    return AvWikiWorkDetails(
      code: code,
      rawCode: makerCode ?? code,
      title: title,
      releaseDate: _firstField(fields, const ['配信開始日', '発売日', 'リリース日']),
      studio: manufacturer,
      publisher: label,
      series: series,
      performerCount: performers?.length,
      performers: performers,
      description: description,
      genres: genres,
      provenanceFacts: facts,
      externalIdentity: externalIdentity.isEmpty ? null : externalIdentity,
      catalogEvidence: [catalogEvidence],
    );
  }

  Uri? findWorkUriByCode(
    String source, {
    required Uri pageUri,
    required String code,
  }) {
    final expected = normalizeScrapeWorkCodeSurface(code);
    if (expected == null) return null;
    final document = html.parse(source);
    for (final article in document.querySelectorAll('article.archive-list')) {
      final summary = _parseArchiveSummary(article, pageUri);
      if (summary == null) continue;
      final candidate = normalizeScrapeWorkCodeSurface(summary.code);
      if (candidate == expected) return summary.detailUri;
      final expectedKey = scrapeWorkResolvedIdentityKey(
        rawCode: code,
        externalIdentity: summary.externalIdentity,
        fallback: 'expected:$expected',
      );
      final candidateKey = scrapeWorkResolvedIdentityKey(
        rawCode: summary.code,
        externalIdentity: summary.externalIdentity,
        fallback: 'candidate:${summary.detailUri}',
      );
      if (expectedKey == candidateKey) return summary.detailUri;
    }
    return null;
  }

  _AvWikiWorkSearchHit? _parseArchiveSummary(Element article, Uri pageUri) {
    final metadata = article.querySelectorAll('.post-meta li');
    String? code;
    String? manufacturer;
    String? label;
    String? series;
    for (final item in metadata) {
      final value = _clean(item.text);
      if (value == null) continue;
      final itemCode = _extractCode(value);
      if (itemCode != null && code == null) {
        code = itemCode;
      }
      final linkText = _clean(item.querySelector('a')?.text);
      if (linkText != null &&
          !item.classes.contains('actress-name') &&
          manufacturer == null) {
        final pieces = linkText.split(RegExp(r'\s*[-／/]\s*'));
        manufacturer = pieces.first.trim();
        label = pieces.length > 1 ? pieces.last.trim() : null;
      }
    }
    series = _firstArchiveLinkText(article, const ['/series/']);
    final detailHref = _clean(
      article.querySelector('.read-more a[href]')?.attributes['href'],
    );
    if (detailHref == null) return null;
    final detailUri = pageUri.resolve(detailHref);
    if (!_isSameHttpsHost(detailUri, pageUri)) return null;
    final platformIds = _platformIdsFromLinks(article);
    final identity = ScrapeExternalWorkIdentity(
      canonicalCode: code,
      makerCode: code,
      manufacturer: manufacturer,
      label: label,
      series: series,
      platformIds: platformIds,
    );
    return _AvWikiWorkSearchHit(
      code: code,
      detailUri: detailUri,
      externalIdentity: identity.isEmpty ? null : identity,
    );
  }

  String? _firstArchiveLinkText(Element article, List<String> hrefParts) {
    for (final anchor in article.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      if (!hrefParts.any(href.contains)) continue;
      final value = _clean(anchor.text);
      if (value != null) return value;
    }
    return null;
  }

  Map<String, String> _detailFields(Element article) {
    final fields = <String, String>{};
    for (final table in article.querySelectorAll('dl.dltable')) {
      final children = table.children;
      for (var index = 0; index + 1 < children.length; index++) {
        final label = children[index];
        final value = children[index + 1];
        if (label.localName != 'dt' || value.localName != 'dd') continue;
        final key = _fieldKey(label.text);
        final cleaned = _clean(value.text);
        if (key != null && cleaned != null) fields[key] = cleaned;
      }
    }
    return fields;
  }

  Map<String, String> _platformFields(Map<String, String> fields) {
    final result = <String, String>{};
    for (final entry in fields.entries) {
      final key = entry.key.toLowerCase();
      final platform = key.contains('fanza') || key.contains('dmm')
          ? 'fanza'
          : key.contains('mgs') || key.contains('mgstage')
          ? 'mgs'
          : key.contains('sokmil')
          ? 'sokmil'
          : key.contains('duga')
          ? 'duga'
          : null;
      if (platform != null && entry.value.trim().isNotEmpty) {
        result[platform] = entry.value.trim();
      }
    }
    return result;
  }

  Map<String, String> _platformIdsFromLinks(Element root) {
    final ids = <String, String>{};
    for (final anchor in root.querySelectorAll('a[href]')) {
      final text = (_clean(anchor.text) ?? '').toLowerCase();
      final href = _clean(anchor.attributes['href']);
      if (href == null) continue;
      final uri = Uri.tryParse(href);
      final raw = uri == null ? href : uri.toString();
      final decoded = Uri.decodeFull(uri?.queryParameters['lurl'] ?? raw);
      final id = RegExp(
        r'(?:[?&]id=|/cid=)([A-Za-z0-9_-]+)',
        caseSensitive: false,
      ).firstMatch(decoded)?.group(1);
      if (id == null || id.trim().isEmpty) continue;
      final platform = text.contains('sokmil') || raw.contains('sokmil')
          ? 'sokmil'
          : text.contains('duga') || raw.contains('duga')
          ? 'duga'
          : text.contains('mgs') || raw.contains('mgstage')
          ? 'mgs'
          : 'fanza';
      ids[platform] = id;
    }
    return ids;
  }

  List<WorkPerformer>? _performers(String? raw) {
    final value = _clean(raw);
    if (value == null) return null;
    final names = value
        .split(RegExp(r'[,、，/／|]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .map((item) => WorkPerformer(name: item))
        .toList(growable: false);
    return names.isEmpty ? null : names;
  }

  ScrapeWorkProvenanceFacts _provenanceFacts({
    required Element article,
    required Map<String, String> fields,
    required String title,
    required String? description,
    required List<String> tags,
    required Uri pageUri,
    required List<String> genres,
  }) {
    final included = <String>{};
    final parent = <String>{};
    final text = [
      title,
      description ?? '',
      ...fields.values,
      ...genres,
      ...tags,
    ].join(' ');
    final hasCollectionContext =
        ScrapeProvenanceSemantics.explicitCompilationLabel(text) != null ||
        ScrapeProvenanceSemantics.strongReuseProposition([text]) != null ||
        ScrapeProvenanceSemantics.containsExplicitPriorWorkStatement(text);
    for (final anchor in article.querySelectorAll('a[href]')) {
      final href = _clean(anchor.attributes['href']);
      if (href == null) continue;
      final uri = pageUri.resolve(href);
      final pathCode = uri.pathSegments
          .where((segment) => segment.trim().isNotEmpty)
          .lastOrNull;
      final code = _extractCode(pathCode) ?? _extractCode(anchor.text);
      if (code == null) continue;
      final surrounding = '${anchor.text} ${anchor.parent?.text ?? ''}';
      if (RegExp(r'元作品|親作品|収録元|原作品').hasMatch(surrounding)) {
        parent.add(code);
      } else if (hasCollectionContext &&
          uri.host.toLowerCase() == pageUri.host.toLowerCase()) {
        included.add(code);
      }
    }
    final independent = ScrapeProvenanceSemantics.containsIndependentSegments(
      text,
    );
    final shared = ScrapeProvenanceSemantics.containsProvenSharedProduction(
      text,
    );
    final sharedHint = ScrapeProvenanceSemantics.containsSharedProductionHint(
      text,
    );
    return ScrapeWorkProvenanceFacts(
      includedWorks: included.toList(growable: false),
      parentWorks: parent.toList(growable: false),
      genres: genres,
      tags: tags,
      description: description,
      containsPriorWorks:
          included.isNotEmpty ||
              parent.isNotEmpty ||
              ScrapeProvenanceSemantics.containsExplicitPriorWorkStatement(text)
          ? true
          : null,
      extractedFromPriorWork:
          RegExp(r'抜粋|切り出し|extract', caseSensitive: false).hasMatch(text)
          ? true
          : null,
      splitFromPriorWork:
          ScrapeProvenanceSemantics.containsStrongSplitEvidence(text)
          ? true
          : null,
      packageOfIndependentWorks:
          RegExp(
            r'オムニバス|アンソロジー|作品集|bundle|package',
            caseSensitive: false,
          ).hasMatch(text)
          ? true
          : null,
      packageOfPriorWorks:
          (included.isNotEmpty || parent.isNotEmpty) &&
              RegExp(
                r'オムニバス|アンソロジー|作品集|bundle|package',
                caseSensitive: false,
              ).hasMatch(text)
          ? true
          : null,
      reusedIndependentSegments:
          (included.isNotEmpty || parent.isNotEmpty) && independent
          ? true
          : null,
      oldMaterialWithNewBonus:
          ScrapeProvenanceSemantics.containsOldMaterialWithNewBonus(text)
          ? true
          : null,
      reissue:
          ScrapeProvenanceSemantics.containsStrongReissueEvidence(text) ||
              ScrapeProvenanceSemantics.containsPremiumRepackageEvidence(text)
          ? true
          : null,
      remaster: RegExp(r'リマスター|remaster', caseSensitive: false).hasMatch(text)
          ? true
          : null,
      reedited: ScrapeProvenanceSemantics.containsStrongReeditEvidence(text)
          ? true
          : null,
      explicitOriginalProduction:
          ScrapeProvenanceSemantics.containsReliableOriginal(text)
          ? true
          : null,
      coPerformance: independent
          ? ScrapeCoPerformance.independentSegments
          : shared
          ? ScrapeCoPerformance.sharedProduction
          : sharedHint
          ? ScrapeCoPerformance.possibleSharedProduction
          : ScrapeCoPerformance.unknown,
    );
  }

  String? _description(Element article) {
    for (final paragraph in article.querySelectorAll('p')) {
      if (_isMetadataParagraph(paragraph)) continue;
      final value = _clean(paragraph.text);
      if (value != null && value.length >= 8) return value;
    }
    return null;
  }

  bool _isMetadataParagraph(Element paragraph) {
    Element? current = paragraph.parent;
    while (current != null) {
      if (current.localName == 'dl' ||
          current.classes.contains('post-meta') ||
          current.classes.contains('link-wrapper')) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  List<String> _tags(Element article) {
    final values = <String>[];
    final seen = <String>{};
    for (final anchor in article.querySelectorAll('a[rel="tag"]')) {
      final value = _clean(anchor.text);
      if (value != null && seen.add(value)) values.add(value);
    }
    return List.unmodifiable(values);
  }

  String _titleWithoutCode(String heading, String? subtitle, String code) {
    if (subtitle != null && subtitle.isNotEmpty) {
      return subtitle;
    }
    var value = heading.trim();
    final codeIndex = value.lastIndexOf(code);
    if (codeIndex > 0) value = value.substring(0, codeIndex).trim();
    return value.isEmpty ? code : value;
  }

  String? _codeFromPath(Uri uri) =>
      uri.pathSegments.isEmpty ? null : _extractCode(uri.pathSegments.last);

  String? _extractCode(String? raw) {
    final value = _clean(raw);
    if (value == null) return null;
    final matches = RegExp(
      r'\b[A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)*\b',
    ).allMatches(value);
    for (final match in matches) {
      final candidate = match.group(0)!;
      if (!RegExp(r'\d').hasMatch(candidate)) continue;
      final identity = parseScrapeWorkCodeIdentity(candidate);
      if (identity?.isStructured == true) return candidate.toUpperCase();
    }
    return null;
  }

  String? _firstField(Map<String, String> fields, List<String> labels) {
    for (final label in labels) {
      final value = fields[_fieldKey(label)];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  List<String> _fieldValues(Map<String, String> fields, List<String> labels) {
    final values = <String>[];
    for (final label in labels) {
      final value = fields[_fieldKey(label)];
      if (value != null && value.trim().isNotEmpty) values.add(value.trim());
    }
    return List.unmodifiable(values);
  }

  String? _fieldKey(String? raw) {
    final value = _clean(raw);
    return value
        ?.replaceAll(RegExp(r'[：:]'), '')
        .replaceAll(RegExp(r'\s+'), '');
  }

  bool _isSameHttpsHost(Uri uri, Uri pageUri) {
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        uri.host.toLowerCase() == pageUri.host.toLowerCase() &&
        (uri.hasPort ? uri.port : 443) ==
            (pageUri.hasPort ? pageUri.port : 443);
  }

  String? _clean(String? raw) {
    final value = raw?.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value == null || value.isEmpty ? null : value;
  }
}
