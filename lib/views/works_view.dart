import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../components/app_snackbar.dart';
import '../controllers/works_controller.dart';
import '../core/database.dart';
import '../l10n/app_localizations.dart';
import '../models/work_scrape_options.dart';
import '../services/javbus/javbus_client.dart';
import '../services/javbus/javbus_verification.dart';
import '../services/works_scrape_service.dart';
import 'work_detail_view.dart';

typedef WorksScrapeExecutor =
    Future<WorksScrapeResult> Function(
      WorkScrapeOptions options,
      WorksScrapeCancellationToken token,
      void Function(WorksScrapeProgress progress) onProgress,
    );

class WorksView extends StatefulWidget {
  const WorksView({
    super.key,
    required this.db,
    required this.actressId,
    this.scrapeExecutor,
  });

  final AppDatabase db;
  final int actressId;
  final WorksScrapeExecutor? scrapeExecutor;

  @override
  State<WorksView> createState() => _WorksViewState();
}

class _WorksViewState extends State<WorksView> {
  late final WorksController controller;
  late final Future<void> initFuture;
  final selectedWorkIds = <int>{};
  var deletionBusy = false;

  @override
  void initState() {
    super.initState();
    controller = WorksController(db: widget.db, actressId: widget.actressId);
    initFuture = controller.init();
    controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    controller.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get isSelecting => selectedWorkIds.isNotEmpty;

  void _clearSelection() {
    if (selectedWorkIds.isEmpty || !mounted) {
      return;
    }
    setState(selectedWorkIds.clear);
  }

  void _handleBack() {
    if (isSelecting) {
      _clearSelection();
      return;
    }
    Navigator.of(context).pop();
  }

  void _toggleSelection(Map<String, Object?> work) {
    if (deletionBusy) {
      return;
    }
    final workId = work['id'];
    if (workId is! int) {
      return;
    }
    setState(() {
      if (!selectedWorkIds.add(workId)) {
        selectedWorkIds.remove(workId);
      }
    });
  }

  Future<void> _openDeleteConfirmation() async {
    if (deletionBusy || selectedWorkIds.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const Key('works-delete-confirm'),
        title: Text(l10n.deleteWorksTitle),
        content: Text(l10n.deleteWorksWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(l10n.confirmDelete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _deleteSelectedWorks();
    }
  }

  Future<void> _deleteSelectedWorks() async {
    if (deletionBusy || selectedWorkIds.isEmpty) {
      return;
    }
    final requested = selectedWorkIds.toList(growable: false);
    setState(() => deletionBusy = true);
    WorkDeletionReport? report;
    Object? error;
    try {
      report = await widget.db.deleteWorksWithReport(requested);
      if (report.databaseCommitted) {
        for (final imagePath in report.cacheEvictionPaths) {
          await FileImage(File(imagePath)).evict();
        }
        await controller.reloadWorks();
      }
    } catch (caught) {
      error = caught;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      deletionBusy = false;
      if (report?.databaseCommitted == true) {
        selectedWorkIds.clear();
      }
    });
    final failed = error != null || report?.databaseCommitted != true;
    final message = failed
        ? AppLocalizations.of(context).deleteFailed
        : AppLocalizations.of(context).worksDeleted(report!.deletedWorkRows);
    if (failed) {
      AppSnackBar.showError(context, message);
    } else {
      AppSnackBar.showSuccess(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snapshot) {
        return PopScope(
          canPop: !isSelecting && !deletionBusy,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && isSelecting) {
              _clearSelection();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: _handleBack,
              ),
              title: Text(_buildTitle(context)),
              actions: [
                if (isSelecting)
                  IconButton(
                    key: const Key('works-delete-action'),
                    tooltip: AppLocalizations.of(context).deleteWorks,
                    onPressed: deletionBusy ? null : _openDeleteConfirmation,
                    icon: const Icon(Icons.delete_outline),
                  )
                else
                  IconButton(
                    key: const Key('works-scrape-action'),
                    tooltip: AppLocalizations.of(context).scrapeWorks,
                    onPressed: controller.status == WorksLoadStatus.loaded
                        ? _openScrapeSettings
                        : null,
                    icon: const Icon(Icons.manage_search),
                  ),
              ],
            ),
            body: _buildBody(context),
          ),
        );
      },
    );
  }

  String _buildTitle(BuildContext context) {
    if (controller.status == WorksLoadStatus.loaded &&
        controller.actressName.isNotEmpty) {
      return AppLocalizations.of(
        context,
      ).actressWorksTitle(controller.actressName);
    }

    return AppLocalizations.of(context).works;
  }

  Widget _buildBody(BuildContext context) {
    return switch (controller.status) {
      WorksLoadStatus.loading => const Center(
        child: CircularProgressIndicator(),
      ),
      WorksLoadStatus.error => Center(
        child: Text(AppLocalizations.of(context).loadFailedGeneric),
      ),
      WorksLoadStatus.notFound => Center(
        child: Text(AppLocalizations.of(context).dataNotFound),
      ),
      WorksLoadStatus.loaded =>
        controller.works.isEmpty
            ? Center(child: Text(AppLocalizations.of(context).noWorks))
            : _buildWorksGrid(),
    };
  }

  Widget _buildWorksGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth <= 600
            ? 3
            : constraints.maxWidth <= 1000
            ? 4
            : 6;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 24,
            childAspectRatio: 0.54,
          ),
          itemCount: controller.works.length,
          itemBuilder: (context, index) {
            final work = controller.works[index];
            final workId = work['id'];
            final selected = workId is int && selectedWorkIds.contains(workId);
            return KeyedSubtree(
              key: selected ? Key('work-card-selected-$workId') : null,
              child: _WorkCard(
                key: Key('work-card-$workId'),
                work: work,
                selected: selected,
                onTap: () {
                  if (isSelecting) {
                    _toggleSelection(work);
                  } else {
                    _openWorkDetail(work);
                  }
                },
                onLongPress: () => _toggleSelection(work),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openWorkDetail(Map<String, Object?> work) async {
    final workId = work['id'];
    if (workId is! int) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => WorkDetailView(db: widget.db, workId: workId),
      ),
    );
  }

  Future<void> _openScrapeSettings() async {
    WorkScrapeOptions initial;
    try {
      initial = WorkScrapeOptions.decode(
        await widget.db.getSetting('works_scrape_options'),
      );
    } catch (_) {
      initial = const WorkScrapeOptions();
    }
    if (!mounted) {
      return;
    }

    final options = await showDialog<WorkScrapeOptions>(
      context: context,
      builder: (context) => _ScrapeSettingsDialog(initial: initial),
    );
    if (options == null || !mounted) {
      return;
    }

    try {
      await widget.db.setSetting('works_scrape_options', options.encode());
    } catch (_) {
      // 儲存偏好失敗不應阻止本次刮削。
    }
    await _runScrape(options);
  }

  Future<void> _runScrape(WorkScrapeOptions options) async {
    final token = WorksScrapeCancellationToken();
    final progress = ValueNotifier<WorksScrapeProgress?>(null);
    final executor = widget.scrapeExecutor ?? _defaultScrapeExecutor;
    NavigatorState? progressNavigator;
    Route<void>? progressRoute;

    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        progressNavigator = Navigator.of(dialogContext);
        progressRoute = ModalRoute.of(dialogContext);
        return PopScope(
          canPop: false,
          child: _ScrapeProgressDialog(
            progress: progress,
            onCancel: token.cancel,
          ),
        );
      },
    );
    await WidgetsBinding.instance.endOfFrame;

    WorksScrapeResult? result;
    Object? scrapeError;
    try {
      result = await executor(
        options,
        token,
        (value) => progress.value = value,
      );
      await controller.reloadWorks();
    } catch (error) {
      scrapeError = error;
    } finally {
      final route = progressRoute;
      if (route != null && route.isActive) {
        progressNavigator?.removeRoute(route);
      }
      await dialog;
      progress.dispose();
    }

    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final completedResult = result;
    if (scrapeError != null || completedResult == null) {
      AppSnackBar.showError(context, l10n.scrapeFailed);
      return;
    }

    final cancelled = completedResult.cancelled;
    var message = cancelled
        ? l10n.scrapeCancelled(
            completedResult.saved,
            completedResult.excluded,
            completedResult.failed,
          )
        : l10n.scrapeComplete(
            completedResult.saved,
            completedResult.excluded,
            completedResult.failed,
          );
    if (!cancelled) {
      message = switch (completedResult.actressImageStatus) {
        ActressImageSyncStatus.unavailable =>
          '$message ${l10n.scrapeAvatarUnavailable}',
        ActressImageSyncStatus.downloadFailed ||
        ActressImageSyncStatus.databaseFailed =>
          '$message ${l10n.scrapeAvatarFailed}',
        ActressImageSyncStatus.notRequested ||
        ActressImageSyncStatus.replaced => message,
      };
    }
    if (cancelled) {
      AppSnackBar.showInfo(context, message);
    } else {
      AppSnackBar.showSuccess(context, message);
    }
  }

  Future<WorksScrapeResult> _defaultScrapeExecutor(
    WorkScrapeOptions options,
    WorksScrapeCancellationToken token,
    void Function(WorksScrapeProgress progress) onProgress,
  ) async {
    String? initialCookies;
    try {
      initialCookies = await widget.db.getSetting('javbus_cookies');
    } catch (_) {
      initialCookies = null;
    }
    final transport = HttpJavBusTransport(
      initialCookieHeader: initialCookies,
      verificationHandler: _showJavBusVerification,
    );
    final service = WorksScrapeService(
      db: widget.db,
      client: JavBusClient(transport: transport),
      actressImageDownloader: HttpActressImageDownloader(
        authenticatedTransport: transport,
      ),
    );
    try {
      return await service.scrape(
        actressId: widget.actressId,
        actressName: controller.actressName,
        aliases: controller.actressAliases,
        options: options,
        cancellationToken: token,
        onProgress: onProgress,
      );
    } finally {
      if (transport.cookieHeader.isNotEmpty) {
        try {
          await widget.db.setSetting('javbus_cookies', transport.cookieHeader);
        } catch (_) {
          // Cookie 儲存失敗不應遮蔽原始刮削結果。
        }
      }
      service.close();
    }
  }

  Future<Map<String, String>?> _showJavBusVerification(
    JavBusVerificationChallenge challenge,
  ) {
    if (!mounted) {
      return Future.value(null);
    }
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _JavBusVerificationDialog(challenge: challenge),
    );
  }
}

class _WorkCard extends StatelessWidget {
  const _WorkCard({
    super.key,
    required this.work,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Map<String, Object?> work;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final title = work['title']?.toString() ?? '';
    final code = work['code']?.toString() ?? '';
    final releaseDate = work['release_date']?.toString() ?? '';
    final imagePath = work['card_image_path']?.toString() ?? '';
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox.expand(
                    child: _LocalWorkImage(
                      path: imagePath,
                      icon: Icons.movie_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colorScheme.primary),
              ),
              const SizedBox(height: 4),
              Text(
                releaseDate,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (selected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.primary, width: 2),
                ),
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: colorScheme.primary,
                      child: Icon(
                        Icons.check,
                        size: 15,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LocalWorkImage extends StatelessWidget {
  const _LocalWorkImage({required this.path, required this.icon});

  final String path;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(context),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(icon, color: colorScheme.onSurfaceVariant, size: 36),
      ),
    );
  }
}

class _ScrapeSettingsDialog extends StatefulWidget {
  const _ScrapeSettingsDialog({required this.initial});

  final WorkScrapeOptions initial;

  @override
  State<_ScrapeSettingsDialog> createState() => _ScrapeSettingsDialogState();
}

class _ScrapeSettingsDialogState extends State<_ScrapeSettingsDialog> {
  final formKey = GlobalKey<FormState>();
  final prefixController = TextEditingController();
  final maxActressCountController = TextEditingController();
  final prefixes = <String>[];
  late bool syncDetails;
  late bool replaceImage;
  late bool fillMissingOnly;

  @override
  void initState() {
    super.initState();
    syncDetails = widget.initial.syncDetails;
    replaceImage = widget.initial.replaceActressImage;
    fillMissingOnly = widget.initial.fillMissingOnly;
    maxActressCountController.text =
        widget.initial.maxActressCount?.toString() ?? '';
    prefixes.addAll(widget.initial.excludedPrefixes);
  }

  @override
  void dispose() {
    prefixController.dispose();
    maxActressCountController.dispose();
    super.dispose();
  }

  void _addPrefix() {
    final value = prefixController.text.trim().toUpperCase();
    if (value.isEmpty || prefixes.contains(value)) {
      return;
    }

    setState(() {
      prefixes.add(value);
      prefixController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.scrapeSettings),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.syncActressDetails),
                  value: syncDetails,
                  onChanged: (value) {
                    setState(() => syncDetails = value ?? false);
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.replaceActressImage),
                  value: replaceImage,
                  onChanged: (value) {
                    setState(() => replaceImage = value ?? false);
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.fillMissingOnly),
                  value: fillMissingOnly,
                  onChanged: (value) {
                    setState(() => fillMissingOnly = value ?? false);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('scrape-max-actress-count-input'),
                  controller: maxActressCountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.maxActressCountLabel,
                    hintText: l10n.maxActressCountHint,
                    isDense: true,
                  ),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) {
                    final cleaned = value?.trim() ?? '';
                    if (cleaned.isEmpty) {
                      return null;
                    }
                    final parsed = int.tryParse(cleaned);
                    return parsed != null && parsed > 0
                        ? null
                        : l10n.maxActressCountInvalid;
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.excludedCodePrefixes,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('scrape-prefix-input'),
                        controller: prefixController,
                        decoration: InputDecoration(
                          hintText: l10n.codePrefixHint,
                          isDense: true,
                        ),
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: (_) => _addPrefix(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      key: const Key('scrape-prefix-add'),
                      tooltip: l10n.addPrefix,
                      onPressed: _addPrefix,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                if (prefixes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final prefix in prefixes)
                        InputChip(
                          label: Text(prefix),
                          onDeleted: () {
                            setState(() => prefixes.remove(prefix));
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (!(formKey.currentState?.validate() ?? false)) {
              return;
            }
            Navigator.of(context).pop(
              WorkScrapeOptions(
                syncDetails: syncDetails,
                replaceActressImage: replaceImage,
                fillMissingOnly: fillMissingOnly,
                maxActressCount: int.tryParse(
                  maxActressCountController.text.trim(),
                ),
                excludedPrefixes: List.unmodifiable(prefixes),
              ),
            );
          },
          child: Text(l10n.startScrape),
        ),
      ],
    );
  }
}

class _ScrapeProgressDialog extends StatelessWidget {
  const _ScrapeProgressDialog({required this.progress, required this.onCancel});

  final ValueListenable<WorksScrapeProgress?> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: ValueListenableBuilder<WorksScrapeProgress?>(
        valueListenable: progress,
        builder: (context, value, child) {
          final total = value?.total ?? 0;
          final current = value?.current ?? 0;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                value: total > 0 ? current / total : null,
              ),
              const SizedBox(height: 16),
              Text(total > 0 ? '$current / $total' : ''),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: Text(AppLocalizations.of(context).cancel),
        ),
      ],
    );
  }
}

class _JavBusVerificationDialog extends StatefulWidget {
  const _JavBusVerificationDialog({required this.challenge});

  final JavBusVerificationChallenge challenge;

  @override
  State<_JavBusVerificationDialog> createState() =>
      _JavBusVerificationDialogState();
}

class _JavBusVerificationDialogState extends State<_JavBusVerificationDialog> {
  final answers = <String, String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final complete = answers.length == widget.challenge.questions.length;

    return AlertDialog(
      title: Text(l10n.javBusVerificationTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.javBusVerificationInstructions),
              const SizedBox(height: 16),
              for (final question in widget.challenge.questions) ...[
                Text(
                  question.prompt,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                RadioGroup<String>(
                  groupValue: answers[question.name],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => answers[question.name] = value);
                    }
                  },
                  child: Column(
                    children: [
                      for (final option in question.options)
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: option.value,
                          title: Text(option.label),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: complete
              ? () => Navigator.of(
                  context,
                ).pop(Map<String, String>.unmodifiable(answers))
              : null,
          child: Text(l10n.javBusVerificationSubmit),
        ),
      ],
    );
  }
}
