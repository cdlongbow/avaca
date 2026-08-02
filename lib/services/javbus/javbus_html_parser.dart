import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../models/scraped_actress_details.dart';
import 'javbus_models.dart';

class JavBusHtmlParser {
  JavBusActressPage parseActressPage(String source, {required Uri pageUri}) {
    final document = html.parse(source);
    final info = document.querySelector('.avatar-box .photo-info');
    final avatar = document.querySelector(
      '.avatar-box .photo-frame img, .avatar-box img',
    );

    return JavBusActressPage(
      details: ScrapedActressDetails(
        name: _clean(info?.querySelector('span')?.text),
        avatarUrl: _resolveOptional(pageUri, avatar?.attributes['src']),
        birthDate: _profileValue(info, const ['生日', '生年月日']),
        height: _digits(_profileValue(info, const ['身高', '身長'])),
        cup: _profileValue(info, const ['罩杯', 'カップ']),
        bust: _digits(_profileValue(info, const ['胸圍', '胸围', 'バスト'])),
        waist: _digits(_profileValue(info, const ['腰圍', '腰围', 'ウエスト'])),
        hip: _digits(_profileValue(info, const ['臀圍', '臀围', 'ヒップ'])),
      ),
      works: document
          .querySelectorAll('a.movie-box')
          .map((element) => _parseWorkSummary(element, pageUri))
          .whereType<JavBusWorkSummary>()
          .toList(growable: false),
      pageCount: _pageCount(document),
    );
  }

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
    final code =
        _field(fields, const ['識別碼', '识别码', '品番']) ?? _codeFromUri(pageUri);
    final rawTitle = _clean(document.querySelector('h3')?.text) ?? '';
    final strippedTitle = rawTitle
        .replaceFirst(
          RegExp('^${RegExp.escape(code)}\\s*', caseSensitive: false),
          '',
        )
        .trim();

    return JavBusWorkDetails(
      code: code,
      title: strippedTitle.isEmpty ? rawTitle : strippedTitle,
      releaseDate: _field(fields, const ['發行日期', '发行日期', '発売日']),
      durationMinutes: int.tryParse(duration ?? ''),
      studio: _field(fields, const ['製作商', '制作商', 'メーカー']),
      publisher: _field(fields, const ['發行商', '发行商', 'レーベル']),
      series: _field(fields, const ['系列', 'シリーズ']),
    );
  }

  List<JavBusActressSearchResult> parseActressSearchResults(
    String source, {
    required Uri pageUri,
  }) {
    final document = html.parse(source);
    return document
        .querySelectorAll('a.avatar-box, a.star-box')
        .map((element) {
          final nameElement =
              element.querySelector('.photo-info .mleft') ??
              element.querySelector('.photo-info span');
          final directName = nameElement?.nodes
              .whereType<Text>()
              .map((node) => node.data)
              .join(' ');
          final name =
              _clean(directName) ??
              _clean(nameElement?.text) ??
              _clean(element.text) ??
              '';
          return JavBusActressSearchResult(
            name: name,
            uri: pageUri.resolve(element.attributes['href'] ?? ''),
          );
        })
        .where((result) => result.name.isNotEmpty)
        .toList(growable: false);
  }

  JavBusWorkSummary? _parseWorkSummary(Element element, Uri pageUri) {
    final dates = element.querySelectorAll('date');
    final code = _clean(dates.firstOrNull?.text);
    final href = _clean(element.attributes['href']);
    if (code == null || href == null) {
      return null;
    }
    return JavBusWorkSummary(
      code: code.toUpperCase(),
      title: _clean(element.querySelector('.photo-info span')?.text) ?? '',
      releaseDate: dates.length > 1 ? _clean(dates[1].text) : null,
      detailUri: pageUri.resolve(href),
    );
  }

  int _pageCount(Document document) {
    var maximum = 1;
    for (final anchor in document.querySelectorAll('.pagination a')) {
      final label = int.tryParse(anchor.text.trim());
      if (label != null && label > maximum) {
        maximum = label;
      }
      final href = anchor.attributes['href'];
      final lastSegment = href == null
          ? null
          : int.tryParse(Uri.parse(href).pathSegments.lastOrNull ?? '');
      if (lastSegment != null && lastSegment > maximum) {
        maximum = lastSegment;
      }
    }
    return maximum;
  }

  String? _profileValue(Element? info, List<String> labels) {
    final lines =
        info?.querySelectorAll('p').map((element) => element.text) ??
        const <String>[];
    for (final source in lines) {
      for (final label in labels) {
        final match = RegExp(
          '^\\s*${RegExp.escape(label)}\\s*[:：]\\s*(.+?)\\s*\$',
        ).firstMatch(source);
        final value = _clean(match?.group(1));
        if (value != null) {
          return value;
        }
      }
    }
    return null;
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

  String? _digits(String? value) {
    return RegExp(r'\d+').firstMatch(value ?? '')?.group(0);
  }

  String _codeFromUri(Uri uri) {
    return uri.pathSegments.lastOrNull?.toUpperCase() ?? '';
  }

  Uri? _resolveOptional(Uri pageUri, String? value) {
    final cleaned = _clean(value);
    return cleaned == null ? null : pageUri.resolve(cleaned);
  }

  String? _clean(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}
