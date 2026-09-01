import 'dart:io';

import 'package:flutter/material.dart';

import '../components/adaptive_page_layout.dart';
import '../components/aligned_app_bar_back_button.dart';
import '../components/app_snackbar.dart';
import '../controllers/works_controller.dart';
import '../core/database.dart';
import '../core/layout.dart';
import '../library/library_collection_service.dart';
import '../l10n/app_localizations.dart';
import '../models/work_storage.dart';
import '../controllers/settings_controller.dart';
import 'work_detail_view.dart';

enum _WorksMenuAction { search, filterStored, filterNotStored, filterAll }

class WorksView extends StatefulWidget {
  const WorksView({
    super.key,
    required this.db,
    required this.actressId,
    this.collectionService,
  });

  final AppDatabase db;
  final int actressId;
  final LibraryCollectionService? collectionService;

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

    controller = WorksController(
      db: widget.db,
      actressId: widget.actressId,
      collectionService: widget.collectionService,
    );

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
    if (widget.collectionService != null || deletionBusy) {
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
    if (widget.collectionService != null ||
        deletionBusy ||
        selectedWorkIds.isEmpty) {
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
    if (widget.collectionService != null ||
        deletionBusy ||
        selectedWorkIds.isEmpty) {
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
                if (widget.collectionService == null && isSelecting)
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
          case _WorksMenuAction.filterStored:
            controller.changeStorageFilter(WorkStorageFilter.stored);
          case _WorksMenuAction.filterNotStored:
            controller.changeStorageFilter(WorkStorageFilter.notStored);
          case _WorksMenuAction.filterAll:
            controller.changeStorageFilter(WorkStorageFilter.all);
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
        if (widget.collectionService == null) ...[
          const PopupMenuDivider(),
          PopupMenuItem<_WorksMenuAction>(
            key: const Key('works-filter-stored-menu-item'),
            value: _WorksMenuAction.filterStored,
            enabled: enabled,
            child: _buildStorageFilterMenuRow(
              l10n.workStorageFilterStored,
              WorkStorageFilter.stored,
              Icons.bookmark,
            ),
          ),
          PopupMenuItem<_WorksMenuAction>(
            key: const Key('works-filter-not-stored-menu-item'),
            value: _WorksMenuAction.filterNotStored,
            enabled: enabled,
            child: _buildStorageFilterMenuRow(
              l10n.workStorageFilterNotStored,
              WorkStorageFilter.notStored,
              Icons.bookmark_border,
            ),
          ),
          PopupMenuItem<_WorksMenuAction>(
            key: const Key('works-filter-all-menu-item'),
            value: _WorksMenuAction.filterAll,
            enabled: enabled,
            child: _buildStorageFilterMenuRow(
              l10n.workStorageFilterAll,
              WorkStorageFilter.all,
              Icons.video_library_outlined,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStorageFilterMenuRow(
    String label,
    WorkStorageFilter filter,
    IconData icon,
  ) {
    final selected = controller.storageFilter == filter;
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        if (selected) const Icon(Icons.check, size: 18),
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

                    onLongPress: widget.collectionService == null
                        ? () => _toggleSelection(work)
                        : null,
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
        builder: (context) => WorkDetailView(
          db: widget.db,
          workId: workId,
          currentActressId: widget.actressId,
          collectionService: widget.collectionService,
        ),
      ),
    );

    if (mounted) {
      await controller.reloadWorks();
    }
  }
}

class _WorkCard extends StatelessWidget {
  const _WorkCard({
    super.key,
    required this.work,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final Map<String, Object?> work;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

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
