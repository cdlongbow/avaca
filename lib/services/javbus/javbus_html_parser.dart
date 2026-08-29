import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../models/scrape_source_id.dart';
import '../../models/work.dart';
import '../scrape/scrape_models.dart';
import '../scrape/provenance_semantics.dart';
import '../scrape/work_identity.dart';
import 'javbus_models.dart';

class JavBusHtmlParser {
  JavBusWorkDetails parseWorkPage(String source, {required Uri pageUri}) {
    final document = html.parse(source);
    final fields = <String, String>{};
    for (final paragraph in document.querySelectorAll('.info p')) {
      final header = paragraph.querySelector('.header');
      if (header == null) {
        continue;
      }
      final key = header.text.replaceAll(RegExp(r'[:：\s]'), '');
      final value = paragraph.text.replaceFirst(header.text, '').trim();
      fields[key] = value;
    }

    final durationText = _field(fields, const ['長度', '长度', '収録時間']);
    final duration = RegExp(r'\d+').firstMatch(durationText ?? '')?.group(0);
    final rawCode =
        _field(fields, const ['識別碼', '识别码', '品番']) ?? _codeFromUri(pageUri);
    final code =
        normalizeScrapeWorkCodeSurface(rawCode) ?? rawCode.trim().toUpperCase();
    final rawTitle = _clean(document.querySelector('h3')?.text) ?? '';
    final strippedTitle = rawTitle
        .replaceFirst(
          RegExp('^${RegExp.escape(rawCode)}\\s*', caseSensitive: false),
          '',
        )
        .trim();

    final performers = _performers(document, pageUri);
    final genres = _genreValues(document);
    final parsedTitle = strippedTitle.isEmpty ? rawTitle : strippedTitle;
    final provenanceFacts = _provenanceFacts(
      document,
      fields,
      parsedTitle,
      genres,
    );
    return JavBusWorkDetails(
      code: code,
      rawCode: rawCode,
      title: parsedTitle,
      releaseDate: _field(fields, const ['發行日期', '发行日期', '発売日']),
      durationMinutes: int.tryParse(duration ?? ''),
      studio: _field(fields, const ['製作商', '制作商', 'メーカー']),
      publisher: _field(fields, const ['發行商', '发行商', 'レーベル']),
      series: _field(fields, const ['系列', 'シリーズ']),
      performers: performers,
      provenanceFacts: provenanceFacts,
      catalogEvidence: [
        ScrapeCatalogWorkEvidence.fromDetails(
          source: ScrapeSourceId.javbus,
          code: code,
          title: parsedTitle,
          manufacturer: _field(fields, const ['製作商', '制作商', 'メーカー']),
          label: _field(fields, const ['發行商', '发行商', 'レーベル']),
          series: _field(fields, const ['系列', 'シリーズ']),
          description: provenanceFacts.description,
          provenanceFacts: provenanceFacts,
        ),
      ],
      originalImageEvidenceUris: _originalImageEvidenceUris(
        document,
        pageUri,
        code,
      ),
    );
  }

  ScrapeWorkProvenanceFacts _provenanceFacts(
    Document document,
    Map<String, String> fields,
    String title,
    List<String> genres,
  ) {
    final description = _clean(
      document
              .querySelector('meta[name="description"]')
              ?.attributes['content'] ??
          _field(fields, const ['説明', '概要', '內容']),
    );
    final includedWorks = _fieldValues(fields, const [
      '収録作品',
      '収録タイトル',
      '収録内容',
      '収録作品名',
    ]);
    final parentWorks = _fieldValues(fields, const [
      '元作品',
      '親作品',
      '収録元',
      '原作品',
    ]);
    final text = [
      title,
      description ?? '',
      ...fields.values,
      ...genres,
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
      tags: genres,
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

  List<String> _genreValues(Document document) {
    final values = <String>[];
    final seen = <String>{};
    for (final anchor in document.querySelectorAll(
      '.info p a[href*="/genre/"]',
    )) {
      final value = _clean(anchor.text);
      if (value != null && seen.add(value)) values.add(value);
    }
    return List.unmodifiable(values);
  }

  List<WorkPerformer>? _performers(Document document, Uri pageUri) {
    final info = document.querySelector('.info');
    if (info == null) {
      return null;
    }
    final children = info.children;
    final headerIndex = children.indexWhere((element) {
      final header = element.querySelector('.header');
      final key = header?.text.replaceAll(RegExp(r'[:：\s]'), '') ?? '';
      return const {'演員', '演员', '出演者'}.contains(key);
    });
    if (headerIndex < 0) {
      return null;
    }

    final result = <WorkPerformer>[];
    final seenNames = <String>{};
    for (var index = headerIndex; index < children.length; index++) {
      final element = children[index];
      final nextHeader = element.querySelector('.header');
      if (index != headerIndex && nextHeader != null) {
        break;
      }
      for (final anchor in element.querySelectorAll('a[href*="/star/"]')) {
        final name = _clean(anchor.text);
        final href = _clean(anchor.attributes['href']);
        if (name == null || href == null) {
          continue;
        }
        final key = name.toLowerCase();
        if (seenNames.add(key)) {
          result.add(
            WorkPerformer(name: name, sourceUri: pageUri.resolve(href)),
          );
        }
      }
    }
    return List.unmodifiable(result);
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
    final imagePath = uri.path.toLowerCase();
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        imagePath.endsWith('.jpg') &&
        (((host == 'awsimgsrc.dmm.co.jp' || host == 'pics.dmm.co.jp') &&
                imagePath.contains('/digital/video/')) ||
            (host == 'image.mgstage.com' && imagePath.contains('/images/')));
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
    final isMgStage = uri.host.toLowerCase() == 'image.mgstage.com';
    return compact.contains(prefix) &&
        compact.contains(isMgStage ? digits : digits.padLeft(5, '0'));
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

  String _codeFromUri(Uri uri) {
    return uri.pathSegments.lastOrNull?.toUpperCase() ?? '';
  }

  String? _clean(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}
