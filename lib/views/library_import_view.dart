import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../core/database.dart';
import '../l10n/app_localizations.dart';
import '../library/library_android_storage_access.dart';
import '../library/library_exact_resolver.dart';
import '../library/library_filesystem.dart';
import '../library/library_filename_parser.dart';
import '../library/library_image_downloader.dart';
import '../library/library_import_service.dart';
import '../library/library_import_session.dart';
import '../library/library_media_probe.dart';
import '../library/library_operation_gate.dart';
import '../library/library_repository.dart';
import '../library/library_source_factory.dart';
import '../models/scrape_source_id.dart';
import '../services/scrape/scrape_source.dart';

class LibraryImportView extends StatefulWidget {
  const LibraryImportView({
    super.key,
    required this.db,
    this.directoryPicker,
    this.repository,
    this.scanner,
    this.operationGate,
  });

  final AppDatabase db;
  final Future<String?> Function()? directoryPicker;
  final LibraryRepository? repository;
  final LibraryFolderScanner? scanner;
  final LibraryOperationGate? operationGate;

  @override
  State<LibraryImportView> createState() => _LibraryImportViewState();
}

class _LibraryImportViewState extends State<LibraryImportView> {
  final LibraryFilesystem _filesystem = LibraryFilesystem();
  final LibraryAndroidStorageAccess _androidStorageAccess =
      const LibraryAndroidStorageAccess();
  final LibraryFilenameParser _parser = const LibraryFilenameParser();
  final LibraryImportSession _session = LibraryImportSession();
  final Map<String, TextEditingController> _manualCodeControllers = {};
  late final LibraryFolderScanner _scanner;
  late final LibraryRepository _repository;

  LibraryImportPlan? _reviewPlan;
  LibraryPreflightReport? _preflight;
  final Map<String, String?> _primaryByWorkCode = {};
  bool _reviewing = false;
  bool _busy = false;
  String? _message;
  LibraryImportBatchResult? _result;
  LibraryImportProgress? _progress;
  LibraryOperationGate? _operationGate;

  LibraryOperationGate get _gate => _operationGate ??=
      widget.operationGate ?? LibraryOperationGate.forDatabase(widget.db);

  @override
  void initState() {
    super.initState();
    _scanner =
        widget.scanner ??
        LibraryFolderScanner(parser: _parser, filesystem: _filesystem);
    _repository = widget.repository ?? LibraryRepository(db: widget.db);
    _restoreRoot();
  }

  @override
  void dispose() {
    for (final controller in _manualCodeControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _restoreRoot() async {
    final root = await _repository.activeLibraryRoot();
    final fallbackRoot = Platform.isAndroid
        ? path.join(widget.db.baseDir, 'library')
        : null;
    if (root == null && fallbackRoot != null) {
      await Directory(fallbackRoot).create(recursive: true);
    }
    if (!mounted) return;
    _session.setLibraryRoot(root ?? fallbackRoot);
    setState(() {});
  }

  Future<void> _selectFolder({required bool libraryRoot}) async {
    final selected =
        await (widget.directoryPicker?.call() ?? FilePicker.getDirectoryPath());
    if (selected == null || selected.trim().isEmpty || !mounted) return;
    if (libraryRoot) {
      _session.setLibraryRoot(selected);
      _clearReviewState();
    } else {
      _session.setSourceFolder(selected);
      _disposeManualCodeControllers();
      _clearReviewState();
    }
    setState(() {
      _message = null;
      _result = null;
      _progress = null;
    });
  }

  Future<void> _scan() async {
    final localizations = AppLocalizations.of(context);
    final source = _session.sourceFolder;
    if (source == null) {
      setState(() => _message = localizations.libraryImportNoFolder);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _result = null;
      _progress = null;
      _clearReviewState();
    });
    try {
      if (!await _androidStorageAccess.ensureMediaReadAccess()) {
        if (mounted) {
          setState(
            () => _message = localizations.libraryImportMediaAccessRequired,
          );
        }
        return;
      }
      final entries = await _scanner.scan(source);
      if (!mounted) return;
      _session.setEntries(entries);
      _replaceManualCodeControllers();
      setState(() {
        if (entries.isEmpty) {
          _message = localizations.libraryImportNoRecognizable;
        }
      });
    } on Object catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleEntry(int index, bool selected) {
    _session.setSelected(index, selected);
    setState(() {});
  }

  void _selectAllRecognizable() {
    _session.selectAllRecognizable();
    setState(() {});
  }

  void _clearSelection() {
    _session.clearSelection();
    setState(() {});
  }

  void _applyManualCode(int index, String value) {
    _session.applyManualCode(index, value);
    setState(() {});
  }

  Future<void> _reviewSelected() async {
    final localizations = AppLocalizations.of(context);
    final source = _session.sourceFolder;
    final root = _session.libraryRoot;
    if (source == null) {
      setState(() => _message = localizations.libraryImportNoFolder);
      return;
    }
    if (root == null) {
      setState(() => _message = localizations.libraryImportNoRoot);
      return;
    }
    _flushManualCodes();
    if (_session.selectedEntries.isEmpty) {
      setState(() => _message = localizations.libraryImportSelected(0));
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _result = null;
      _preflight = null;
      _progress = null;
    });
    try {
      final plan = await _withImportService(
        (service) => service.buildPlan(
          sourceFolder: source,
          libraryRoot: root,
          selectedEntries: _session.selectedEntries,
          revision: _session.revision,
          onProgress: _handleProgress,
          // Review may show unresolved primary choices. Commit always
          // rebuilds with an explicit choice for multi-performer Works.
          allowImplicitPrimary: true,
        ),
      );
      if (!mounted) return;
      _reviewPlan = plan;
      _primaryByWorkCode
        ..clear()
        ..addAll(_initialPrimaryChoices(plan));
      setState(() {
        _reviewing = true;
        // The plan is complete; do not leave the last build phase (usually
        // `probing`) rendered as if it were still active in Review.
        _progress = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final localizations = AppLocalizations.of(context);
    final source = _session.sourceFolder;
    final root = _session.libraryRoot;
    if (source == null) {
      setState(() => _message = localizations.libraryImportNoFolder);
      return;
    }
    if (root == null) {
      setState(() => _message = localizations.libraryImportNoRoot);
      return;
    }
    final reviewPlan = _reviewPlan;
    if (reviewPlan == null) {
      await _reviewSelected();
      return;
    }
    _flushManualCodes();
    final missingPrimary = _missingPrimaryCodes(reviewPlan);
    if (missingPrimary.isNotEmpty) {
      setState(
        () => _message =
            '${localizations.libraryImportPrimaryRequired}\n${missingPrimary.join(', ')}',
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _preflight = null;
      _progress = null;
    });
    try {
      final result = await _gate.run(
        () => _withImportService((service) async {
          final plan = await service.buildPlan(
            sourceFolder: source,
            libraryRoot: root,
            selectedEntries: _session.selectedEntries,
            revision: _session.revision,
            primaryActressSelector: (details) =>
                _primaryByWorkCode[details.code.trim().toUpperCase()],
            onProgress: _handleProgress,
          );
          if (plan.issues.isNotEmpty) {
            if (mounted) {
              setState(() {
                _reviewPlan = plan;
                _preflight = null;
                _message = plan.issues.join('\n');
              });
            }
            return null;
          }
          final preflight = await service.preflight(
            plan,
            onProgress: _handleProgress,
          );
          if (!mounted) return null;
          if (!preflight.isReady) {
            setState(() {
              _reviewPlan = plan;
              _preflight = preflight;
              _message = [
                localizations.libraryImportCommitBlocked,
                ...preflight.errors.map((issue) => issue.toString()),
                ...preflight.items
                    .where((item) => item.error != null)
                    .map((item) => '${item.item.details.code}: ${item.error}'),
              ].join('\n');
            });
            return null;
          }
          return service.execute(plan, preflight, onProgress: _handleProgress);
        }),
      );
      if (!mounted || result == null) return;
      _session.reconcileAfterImport(
        result.items
            .where((item) => item.state == LibraryImportResultState.succeeded)
            .map((item) => item.sourcePath),
      );
      _replaceManualCodeControllers();
      setState(() {
        _result = result;
        _reviewing = false;
        _reviewPlan = null;
        _preflight = null;
        _primaryByWorkCode.clear();
      });
    } on Object catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _choosePrimary(String code, String value) {
    _primaryByWorkCode[code] = value;
    setState(() {
      _preflight = null;
      _message = null;
    });
  }

  void _handleProgress(LibraryImportProgress progress) {
    if (!mounted) return;
    setState(() => _progress = progress);
  }

  void _backToScan() {
    setState(() {
      _reviewing = false;
      _preflight = null;
      _message = null;
    });
  }

  Future<T> _withImportService<T>(
    Future<T> Function(LibraryImportService service) action,
  ) async {
    final factory = LibrarySourceFactory(db: widget.db);
    Map<ScrapeSourceId, ScrapeSource>? sources;
    final probe = FfmpegKitMediaProbe();
    final imageDownloader = WorkImageLibraryDownloader();
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
        imageDownloader: imageDownloader,
      );
      return await action(service);
    } finally {
      for (final sourceAdapter in sources?.values ?? const <ScrapeSource>[]) {
        sourceAdapter.close();
      }
      imageDownloader.close();
      probe.close();
    }
  }

  Map<String, String?> _initialPrimaryChoices(LibraryImportPlan plan) {
    final namesByCode = _performerNamesByCode(plan);
    return <String, String?>{
      for (final entry in namesByCode.entries)
        entry.key: entry.value.length == 1 ? entry.value.single : null,
    };
  }

  Map<String, List<String>> _performerNamesByCode(LibraryImportPlan plan) {
    final namesByCode = <String, List<String>>{};
    for (final item in plan.items) {
      final code = item.details.code.trim().toUpperCase();
      final names = namesByCode.putIfAbsent(code, () => <String>[]);
      for (final performer in item.performers) {
        final name = performer['name']?.toString().trim();
        if (name != null &&
            name.isNotEmpty &&
            !names.any(
              (existing) => existing.toLowerCase() == name.toLowerCase(),
            )) {
          names.add(name);
        }
      }
    }
    return namesByCode;
  }

  List<String> _missingPrimaryCodes(LibraryImportPlan plan) {
    final namesByCode = _performerNamesByCode(plan);
    return [
      for (final entry in namesByCode.entries)
        if (entry.value.length > 1 &&
            (_primaryByWorkCode[entry.key]?.trim().isEmpty ?? true))
          entry.key,
    ];
  }

  void _flushManualCodes() {
    for (var index = 0; index < _session.entries.length; index++) {
      final entry = _session.entries[index];
      final controller = _manualCodeControllers[entry.sourcePath];
      if (controller != null && controller.text != entry.parseResult.code) {
        _session.applyManualCode(index, controller.text);
      }
    }
  }

  void _replaceManualCodeControllers() {
    _disposeManualCodeControllers();
    for (final entry in _session.entries) {
      _manualCodeControllers[entry.sourcePath] = TextEditingController(
        text: entry.parseResult.code ?? '',
      );
    }
  }

  void _disposeManualCodeControllers() {
    for (final controller in _manualCodeControllers.values) {
      controller.dispose();
    }
    _manualCodeControllers.clear();
  }

  void _clearReviewState() {
    _reviewing = false;
    _reviewPlan = null;
    _preflight = null;
    _primaryByWorkCode.clear();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _reviewing
              ? localizations.libraryImportReviewTitle
              : localizations.libraryImportTitle,
        ),
      ),
      body: SafeArea(
        child: _reviewing
            ? _buildReview(localizations)
            : _buildScan(localizations),
      ),
    );
  }

  Widget _buildScan(AppLocalizations localizations) {
    final selectedCount = _session.selectedCount;
    final hasEntries = _session.entries.isNotEmpty;
    return Column(
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
              OutlinedButton(
                onPressed: !_busy && hasEntries ? _selectAllRecognizable : null,
                child: Text(localizations.libraryImportSelectAll),
              ),
              OutlinedButton(
                onPressed: !_busy && hasEntries ? _clearSelection : null,
                child: Text(localizations.libraryImportClearAll),
              ),
            ],
          ),
        ),
        _pathSummary(localizations),
        if (_progress != null) _progressBanner(localizations),
        if (_message != null) _errorMessage(),
        Expanded(child: _buildEntries(localizations)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(localizations.libraryImportSelected(selectedCount)),
              ),
              FilledButton.icon(
                onPressed: _busy || selectedCount == 0 ? null : _reviewSelected,
                icon: const Icon(Icons.rate_review_outlined),
                label: Text(localizations.libraryImportReview),
              ),
            ],
          ),
        ),
        if (_result != null) _resultSummary(localizations),
      ],
    );
  }

  Widget _buildReview(AppLocalizations localizations) {
    final plan = _reviewPlan;
    if (plan == null || plan.items.isEmpty) {
      return Column(
        children: [
          if (_progress != null) _progressBanner(localizations),
          if (_message != null) _errorMessage(),
          if (plan?.issues.isNotEmpty ?? false)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(localizations.libraryImportReviewIssues),
                    for (final issue in plan!.issues) Text(issue.toString()),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: Text(localizations.libraryImportReviewNoItems),
            ),
          ),
          _reviewActions(localizations),
        ],
      );
    }
    final groups = <String, List<LibraryImportPlanItem>>{};
    for (final item in plan.items) {
      groups
          .putIfAbsent(item.details.code.trim().toUpperCase(), () => [])
          .add(item);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${localizations.libraryImportSource}: ${_session.sourceFolder ?? '-'}\n'
              '${localizations.libraryImportDestination}: ${_session.libraryRoot ?? '-'}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (_progress != null) _progressBanner(localizations),
        if (_message != null) _errorMessage(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              if (plan.issues.isNotEmpty)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(localizations.libraryImportReviewIssues),
                        for (final issue in plan.issues) Text(issue.toString()),
                      ],
                    ),
                  ),
                ),
              for (final entry in groups.entries)
                _reviewWorkCard(entry.key, entry.value, localizations),
              if (_preflight != null && !_preflight!.isReady)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(localizations.libraryImportCommitBlocked),
                        for (final issue in _preflight!.errors)
                          Text(issue.toString()),
                        for (final item in _preflight!.items)
                          if (item.error != null)
                            Text('${item.item.details.code}: ${item.error}'),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        _reviewActions(localizations),
      ],
    );
  }

  Widget _reviewWorkCard(
    String code,
    List<LibraryImportPlanItem> items,
    AppLocalizations localizations,
  ) {
    final first = items.first;
    final performerNames = <String>[];
    for (final item in items) {
      for (final performer in item.performers) {
        final name = performer['name']?.toString().trim();
        if (name != null &&
            name.isNotEmpty &&
            !performerNames.any(
              (existing) => existing.toLowerCase() == name.toLowerCase(),
            )) {
          performerNames.add(name);
        }
      }
    }
    final primary = _primaryByWorkCode[code];
    final destination = primary == null || primary.trim().isEmpty
        ? '-'
        : '${_filesystem.safeSegment(primary)}/${_filesystem.safeSegment(code)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$code · ${first.details.title}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${localizations.libraryImportReviewDestination}: $destination',
            ),
            const SizedBox(height: 8),
            if (performerNames.length <= 1)
              Text(
                '${localizations.libraryImportPrimaryPerformer}: '
                '${performerNames.firstOrNull ?? '-'}',
              )
            else ...[
              Text(localizations.libraryImportPrimaryPerformer),
              DropdownButton<String>(
                isExpanded: true,
                value: performerNames.contains(primary) ? primary : null,
                hint: Text(localizations.libraryImportChoosePrimary),
                items: [
                  for (final name in performerNames)
                    DropdownMenuItem<String>(value: name, child: Text(name)),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) _choosePrimary(code, value);
                      },
              ),
            ],
            const Divider(),
            Text('${localizations.libraryImportReviewMedia}: ${items.length}'),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${path.basename(item.entry.sourcePath)} → '
                  '${item.normalizedFileName} · '
                  '${item.entry.parseResult.variantToken ?? '-'} · '
                  '${item.entry.parseResult.partLabel ?? '-'}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _reviewActions(AppLocalizations localizations) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: _busy ? null : _backToScan,
            child: Text(localizations.libraryImportBackToScan),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _busy ? null : _commit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt),
            label: Text(localizations.libraryImportCommit),
          ),
        ],
      ),
    );
  }

  Widget _pathSummary(AppLocalizations localizations) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '${localizations.libraryImportSource}: ${_session.sourceFolder ?? '-'}\n'
          '${localizations.libraryImportDestination}: ${_session.libraryRoot ?? '-'}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _errorMessage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SelectableText(
        _message!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Widget _progressBanner(AppLocalizations localizations) {
    final progress = _progress!;
    return Padding(
      key: const Key('library-import-progress'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          localizations.libraryImportProgress(
            progress.itemIndex,
            progress.itemCount,
            progress.code,
            progress.sourceFileName,
            localizations.libraryImportProgressPhase(progress.phase.name),
          ),
        ),
      ),
    );
  }

  Widget _buildEntries(AppLocalizations localizations) {
    final entries = _session.entries;
    if (entries.isEmpty) {
      return Center(
        child: Text(
          _result == null
              ? localizations.libraryImportNoFolder
              : localizations.libraryImportNoPending,
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final parsed = entry.parseResult;
        final importable = parsed.isImportable;
        final controller = _manualCodeControllers[entry.sourcePath];
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                CheckboxListTile(
                  value: entry.selected,
                  onChanged: !_busy
                      ? (value) => _toggleEntry(index, value ?? false)
                      : null,
                  title: Text(entry.originalFileName),
                  subtitle: Text(
                    '${importable ? localizations.libraryImportStatusReady : localizations.libraryImportStatusNeedsCorrection} · '
                    '${parsed.code ?? '-'} · ${parsed.variantToken ?? '-'} · '
                    '${parsed.partLabel ?? '-'}\n${parsed.diagnostic}',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
                  child: Focus(
                    onFocusChange: (hasFocus) {
                      if (!hasFocus && controller != null) {
                        _applyManualCode(index, controller.text);
                      }
                    },
                    child: TextField(
                      controller: controller,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: localizations.libraryImportManualCode,
                        isDense: true,
                      ),
                      onChanged: (value) => _applyManualCode(index, value),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _resultSummary(AppLocalizations localizations) {
    final result = _result!;
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localizations.libraryImportResult(
              result.succeededCount,
              result.duplicateCount,
              result.failedCount,
            ),
          ),
          for (final item in result.items)
            Text('${item.code}: ${item.message}'),
        ],
      ),
    );
  }
}
