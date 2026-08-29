import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/database.dart';
import '../l10n/app_localizations.dart';
import '../library/library_exact_resolver.dart';
import '../library/library_filesystem.dart';
import '../library/library_image_downloader.dart';
import '../library/library_import_service.dart';
import '../library/library_media_probe.dart';
import '../library/library_filename_parser.dart';
import '../library/library_info_store.dart';
import '../library/library_models.dart';
import '../library/library_repository.dart';
import '../library/library_source_factory.dart';
import '../models/scrape_source_id.dart';
import '../services/scrape/scrape_source.dart';

class LibraryImportView extends StatefulWidget {
  const LibraryImportView({super.key, required this.db});

  final AppDatabase db;

  @override
  State<LibraryImportView> createState() => _LibraryImportViewState();
}

class _LibraryImportViewState extends State<LibraryImportView> {
  final LibraryFilesystem _filesystem = LibraryFilesystem();
  final LibraryFilenameParser _parser = const LibraryFilenameParser();
  late final LibraryFolderScanner _scanner;
  late final LibraryRepository _repository;
  String? _sourceFolder;
  String? _libraryRoot;
  List<LibraryScanEntry> _entries = const [];
  bool _busy = false;
  String? _message;
  LibraryImportBatchResult? _result;

  @override
  void initState() {
    super.initState();
    _scanner = LibraryFolderScanner(parser: _parser, filesystem: _filesystem);
    _repository = LibraryRepository(db: widget.db);
    _restoreRoot();
  }

  Future<void> _restoreRoot() async {
    final root = await _repository.activeLibraryRoot();
    if (!mounted) return;
    setState(() => _libraryRoot = root);
  }

  Future<void> _selectFolder({required bool libraryRoot}) async {
    final selected = await FilePicker.getDirectoryPath();
    if (selected == null || selected.trim().isEmpty || !mounted) return;
    setState(() {
      if (libraryRoot) {
        _libraryRoot = selected;
      } else {
        _sourceFolder = selected;
        _entries = const [];
        _result = null;
      }
      _message = null;
    });
    if (libraryRoot) {
      await _repository.setActiveLibraryRoot(
        _filesystem.absolutePath(selected),
      );
      try {
        final report = await LibraryReindexService(
          repository: _repository,
          filesystem: _filesystem,
        ).reindex(selected);
        if (mounted && report.errors.isNotEmpty) {
          setState(() => _message = report.errors.join('\n'));
        }
      } on Object catch (error) {
        if (mounted) setState(() => _message = '$error');
      }
    }
  }

  Future<void> _scan() async {
    final localizations = AppLocalizations.of(context);
    final source = _sourceFolder;
    if (source == null) {
      setState(() => _message = localizations.libraryImportNoFolder);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _result = null;
    });
    try {
      final entries = await _scanner.scan(source);
      if (!mounted) return;
      setState(() => _entries = entries);
    } on Object catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleEntry(int index, bool selected) {
    setState(() {
      final next = [..._entries];
      next[index] = next[index].copyWith(selected: selected);
      _entries = next;
    });
  }

  void _applyManualCode(int index, String value) {
    setState(() {
      final next = [..._entries];
      next[index] = next[index].copyWith(
        parseResult: _parser.applyManualCode(next[index].parseResult, value),
      );
      _entries = next;
    });
  }

  Future<void> _startImport() async {
    final localizations = AppLocalizations.of(context);
    final source = _sourceFolder;
    final root = _libraryRoot;
    if (source == null) {
      setState(() => _message = localizations.libraryImportNoFolder);
      return;
    }
    if (root == null) {
      setState(() => _message = localizations.libraryImportNoRoot);
      return;
    }
    final selected = _entries.where((entry) => entry.selected).toList();
    if (selected.isEmpty) {
      setState(() => _message = localizations.libraryImportSelected(0));
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _result = null;
    });
    final factory = LibrarySourceFactory(db: widget.db);
    Map<ScrapeSourceId, ScrapeSource>? sources;
    WorkImageLibraryDownloader? imageDownloader;
    final probe = FfmpegKitMediaProbe();
    try {
      sources = await factory.createSources();
      final service = LibraryImportService(
        repository: _repository,
        resolver: LibraryExactWorkResolver(sources: sources),
        mediaProbe: probe,
        filesystem: _filesystem,
        shortcutManager: Platform.isWindows
            ? const WindowsShortcutManager()
            : const NoopShortcutManager(),
        imageDownloader: imageDownloader = WorkImageLibraryDownloader(),
      );
      final plan = await service.buildPlan(
        sourceFolder: source,
        libraryRoot: root,
        selectedEntries: selected,
      );
      final preflight = await service.preflight(plan);
      final result = await service.execute(plan, preflight);
      if (mounted) setState(() => _result = result);
    } on Object catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      for (final sourceAdapter in sources?.values ?? const <ScrapeSource>[]) {
        sourceAdapter.close();
      }
      imageDownloader?.close();
      probe.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final selectedCount = _entries.where((entry) => entry.selected).length;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.libraryImportTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                localizations.libraryImportPhase1ReadOnly,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _selectFolder(libraryRoot: false),
                    icon: const Icon(Icons.folder_open),
                    label: Text(localizations.libraryImportSelectFolder),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _selectFolder(libraryRoot: true),
                    icon: const Icon(Icons.library_books_outlined),
                    label: Text(localizations.libraryImportSelectRoot),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Icons.search),
                    label: Text(localizations.libraryImportScan),
                  ),
                ],
              ),
            ),
            _pathSummary(localizations),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: SelectableText(
                  _message!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(child: _buildEntries(localizations)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      localizations.libraryImportSelected(selectedCount),
                    ),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _startImport,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(localizations.libraryImportConfirm),
                  ),
                ],
              ),
            ),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.libraryImportResult(
                        _result!.succeededCount,
                        _result!.duplicateCount,
                        _result!.failedCount,
                      ),
                    ),
                    for (final item in _result!.items)
                      Text('${item.code}: ${item.message}'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pathSummary(AppLocalizations localizations) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '${localizations.libraryImportSelectFolder}: ${_sourceFolder ?? '-'}\n'
          '${localizations.libraryImportSelectRoot}: ${_libraryRoot ?? '-'}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildEntries(AppLocalizations localizations) {
    if (_entries.isEmpty) {
      return Center(child: Text(localizations.libraryImportNoFolder));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final parsed = entry.parseResult;
        final importable = parsed.isImportable;
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                CheckboxListTile(
                  value: entry.selected,
                  onChanged: importable
                      ? (value) => _toggleEntry(index, value ?? false)
                      : null,
                  title: Text(entry.originalFileName),
                  subtitle: Text(
                    '${parsed.code ?? '-'} · ${parsed.variantToken ?? '-'} · '
                    '${parsed.partLabel ?? '-'}\n${parsed.diagnostic}',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
                  child: TextFormField(
                    key: ValueKey('${entry.sourcePath}:${parsed.code}'),
                    initialValue: parsed.code ?? '',
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: localizations.libraryImportManualCode,
                      isDense: true,
                    ),
                    onFieldSubmitted: (value) => _applyManualCode(index, value),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
