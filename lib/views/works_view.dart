import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../components/adaptive_page_layout.dart';
import '../components/aligned_app_bar_back_button.dart';
import '../components/app_snackbar.dart';
import '../components/javbus_verification_dialog.dart';
import '../controllers/works_controller.dart';
import '../core/database.dart';
import '../core/layout.dart';
import '../l10n/app_localizations.dart';
import '../models/scrape_source_settings.dart';
import '../models/work_scrape_options.dart';
import '../services/javbus/javbus_client.dart';
import '../services/javbus/javbus_scrape_source.dart';
import '../services/javbus/javbus_verification.dart';
import '../services/javbus/work_image_downloader.dart';
import '../services/javbus/work_image_policy.dart';
import '../services/minnano/minnano_client.dart';
import '../services/minnano/minnano_scrape_source.dart';
import '../services/minnano/minnano_transport.dart';
import '../services/scrape/scrape_image_downloader.dart';
import '../services/scrape/scrape_models.dart';
import '../services/scrape/scrape_source.dart';
import '../services/scrape/scrape_source_registry.dart';
import '../services/works_scrape_service.dart';
import '../controllers/settings_controller.dart';
import 'work_detail_view.dart';

typedef WorksScrapeExecutor =
    Future<WorksScrapeResult> Function(
      WorkScrapeOptions options,
      WorksScrapeCancellationToken token,
      void Function(WorksScrapeProgress progress) onProgress,
    );

enum _WorksMenuAction { search, scrape }

const _scrapeSettingsDialogRadius = 28.0;

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
  final searchTextController = TextEditingController();
  final searchFocusNode = FocusNode();

  var deletionBusy = false;
  var searchOpen = false;
  late final SettingsController settingsController;

  @override
  void initState() {
    super.initState();

    controller = WorksController(db: widget.db, actressId: widget.actressId);

    settingsController = SettingsController(db: widget.db);

    initFuture = controller.init();

    settingsController.loadFromPrefs();

    controller.addListener(_handleControllerChanged);

    settingsController.addListener(_handleSettingsChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);

    settingsController.removeListener(_handleSettingsChanged);

    settingsController.dispose();

    searchTextController.dispose();
    searchFocusNode.dispose();

    controller.dispose();

    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleSettingsChanged() {
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

    if (searchOpen) {
      _closeSearch();

      return;
    }

    Navigator.of(context).pop();
  }

  void _openSearch() {
    if (searchOpen || !mounted) {
      return;
    }

    setState(() => searchOpen = true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && searchOpen) {
        searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    if (!searchOpen) {
      return;
    }

    searchFocusNode.unfocus();
    searchTextController.clear();
    controller.changeSearch('');

    if (mounted) {
      setState(() => searchOpen = false);
    }
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
          canPop: !isSelecting && !searchOpen && !deletionBusy,

          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && isSelecting) {
              _clearSelection();
            } else if (!didPop && searchOpen) {
              _closeSearch();
            }
          },

          child: Scaffold(
            appBar: AppBar(
              leading: AlignedAppBarBackButton(onPressed: _handleBack),

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
                  _buildOverflowMenu(),
              ],
            ),

            body: AdaptivePageLayout(
              padding: EdgeInsets.zero,
              compactBuilder: (context, tokens) =>
                  _buildWorksContent(context, tokens),
              expandedBuilder: (context, tokens) =>
                  _buildWorksContent(context, tokens),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverflowMenu() {
    final l10n = AppLocalizations.of(context);
    final enabled = controller.status == WorksLoadStatus.loaded;

    return PopupMenuButton<_WorksMenuAction>(
      key: const Key('works-overflow-menu'),
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        switch (action) {
          case _WorksMenuAction.search:
            _openSearch();
          case _WorksMenuAction.scrape:
            _openScrapeSettings();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_WorksMenuAction>(
          key: const Key('works-search-menu-item'),
          value: _WorksMenuAction.search,
          enabled: enabled,
          child: Row(
            children: [
              const Icon(Icons.search),
              const SizedBox(width: 12),
              Text(l10n.searchWorks),
            ],
          ),
        ),
        PopupMenuItem<_WorksMenuAction>(
          key: const Key('works-scrape-menu-item'),
          value: _WorksMenuAction.scrape,
          enabled: enabled,
          child: Row(
            children: [
              const Icon(Icons.manage_search),
              const SizedBox(width: 12),
              Text(l10n.scrapeWorks),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWorksContent(BuildContext context, AppLayoutTokens tokens) {
    return Column(
      children: [
        _buildSearchBar(tokens),
        Expanded(child: _buildBody(context, tokens)),
      ],
    );
  }

  Widget _buildSearchBar(AppLayoutTokens tokens) {
    final isOpen = searchOpen;
    final l10n = AppLocalizations.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.decelerate,
      height: isOpen ? 55 : 0,
      margin: EdgeInsets.only(
        left: tokens.gridPadding.left + 5,
        right: tokens.gridPadding.right + 5,
        top: isOpen ? tokens.gridGap : 0,
        bottom: isOpen ? tokens.gridGap : 0,
      ),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(30),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: searchFocusNode.requestFocus,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.search),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('works-search-field'),
                    controller: searchTextController,
                    focusNode: searchFocusNode,
                    decoration: InputDecoration(
                      hintText: l10n.workCodeSearchHint,
                      isDense: true,
                      filled: false,
                      fillColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                    ),
                    onChanged: controller.changeSearch,
                  ),
                ),
                IconButton(
                  key: const Key('works-search-close'),
                  tooltip: l10n.close,
                  onPressed: _closeSearch,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
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

  Widget _buildBody(BuildContext context, AppLayoutTokens tokens) {
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

      WorksLoadStatus.loaded => _buildLoadedBody(context, tokens),
    };
  }

  Widget _buildLoadedBody(BuildContext context, AppLayoutTokens tokens) {
    if (controller.works.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context).noWorks));
    }

    final visibleWorks = controller.visibleWorks;

    if (visibleWorks.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context).noMatchingWorks));
    }

    return _buildWorksGrid(tokens, visibleWorks);
  }

  Widget _buildWorksGrid(
    AppLayoutTokens tokens,
    List<Map<String, Object?>> works,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = settingsController.worksPageSize == WorksPageSize.small;

        final geometry = tokens.gridGeometry(
          availableWidth: constraints.maxWidth,

          minItemWidth: isSmall
              ? tokens.workCardSmallMinWidth
              : tokens.workCardMinWidth,

          maxItemWidth: isSmall
              ? tokens.workCardSmallMaxWidth
              : tokens.workCardMaxWidth,

          itemCount: works.length,

          // Works cards should use the available width naturally. The
          // generic geometry still protects other grids with their own
          // maxUsefulColumns values, but a fixed 4/6 cap leaves artificial
          // rails on wide Works pages when there are enough items.
          maxUsefulColumns: works.length,
        );

        return Align(
          alignment: Alignment.topCenter,

          child: SizedBox(
            width: geometry.railWidth,

            height: constraints.maxHeight,

            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(
                0,

                tokens.sectionGap,

                0,

                tokens.sectionGap * 1.5,
              ),

              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: geometry.columns,

                crossAxisSpacing: tokens.gridGap,

                mainAxisSpacing: tokens.sectionGap,

                childAspectRatio: 0.54,
              ),

              itemCount: works.length,

              itemBuilder: (context, index) {
                final work = works[index];

                final workId = work['id'];

                final selected =
                    workId is int && selectedWorkIds.contains(workId);

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
            ),
          ),
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

    var saveQueue = Future<void>.value();

    Future<void> saveOptions(WorkScrapeOptions options) async {
      final save = saveQueue.then<void>(
        (_) => widget.db.setSetting('works_scrape_options', options.encode()),
      );
      saveQueue = save.catchError((_) {});

      try {
        await save;
      } catch (_) {
        // 儲存偏好失敗不應阻止關閉設定視窗或本次刮削。
      }
    }

    final options = await showDialog<WorkScrapeOptions>(
      context: context,

      builder: (context) => _ScrapeSettingsDialog(
        initial: initial,
        onOptionsChanged: saveOptions,
      ),
    );

    if (options == null || !mounted) {
      return;
    }

    await saveOptions(options);

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
      await _showScrapeResultDialog(l10n.scrapeFailed);

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

    final hasNoChanges =
        !cancelled &&
        completedResult.saved == 0 &&
        completedResult.excluded == 0 &&
        completedResult.failed == 0 &&
        completedResult.imageFailures.isEmpty;
    if (hasNoChanges) {
      message = l10n.scrapeZeroResults;
    } else if (completedResult.partialSuccess && !cancelled) {
      message = '$message ${l10n.scrapePartial}';
    }

    await _showScrapeResultDialog(message, result: completedResult);
  }

  Future<void> _showScrapeResultDialog(
    String message, {
    WorksScrapeResult? result,
  }) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: _ScrapeResultDialog(message: message, result: result),
      ),
    );
  }

  Future<WorksScrapeResult> _defaultScrapeExecutor(
    WorkScrapeOptions options,
    WorksScrapeCancellationToken token,
    void Function(WorksScrapeProgress progress) onProgress,
  ) async {
    ScrapeSourceSettings sourceSettings;
    try {
      sourceSettings = ScrapeSourceSettings.decode(
        await widget.db.getSetting(scrapeSourceSettingsKey),
      );
    } catch (_) {
      sourceSettings = const ScrapeSourceSettings();
    }

    final requestedSourceIds = <ScrapeSourceId>{
      sourceSettings.actressDetailsSource,
      ...ScrapeSourceRegistry.resolveWorksSources(sourceSettings.worksSource),
    };
    final configuredSources = <ScrapeSourceId, ScrapeSource>{};
    HttpJavBusTransport? javBusTransport;
    HttpMinnanoTransport? minnanoTransport;
    MinnanoClient? minnanoClient;
    HttpBinaryTransport? minnanoAvatarTransport;
    HttpScrapeImageUriDownloader? imageUriDownloader;

    if (requestedSourceIds.contains(ScrapeSourceId.javbus)) {
      String? initialCookies;
      try {
        initialCookies = await widget.db.getSetting('javbus_cookies');
      } catch (_) {
        initialCookies = null;
      }
      javBusTransport = HttpJavBusTransport(
        initialCookieHeader: initialCookies,
        verificationHandler: _showJavBusVerification,
      );
      configuredSources[ScrapeSourceId.javbus] = JavBusScrapeSource(
        JavBusClient(transport: javBusTransport),
      );
    }
    if (requestedSourceIds.contains(ScrapeSourceId.minnanoAv)) {
      minnanoTransport = HttpMinnanoTransport();
      minnanoClient = MinnanoClient(transport: minnanoTransport);
      configuredSources[ScrapeSourceId.minnanoAv] = MinnanoScrapeSource(
        minnanoClient,
      );
      minnanoAvatarTransport = HttpBinaryTransport(
        allowedHosts: const {'www.minnano-av.com'},
        maxBytes: 5 * 1024 * 1024,
      );
      imageUriDownloader = HttpScrapeImageUriDownloader(
        isAllowed: minnanoClient.acceptsImageUri,
        transport: HttpBinaryTransport(
          allowedHosts: const {'www.minnano-av.com'},
          maxBytes: 15 * 1024 * 1024,
        ),
      );
    }

    final detailsImageDownloader =
        sourceSettings.actressDetailsSource == ScrapeSourceId.minnanoAv
        ? HttpActressImageDownloader(transport: minnanoAvatarTransport)
        : HttpActressImageDownloader(authenticatedTransport: javBusTransport);
    final service = WorksScrapeService(
      db: widget.db,
      sources: configuredSources,
      actressImageDownloader: detailsImageDownloader,
      imageUriDownloader: imageUriDownloader,
    );

    try {
      return await service.scrape(
        actressId: widget.actressId,

        actressName: controller.actressName,

        aliases: controller.actressAliases,
        options: options,
        sourceSettings: sourceSettings,
        cancellationToken: token,
        onProgress: onProgress,
      );
    } finally {
      if (javBusTransport != null && javBusTransport.cookieHeader.isNotEmpty) {
        try {
          await widget.db.setSetting(
            'javbus_cookies',
            javBusTransport.cookieHeader,
          );
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

      builder: (context) => JavBusVerificationDialog(challenge: challenge),
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
  const _ScrapeSettingsDialog({
    required this.initial,
    required this.onOptionsChanged,
  });

  final WorkScrapeOptions initial;
  final Future<void> Function(WorkScrapeOptions options) onOptionsChanged;

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
  bool prefixesExpanded = false;
  Future<void> pendingSave = Future<void>.value();

  @override
  void initState() {
    super.initState();
    syncDetails = widget.initial.syncDetails;
    replaceImage = widget.initial.replaceActressImage;
    fillMissingOnly = widget.initial.fillMissingOnly;
    maxActressCountController.text =
        widget.initial.maxActressCount?.toString() ?? '0';
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

    _scheduleSave();
  }

  void _scheduleSave() {
    pendingSave = _saveCurrentOptions();
  }

  Future<void> _saveCurrentOptions() async {
    final options = _currentOptions();
    try {
      await widget.onOptionsChanged(options);
    } catch (_) {
      // 儲存偏好失敗不應阻止繼續編輯設定。
    }
  }

  WorkScrapeOptions _currentOptions() {
    final maxActressCount = int.tryParse(maxActressCountController.text.trim());
    return WorkScrapeOptions(
      syncDetails: syncDetails,
      replaceActressImage: replaceImage,
      fillMissingOnly: fillMissingOnly,
      maxActressCount: maxActressCount == null || maxActressCount <= 0
          ? null
          : maxActressCount,
      excludedPrefixes: List.unmodifiable(prefixes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final optionTextStyle = theme.textTheme.bodyMedium;
    final prefixInputBorder = OutlineInputBorder(
      borderRadius: const BorderRadius.all(
        Radius.circular(_scrapeSettingsDialogRadius),
      ),
      borderSide: BorderSide(color: colorScheme.outline),
    );

    return AlertDialog(
      title: Text(l10n.scrapeSettings, key: const Key('scrape-settings-title')),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(_scrapeSettingsDialogRadius),
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          key: const Key('scrape-settings-scroll'),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  key: Key('scrape-settings-gap-title'),
                  height: 8,
                ),
                SwitchListTile(
                  key: const Key('scrape-sync-details-switch'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.trailing,
                  title: Text(l10n.syncActressDetails),
                  value: syncDetails,
                  onChanged: (value) {
                    setState(() => syncDetails = value);
                  },
                ),
                const SizedBox(key: Key('scrape-settings-gap-sync'), height: 8),
                SwitchListTile(
                  key: const Key('scrape-replace-actress-image-switch'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.trailing,
                  title: Text(l10n.replaceActressImage),
                  value: replaceImage,
                  onChanged: (value) {
                    setState(() => replaceImage = value);
                  },
                ),
                const SizedBox(
                  key: Key('scrape-settings-gap-replace'),
                  height: 8,
                ),
                SwitchListTile(
                  key: const Key('scrape-fill-missing-only-switch'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.trailing,
                  title: Text(l10n.fillMissingOnly),
                  value: fillMissingOnly,
                  onChanged: (value) {
                    setState(() => fillMissingOnly = value);
                  },
                ),
                const SizedBox(key: Key('scrape-settings-gap-fill'), height: 8),
                ListTile(
                  key: const Key('scrape-max-actress-count-row'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(l10n.maxActressCountLabel),
                  trailing: SizedBox(
                    width: 48,
                    child: TextFormField(
                      key: const Key('scrape-max-actress-count-input'),
                      controller: maxActressCountController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: l10n.maxActressCountHint,
                        isDense: true,
                        contentPadding: const EdgeInsets.only(bottom: 2),
                        border: const UnderlineInputBorder(),
                        enabledBorder: const UnderlineInputBorder(),
                        focusedBorder: const UnderlineInputBorder(),
                      ),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) {
                        final cleaned = value?.trim() ?? '';
                        if (cleaned.isEmpty) {
                          return null;
                        }
                        final parsed = int.tryParse(cleaned);
                        return parsed != null && parsed >= 0
                            ? null
                            : l10n.maxActressCountInvalid;
                      },
                    ),
                  ),
                ),
                const SizedBox(key: Key('scrape-settings-gap-max'), height: 8),
                ListTile(
                  key: const Key('scrape-prefix-section'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    l10n.excludedCodePrefixes,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${prefixes.length}',
                        key: const Key('scrape-prefix-count'),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        prefixesExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        key: const Key('scrape-prefix-chevron'),
                      ),
                    ],
                  ),
                  onTap: () {
                    setState(() => prefixesExpanded = !prefixesExpanded);
                  },
                ),
                if (prefixesExpanded) ...[
                  Column(
                    key: const Key('scrape-prefix-section-content'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('scrape-prefix-input'),
                              controller: prefixController,
                              style: optionTextStyle,
                              decoration: InputDecoration(
                                hintText: l10n.codePrefixHint,
                                hintStyle: optionTextStyle?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                border: prefixInputBorder,
                                enabledBorder: prefixInputBorder,
                                focusedBorder: prefixInputBorder.copyWith(
                                  borderSide: BorderSide(
                                    color: colorScheme.primary,
                                    width: 2,
                                  ),
                                ),
                              ),
                              textCapitalization: TextCapitalization.characters,
                              onSubmitted: (_) => _addPrefix(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
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
                                  _scheduleSave();
                                },
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actions: [
        TextButton(
          onPressed: () async {
            await pendingSave;
            if (!context.mounted) {
              return;
            }
            Navigator.of(context).pop();
          },
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () async {
            if (!(formKey.currentState?.validate() ?? false)) {
              return;
            }

            await pendingSave;
            if (!context.mounted) {
              return;
            }

            Navigator.of(context).pop(_currentOptions());
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
          final l10n = AppLocalizations.of(context);
          final phase = value?.phase ?? WorksScrapePhase.collectingSources;
          final sourceProgress =
              value?.sourceProgress.entries.toList(growable: false) ??
              const <MapEntry<ScrapeSourceId, WorksScrapeSourceProgress>>[];
          final operation = [
            _scrapePhaseLabel(l10n, phase),
            if (value?.source != null) _scrapeSourceLabel(l10n, value!.source!),
            if (phase == WorksScrapePhase.downloadingImages &&
                value?.workCode != null &&
                value!.workCode!.trim().isNotEmpty)
              value.workCode!,
          ].join(' · ');
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                value: total > 0 ? current / total : null,
              ),
              const SizedBox(height: 16),
              Text(
                operation,
                key: const Key('scrape-progress-operation'),
                textAlign: TextAlign.center,
              ),
              if (total > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '$current / $total',
                  key: const Key('scrape-progress-count'),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                l10n.scrapeProgressSummary(
                  value?.saved ?? 0,
                  value?.excluded ?? 0,
                  value?.failed ?? 0,
                ),
                key: const Key('scrape-progress-summary'),
                textAlign: TextAlign.center,
              ),
              if (sourceProgress.length > 1) ...[
                const SizedBox(height: 12),
                Column(
                  key: const Key('scrape-progress-sources'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in sourceProgress)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_scrapeSourceLabel(l10n, entry.key)),
                            Text(
                              entry.value.total > 0
                                  ? entry.value.current.toString() +
                                        ' / ' +
                                        entry.value.total.toString()
                                  : _scrapePhaseLabel(l10n, entry.value.phase),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
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

class _ScrapeResultDialog extends StatelessWidget {
  const _ScrapeResultDialog({required this.message, this.result});

  final String message;
  final WorksScrapeResult? result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final failedWorks = result?.failedWorks ?? const <WorksScrapeFailure>[];
    final imageFailures =
        result?.imageFailures ?? const <WorksScrapeImageFailure>[];
    final sourceResults =
        result?.sourceResults.entries.toList(growable: false) ??
        const <MapEntry<ScrapeSourceId, ScrapeSourceRunResult>>[];
    final body = <Widget>[
      Text(message, key: const Key('scrape-result-message')),
      if (sourceResults.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(
          '來源結果',
          key: const Key('scrape-source-results-title'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final entry in sourceResults)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '• ${_scrapeSourceLabel(l10n, entry.key)} — '
              '${_scrapeSourceStateLabel(entry.value.state)}'
              '${entry.value.error == null ? '' : '：${entry.value.error}'}',
            ),
          ),
      ],
      if (failedWorks.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(
          l10n.scrapeFailedWorksTitle(failedWorks.length),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final failure in failedWorks)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '• ' +
                  failure.code +
                  ' — ' +
                  _scrapeFailureReasonLabel(l10n, failure.reason) +
                  (failure.error == null ? '' : '：' + failure.error.toString()),
            ),
          ),
      ],
      if (imageFailures.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(
          l10n.scrapeImageFailuresTitle(imageFailures.length),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final failure in imageFailures)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '• ${failure.code} — ${_scrapeImageFailureLabel(l10n, failure.variants)}',
            ),
          ),
      ],
    ];
    return AlertDialog(
      key: const Key('scrape-result-dialog'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.62,
        ),
        child: SingleChildScrollView(
          key: const Key('scrape-result-scroll'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: body,
          ),
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('scrape-result-done'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.done),
        ),
      ],
    );
  }
}

String _scrapeSourceStateLabel(ScrapeSourceRunState state) {
  return switch (state) {
    ScrapeSourceRunState.success => '成功',
    ScrapeSourceRunState.zeroResults => '完成，沒有作品',
    ScrapeSourceRunState.partial => '部分成功，另有頁面失敗',
    ScrapeSourceRunState.unavailable => '未設定',
    ScrapeSourceRunState.failed => '失敗',
    ScrapeSourceRunState.cancelled => '已取消',
    ScrapeSourceRunState.verificationRequired => '需要驗證',
    ScrapeSourceRunState.blocked => '頁面被阻擋',
    ScrapeSourceRunState.rateLimited => '被限流',
    ScrapeSourceRunState.timedOut => '逾時',
  };
}

String _scrapePhaseLabel(AppLocalizations l10n, WorksScrapePhase phase) {
  return switch (phase) {
    WorksScrapePhase.collectingSources => l10n.scrapePhaseCollecting,
    WorksScrapePhase.syncingActress => l10n.scrapePhaseSyncingActress,
    WorksScrapePhase.fetchingDetails => l10n.scrapePhaseFetchingDetails,
    WorksScrapePhase.resolvingWorks => l10n.scrapePhaseResolvingWorks,
    WorksScrapePhase.savingWorks => l10n.scrapePhaseSavingWorks,
    WorksScrapePhase.downloadingImages => l10n.scrapePhaseSavingWorks,
    WorksScrapePhase.completed => l10n.scrapePhaseCompleted,
  };
}

String _scrapeSourceLabel(AppLocalizations l10n, ScrapeSourceId source) {
  return switch (source) {
    ScrapeSourceId.javbus => l10n.scrapeSourceJavBus,
    ScrapeSourceId.minnanoAv => l10n.scrapeSourceMinnanoAv,
  };
}

String _scrapeFailureReasonLabel(
  AppLocalizations l10n,
  WorksScrapeFailureReason reason,
) {
  return switch (reason) {
    WorksScrapeFailureReason.detailsUnavailable =>
      l10n.scrapeFailureDetailsUnavailable,
    WorksScrapeFailureReason.detailCodeMismatch =>
      l10n.scrapeFailureDetailCodeMismatch,
    WorksScrapeFailureReason.invalidCode => l10n.scrapeFailureInvalidCode,
    WorksScrapeFailureReason.performerCountUnavailable =>
      l10n.scrapeFailurePerformerCountUnavailable,
    WorksScrapeFailureReason.databaseSaveFailed =>
      l10n.scrapeFailureDatabaseSave,
  };
}

String _scrapeImageFailureLabel(
  AppLocalizations l10n,
  List<WorkImageVariant> variants,
) {
  final hasCard = variants.contains(WorkImageVariant.card);
  final hasDetail = variants.contains(WorkImageVariant.detail);
  if (hasCard && hasDetail) {
    return l10n.scrapeImageFailureBoth;
  }
  if (hasCard) {
    return l10n.scrapeImageFailureCard;
  }
  return l10n.scrapeImageFailureDetail;
}
