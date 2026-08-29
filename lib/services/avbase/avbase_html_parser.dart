import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../models/work.dart';
import '../../models/scrape_source_id.dart';
import '../scrape/scrape_models.dart';
import '../scrape/provenance_semantics.dart';
import 'avbase_models.dart';

final class AvBaseHtmlParser {
  AvBaseWorkDetails parseWorkPage(String source, {required Uri pageUri}) {
    final document = html.parse(source);
    final fields = _detailFields(document);
    final rawCode = _codeFromUri(pageUri);
    final title = _clean(document.querySelector('h1')?.text) ?? '';
    final strippedTitle = _stripCode(title, rawCode);
    final performers = _performers(document, pageUri);
    final releaseDate = _normalizeDate(_field(fields, const ['発売日', '発売日']));
    final durationMinutes = _digitsAsInt(
      _field(fields, const ['収録分数', '収録時間']),
    );
    final studio = _field(fields, const ['メーカー', '製作メーカー']);
    final publisher = _field(fields, const ['レーベル', '発売元']);
    final series = _field(fields, const ['シリーズ']);
    final provenanceFacts = _provenanceFacts(
      document,
      fields,
      strippedTitle,
      pageUri,
    );

    return AvBaseWorkDetails(
      code: rawCode,
      title: strippedTitle,
      releaseDate: releaseDate,
      durationMinutes: durationMinutes,
      studio: studio,
      publisher: publisher,
      series: series,
      performerCount: performers?.length,
      performers: performers,
      provenanceFacts: provenanceFacts,
      catalogEvidence: [
        ScrapeCatalogWorkEvidence.fromDetails(
          source: ScrapeSourceId.avbase,
          code: rawCode,
          title: strippedTitle,
          manufacturer: studio,
          label: publisher,
          series: series,
          provenanceFacts: provenanceFacts,
        ),
      ],
      originalImageEvidenceUris: _originalImageEvidenceUris(
        document,
        pageUri,
        rawCode,
      ),
    );
  }

  ScrapeWorkProvenanceFacts _provenanceFacts(
    Document document,
    Map<String, String> fields,
    String title,
    Uri pageUri,
  ) {
    final tags = _sectionTags(document);
    final description =
        _sectionDescription(document) ??
        _clean(
          document
                  .querySelector('meta[name="description"]')
                  ?.attributes['content'] ??
              _field(fields, const ['説明', '概要', '内容']),
        );
    final includedWorks = <String>{
      ..._sectionWorkCodes(document, pageUri, const ['収録作品']),
      ..._fieldValues(fields, const ['収録作品', '収録タイトル', '収録内容', '収録作品名']),
    }.toList(growable: false);
    final parentWorks = <String>{
      ..._sectionWorkCodes(document, pageUri, const [
        '元作品',
        '親作品',
        '収録元',
        '原作品',
      ]),
      ..._fieldValues(fields, const ['元作品', '親作品', '収録元', '原作品']),
    }.toList(growable: false);
    final genres = _fieldValues(fields, const ['ジャンル', '類別', '類型']);
    final text = [
      title,
      description ?? '',
      ...fields.values,
      ...genres,
      ...tags,
    ].join(' ');
    final hasPriorMarker =
        includedWorks.isNotEmpty ||
        parentWorks.isNotEmpty ||
        ScrapeProvenanceSemantics.containsExplicitPriorWorkStatement(text);
    final isSplit = ScrapeProvenanceSemantics.containsStrongSplitEvidence(text);
    final isExtract = RegExp(
      r'抜粋|切り出し|extract',
      caseSensitive: false,
    ).hasMatch(text);
    final isPackage = RegExp(
      r'オムニバス|アンソロジー|作品集|bundle|package',
      caseSensitive: false,
    ).hasMatch(text);
    final isOldWithBonus =
        ScrapeProvenanceSemantics.containsOldMaterialWithNewBonus(text);
    final provenShared =
        ScrapeProvenanceSemantics.containsProvenSharedProduction(text);
    final sharedHint = ScrapeProvenanceSemantics.containsSharedProductionHint(
      text,
    );
    final independent = ScrapeProvenanceSemantics.containsIndependentSegments(
      text,
    );
    return ScrapeWorkProvenanceFacts(
      includedWorks: includedWorks,
      parentWorks: parentWorks,
      genres: genres,
      tags: tags,
      description: description,
      containsPriorWorks: hasPriorMarker ? true : null,
      extractedFromPriorWork: isExtract ? true : null,
      splitFromPriorWork: isSplit ? true : null,
      packageOfIndependentWorks: isPackage ? true : null,
      packageOfPriorWorks: isPackage && hasPriorMarker ? true : null,
      reusedIndependentSegments: independent && hasPriorMarker ? true : null,
      oldMaterialWithNewBonus: isOldWithBonus ? true : null,
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
          : provenShared
          ? ScrapeCoPerformance.sharedProduction
          : sharedHint
          ? ScrapeCoPerformance.possibleSharedProduction
          : ScrapeCoPerformance.unknown,
    );
  }

  List<String> _fieldValues(Map<String, String> fields, List<String> labels) {
    final values = <String>[];
    for (final label in labels) {
      final value = _clean(fields[label]);
      if (value != null && !values.contains(value)) values.add(value);
    }
    return List.unmodifiable(values);
  }

  List<String> _sectionTags(Document document) {
    final section = _sectionForHeading(document, const ['タグ・説明文']);
    if (section == null) return const [];
    final values = <String>[];
    final seen = <String>{};
    for (final anchor in section.querySelectorAll('a[href*="/tags/"]')) {
      final value = _clean(anchor.text);
      if (value != null && seen.add(value)) values.add(value);
    }
    return List.unmodifiable(values);
  }

  String? _sectionDescription(Document document) {
    final section = _sectionForHeading(document, const ['紹介文']);
    final fallback = _sectionForHeading(document, const ['タグ・説明文']);
    return _descriptionFromSection(section) ??
        _descriptionFromSection(fallback);
  }

  String? _descriptionFromSection(Element? section) {
    if (section == null) return null;
    for (final element in section.querySelectorAll(
      'p, article, [data-description], .prose, [class*="prose"]',
    )) {
      final value = _clean(element.text);
      if (value == null || value.length < 8) continue;
      final links = element.querySelectorAll('a');
      if (links.isNotEmpty &&
          element.querySelectorAll('a[href*="/tags/"]').length ==
              links.length) {
        continue;
      }
      return value;
    }
    for (final element in section.children.skip(1)) {
      if (element.querySelectorAll('a').isNotEmpty) continue;
      final value = _clean(element.text);
      if (value != null && value.length >= 8) return value;
    }
    return null;
  }

  List<String> _sectionWorkCodes(
    Document document,
    Uri pageUri,
    List<String> headings,
  ) {
    final section = _sectionForHeading(document, headings);
    if (section == null) return const [];
    final values = <String>[];
    final seen = <String>{};
    for (final anchor in section.querySelectorAll('a[href*="/works/"]')) {
      final href = _clean(anchor.attributes['href']);
      if (href == null) continue;
      final code = _codeFromUri(pageUri.resolve(href));
      if (code.isNotEmpty && seen.add(code)) values.add(code);
    }
    return List.unmodifiable(values);
  }

  Element? _sectionForHeading(Document document, List<String> headings) {
    for (final heading in document.querySelectorAll('h2, h3')) {
      final headingText = _clean(heading.text) ?? '';
      if (!headings.any(headingText.contains)) continue;
      Element? current = heading;
      while (current != null) {
        if (current.localName == 'section') return current;
        final parent = current.parent;
        current = parent is Element ? parent : null;
      }
      final parent = heading.parent;
      if (parent is Element &&
          parent.querySelectorAll('h2, h3').length == 1 &&
          _isControlledHeadingContainer(parent)) {
        return parent;
      }
      final ancestor = parent is Element ? parent.parent : null;
      if (ancestor is Element &&
          ancestor.querySelectorAll('h2, h3').length == 1 &&
          (ancestor.localName == 'article' ||
              ancestor.localName == 'div' &&
                  (ancestor.attributes.containsKey('data-slot') ||
                      ancestor.classes.any(
                        (value) => value.toLowerCase().contains('card'),
                      )))) {
        return ancestor;
      }
    }
    return null;
  }

  bool _isControlledHeadingContainer(Element element) {
    if (element.localName != 'div' && element.localName != 'article') {
      return false;
    }
    if (element.children.length > 12) return false;
    return element.querySelector('nav, footer, header, main, aside') == null;
  }

  Uri? findWorkUriByCode(
    String source, {
    required Uri pageUri,
    required String code,
  }) {
    final expected = code.trim().toUpperCase();
    if (expected.isEmpty) return null;
    final document = html.parse(source);
    for (final anchor in document.querySelectorAll('a[href*="/works/"]')) {
      final href = _clean(anchor.attributes['href']);
      if (href == null) continue;
      final uri = pageUri.resolve(href);
      if (_codeFromUri(uri) == expected) return uri;
    }
    return null;
  }

  Map<String, String> _detailFields(Document document) {
    final fields = <String, String>{};
    for (final term in document.querySelectorAll('dt')) {
      final parent = term.parent;
      if (parent is! Element) {
        continue;
      }
      final index = parent.children.indexOf(term);
      if (index < 0 || index + 1 >= parent.children.length) {
        continue;
      }
      final label = _normalizeLabel(term.text);
      final value = _clean(parent.children[index + 1].text);
      if (label != null && value != null) {
        fields[label] = value;
      }
    }
    return fields;
  }

  List<WorkPerformer>? _performers(Document document, Uri pageUri) {
    Element? section;
    for (final heading in document.querySelectorAll('h2')) {
      final text = _clean(heading.text) ?? '';
      if (!text.contains('出演者')) {
        continue;
      }
      Element? current = heading;
      while (current != null) {
        if (current.localName == 'section') {
          section = current;
          break;
        }
        final parent = current.parent;
        current = parent is Element ? parent : null;
      }
      if (section != null) {
        break;
      }
    }
    if (section == null) {
      return null;
    }
    final result = <WorkPerformer>[];
    final seen = <String>{};
    for (final anchor in section.querySelectorAll('a[href*="/talents/"]')) {
      final name = _clean(anchor.text);
      final href = _clean(anchor.attributes['href']);
      if (name == null || href == null || !seen.add(name.toLowerCase())) {
        continue;
      }
      result.add(WorkPerformer(name: name, sourceUri: pageUri.resolve(href)));
    }
    return result.isEmpty ? null : List.unmodifiable(result);
  }

  List<Uri> _originalImageEvidenceUris(
    Document document,
    Uri pageUri,
    String code,
  ) {
    final result = <Uri>[];
    final seen = <String>{};
    for (final element in document.querySelectorAll('img, a')) {
      for (final attribute in const [
        'src',
        'data-src',
        'data-original',
        'href',
      ]) {
        final raw = _clean(element.attributes[attribute]);
        if (raw == null) {
          continue;
        }
        final uri = pageUri.resolve(raw);
        if (!_isImageEvidenceUri(uri) || !_evidenceMatchesCode(uri, code)) {
          continue;
        }
        if (seen.add(uri.toString())) {
          result.add(uri);
        }
      }
    }
    return List.unmodifiable(result);
  }

  bool _isImageEvidenceUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        path.endsWith('.jpg') &&
        (((host == 'awsimgsrc.dmm.co.jp' || host == 'pics.dmm.co.jp') &&
                path.contains('/digital/video/')) ||
            (host == 'image.mgstage.com' && path.contains('/images/')));
  }

  bool _evidenceMatchesCode(Uri uri, String code) {
    final match = RegExp(r'^([A-Za-z0-9]+)-(\d+)$').firstMatch(code);
    if (match == null) {
      return false;
    }
    final prefix = match.group(1)!.toLowerCase();
    final digits = match.group(2)!;
    final compact = uri.toString().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '',
    );
    return compact.contains(prefix) &&
        (compact.contains(digits) || compact.contains(digits.padLeft(5, '0')));
  }

  String? _field(Map<String, String> fields, List<String> labels) {
    for (final label in labels) {
      final value = _clean(fields[label]);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  int? _digitsAsInt(String? value) => int.tryParse(_digits(value) ?? '');

  String? _digits(String? value) {
    return RegExp(r'\d+').firstMatch(value ?? '')?.group(0);
  }

  String? _normalizeDate(String? value) {
    final cleaned = _clean(value);
    if (cleaned == null) {
      return null;
    }
    final match = RegExp(
      r'^(\d{4})[./年-](\d{1,2})[./月-](\d{1,2})',
    ).firstMatch(cleaned);
    if (match == null) {
      return cleaned;
    }
    return '${match.group(1)}-${match.group(2)!.padLeft(2, '0')}-${match.group(3)!.padLeft(2, '0')}';
  }

  String _codeFromUri(Uri uri) {
    if (uri.pathSegments.isEmpty) {
      return '';
    }
    final segment = Uri.decodeComponent(uri.pathSegments.last).trim();
    final separator = segment.lastIndexOf(':');
    return (separator < 0 ? segment : segment.substring(separator + 1))
        .trim()
        .toUpperCase();
  }

  String _stripCode(String title, String code) {
    if (code.isEmpty) {
      return title;
    }
    return title
        .replaceFirst(
          RegExp('^${RegExp.escape(code)}\\s*', caseSensitive: false),
          '',
        )
        .trim();
  }

  String? _normalizeLabel(String value) {
    final cleaned = _clean(value);
    return cleaned?.replaceAll(RegExp(r'[：:]'), '').trim();
  }

  String? _clean(String? value) {
    final cleaned = value?.replaceAll('\u00a0', ' ').trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}
