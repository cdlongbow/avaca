import 'dart:io';

import 'package:flutter/material.dart';

import '../components/aligned_app_bar_back_button.dart';
import '../components/adaptive_page_layout.dart';
import '../core/database.dart';
import '../core/layout.dart';
import '../l10n/app_localizations.dart';

class WorkDetailView extends StatefulWidget {
  const WorkDetailView({
    super.key,
    required this.db,
    required this.workId,
    this.currentActressId,
  });

  final AppDatabase db;
  final int workId;
  final int? currentActressId;

  @override
  State<WorkDetailView> createState() => _WorkDetailViewState();
}

class _WorkDetailViewState extends State<WorkDetailView> {
  late final Future<Map<String, Object?>?> workFuture;

  @override
  void initState() {
    super.initState();
    workFuture = widget.db.getWorkById(
      widget.workId,
      currentActressId: widget.currentActressId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Object?>?>(
      future: workFuture,
      builder: (context, snapshot) {
        final work = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            leading: Navigator.canPop(context)
                ? const AlignedAppBarBackButton()
                : null,
            title: Text(work?['code']?.toString() ?? ''),
          ),
          body: switch (snapshot.connectionState) {
            ConnectionState.waiting => const Center(
              child: CircularProgressIndicator(),
            ),
            _ when snapshot.hasError => Center(
              child: Text(AppLocalizations.of(context).loadFailedGeneric),
            ),
            _ when work == null => Center(
              child: Text(AppLocalizations.of(context).dataNotFound),
            ),
            _ => _buildContent(work),
          },
        );
      },
    );
  }

  Widget _buildContent(Map<String, Object?> work) {
    return AdaptivePageLayout(
      padding: EdgeInsets.zero,
      compactBuilder: (context, tokens) => _buildCompactContent(work, tokens),
      expandedBuilder: (context, tokens) => _buildExpandedContent(work, tokens),
    );
  }

  Widget _buildCompactContent(
    Map<String, Object?> work,
    AppLayoutTokens tokens,
  ) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        tokens.pagePadding.left,
        tokens.pagePadding.top,
        tokens.pagePadding.right,
        tokens.pagePadding.bottom * 2,
      ),
      children: [
        _buildMedia(work['detail_image_path']?.toString() ?? ''),
        SizedBox(height: tokens.sectionGap),
        _buildMetadata(work, tokens),
      ],
    );
  }

  Widget _buildExpandedContent(
    Map<String, Object?> work,
    AppLayoutTokens tokens,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final splitRequired =
            360 +
            tokens.contentColumnGap +
            tokens.detailPaneMinWidth * textScale;
        if (constraints.maxWidth < splitRequired) {
          return _buildCompactContent(work, tokens);
        }

        final mediaWidth = (constraints.maxWidth * 0.45)
            .clamp(360.0, 520.0)
            .toDouble();
        return SingleChildScrollView(
          padding: EdgeInsets.all(tokens.pagePadding.left),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: mediaWidth,
                child: _buildMedia(work['detail_image_path']?.toString() ?? ''),
              ),
              SizedBox(width: tokens.contentColumnGap),
              Expanded(child: _buildMetadata(work, tokens)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMedia(String imagePath) {
    return ClipRRect(
      key: const Key('work-detail-image'),
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(aspectRatio: 1.48, child: _detailImage(imagePath)),
    );
  }

  Widget _buildMetadata(Map<String, Object?> work, AppLayoutTokens tokens) {
    final l10n = AppLocalizations.of(context);
    final title = work['title']?.toString() ?? '';
    final duration = work['duration_minutes'];
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.cardRadius),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.cardRadius + 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: tokens.sectionGap / 2),
            _value(work['code']?.toString()),
            _value(work['release_date']?.toString()),
            if (duration is int) _value(l10n.durationMinutes(duration)),
            _labeledValue(l10n.studio, work['studio']?.toString()),
            _labeledValue(l10n.publisher, work['publisher']?.toString()),
            _labeledValue(l10n.series, work['series']?.toString()),
            _buildRelatedActresses(work),
          ],
        ),
      ),
    );
  }

  Widget _buildRelatedActresses(Map<String, Object?> work) {
    final raw = work['related_performers'];
    if (raw is! List) {
      return const SizedBox.shrink();
    }
    final performers = raw
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .where((performer) {
          final actressId = performer['actress_id'];
          return widget.currentActressId == null ||
              actressId != widget.currentActressId;
        })
        .toList(growable: false);
    if (performers.isEmpty ||
        (widget.currentActressId == null && performers.length < 2)) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    return Padding(
      key: const Key('related-actresses-section'),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.relatedActresses),
          const SizedBox(height: 4),
          for (final performer in performers) _relatedActressTile(performer),
        ],
      ),
    );
  }

  Widget _relatedActressTile(Map<String, Object?> performer) {
    final name = performer['name']?.toString().trim() ?? '';
    final actressId = performer['actress_id'];
    if (name.isEmpty) {
      return const SizedBox.shrink();
    }
    if (actressId is int) {
      return ListTile(
        key: ValueKey('related-actress-$actressId'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(name),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed('/detail/$actressId'),
      );
    }
    return ListTile(
      key: ValueKey('related-actress-$name'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(name),
    );
  }

  Widget _detailImage(String path) {
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          color: colorScheme.onSurfaceVariant,
          size: 48,
        ),
      ),
    );
  }

  Widget _value(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(value),
    );
  }

  Widget _labeledValue(String label, String? value) {
    if (value == null || value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label：$value'),
    );
  }
}
