import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:avaca_domain/avaca_domain.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

part 'src/default_avaca_scraper.dart';

/// Scraping is a Server concern.  The client only receives normalized catalog
/// records and cannot invoke source adapters directly.
abstract interface class AvacaScraper {
  Future<AvacaWorkSummary> resolveWork(String code);
}

/// Rich metadata is an optional Server-side capability.  Keeping it separate
/// from [AvacaScraper] preserves compatibility with small offline fixtures
/// while allowing the production importer to persist fields independently.
abstract interface class AvacaRichScraper {
  Future<AvacaWorkMetadata> resolveWorkDetails(String code);
}

final class AvacaPerformerMetadata {
  const AvacaPerformerMetadata({
    required this.performerId,
    required this.displayName,
    this.externalId,
  });

  final AvacaActressId performerId;
  final String displayName;
  final String? externalId;
}

/// A source artwork candidate is still remote metadata.  The Server may
/// download and cache it, but the candidate itself never crosses to AVACA as
/// a URL or an HTTP response body.
final class AvacaArtworkMetadata {
  const AvacaArtworkMetadata({
    required this.uri,
    this.mimeType,
    this.assetId,
    this.cachedPath,
    this.length,
  });

  final Uri uri;
  final String? mimeType;
  final String? assetId;
  final String? cachedPath;
  final int? length;
}

final class AvacaWorkMetadata {
  const AvacaWorkMetadata({
    required this.summary,
    this.description,
    this.releaseDate,
    this.performers = const <AvacaPerformerMetadata>[],
    this.artwork,
    this.source,
    this.sourceUri,
    this.durationMs,
    this.diagnostics = const <String>[],
  });

  final AvacaWorkSummary summary;
  final String? description;
  final String? releaseDate;
  final List<AvacaPerformerMetadata> performers;
  final AvacaArtworkMetadata? artwork;
  final String? source;
  final Uri? sourceUri;
  final int? durationMs;
  final List<String> diagnostics;

  AvacaWorkMetadata copyWith({AvacaArtworkMetadata? artwork}) =>
      AvacaWorkMetadata(
        summary: summary,
        description: description,
        releaseDate: releaseDate,
        performers: performers,
        artwork: artwork ?? this.artwork,
        source: source,
        sourceUri: sourceUri,
        durationMs: durationMs,
        diagnostics: diagnostics,
      );
}

/// Sources that can return rich metadata opt in to this interface.  Legacy
/// summary-only sources remain valid and are upgraded to [AvacaWorkMetadata]
/// with an empty optional-field set by [CompositeAvacaScraper].
abstract interface class AvacaDetailedScrapeSource {
  String get id;

  Future<AvacaWorkMetadata?> fetchWorkDetails(String code);
}

/// A concrete source adapter belongs to the Server composition.  The source
/// returns normalized domain data; it never exposes HTTP response bodies,
/// cookies, or source-specific persistence to the client.
abstract interface class AvacaScrapeSource {
  String get id;

  Future<AvacaWorkSummary?> fetchWork(String code);
}

class AvacaScraperException implements Exception {
  const AvacaScraperException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// Tries configured Server-owned sources in order.  A source failure is
/// isolated so one unavailable provider does not freeze a folder import; the
/// caller receives a stable error only when no source can resolve the code.
final class CompositeAvacaScraper implements AvacaScraper, AvacaRichScraper {
  CompositeAvacaScraper(Iterable<AvacaScrapeSource> sources)
    : sources = List<AvacaScrapeSource>.unmodifiable(sources);

  final List<AvacaScrapeSource> sources;

  @override
  Future<AvacaWorkSummary> resolveWork(String code) async {
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) {
      throw const AvacaScraperException(
        'invalid_work_code',
        'work code is empty',
      );
    }
    if (sources.isEmpty) {
      throw const AvacaScraperException(
        'scraper_not_configured',
        'no Server scraper source is configured',
      );
    }
    var hadFailure = false;
    for (final source in sources) {
      try {
        final result = await source.fetchWork(normalizedCode);
        if (result != null) return result;
      } on Object {
        hadFailure = true;
      }
    }
    throw AvacaScraperException(
      hadFailure ? 'scraper_unavailable' : 'work_not_found',
      hadFailure
          ? 'configured Server scraper sources are unavailable'
          : 'work code was not found by configured Server scraper sources',
    );
  }

  @override
  Future<AvacaWorkMetadata> resolveWorkDetails(String code) async {
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) {
      throw const AvacaScraperException(
        'invalid_work_code',
        'work code is empty',
      );
    }
    if (sources.isEmpty) {
      throw const AvacaScraperException(
        'scraper_not_configured',
        'no Server scraper source is configured',
      );
    }
    var hadFailure = false;
    for (final source in sources) {
      try {
        if (source is AvacaDetailedScrapeSource) {
          final detailedSource = source as AvacaDetailedScrapeSource;
          final details = await detailedSource.fetchWorkDetails(normalizedCode);
          if (details != null) return details;
          continue;
        }
        final summary = await source.fetchWork(normalizedCode);
        if (summary != null) {
          return AvacaWorkMetadata(summary: summary, source: source.id);
        }
      } on Object {
        hadFailure = true;
      }
    }
    throw AvacaScraperException(
      hadFailure ? 'scraper_unavailable' : 'work_not_found',
      hadFailure
          ? 'configured Server scraper sources are unavailable'
          : 'work code was not found by configured Server scraper sources',
    );
  }
}

class UnavailableAvacaScraper implements AvacaScraper {
  const UnavailableAvacaScraper();

  @override
  Future<AvacaWorkSummary> resolveWork(String code) =>
      Future<AvacaWorkSummary>.error(
        UnsupportedError('Server scraper is not configured'),
      );
}
