import '../models/scrape_source_id.dart';
import '../services/scrape/scrape_models.dart';
import '../services/scrape/scrape_source.dart';

class LibraryResolutionResult {
  const LibraryResolutionResult({
    required this.requestedCode,
    this.details,
    this.source,
    this.diagnostics = const [],
  });

  final String requestedCode;
  final ScrapeWorkDetails? details;
  final ScrapeSourceId? source;
  final List<String> diagnostics;

  bool get isResolved => details != null;
}

/// Resolves one exact code through source-owned lookup capabilities.
///
/// This deliberately does not call the legacy canonicalizer or catalog merge
/// logic.  A source returning a different code is treated as a miss, because
/// a folder filename cannot authorize an identity merge.
class LibraryExactWorkResolver {
  LibraryExactWorkResolver({
    required Map<ScrapeSourceId, ScrapeSource> sources,
    Iterable<ScrapeSourceId>? priority,
  }) : _sources = Map.unmodifiable(sources),
       _priority = List.unmodifiable(
         priority ??
             const [
               ScrapeSourceId.avwiki,
               ScrapeSourceId.avbase,
               ScrapeSourceId.javbus,
             ],
       );

  final Map<ScrapeSourceId, ScrapeSource> _sources;
  final List<ScrapeSourceId> _priority;

  Future<LibraryResolutionResult> resolve(String code) async {
    final requested = _exactCode(code);
    if (requested == null) {
      return LibraryResolutionResult(
        requestedCode: code,
        diagnostics: const ['code is empty'],
      );
    }
    final diagnostics = <String>[];
    for (final sourceId in _priority) {
      final source = _sources[sourceId];
      if (source == null) continue;
      try {
        final details = await source.fetchWorkDetailsByCode(requested);
        if (details == null) {
          diagnostics.add('${sourceId.storageValue}: no exact result');
          continue;
        }
        if (_exactCode(details.code) != requested) {
          diagnostics.add(
            '${sourceId.storageValue}: returned ${details.code}, not $requested',
          );
          continue;
        }
        return LibraryResolutionResult(
          requestedCode: requested,
          details: details,
          source: sourceId,
          diagnostics: List.unmodifiable(diagnostics),
        );
      } on Object catch (error) {
        diagnostics.add('${sourceId.storageValue}: ${error.runtimeType}');
      }
    }
    return LibraryResolutionResult(
      requestedCode: requested,
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  static String? _exactCode(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.toUpperCase();
  }
}
