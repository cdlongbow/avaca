import 'dart:io';

import 'package:flutter/material.dart';

import '../components/adaptive_page_layout.dart';
import '../core/database.dart';
import '../core/layout.dart';
import '../l10n/app_localizations.dart';

class WorkDetailView extends StatefulWidget {
  const WorkDetailView({super.key, required this.db, required this.workId});

  final AppDatabase db;
  final int workId;

  @override
  State<WorkDetailView> createState() => _WorkDetailViewState();
}

class _WorkDetailViewState extends State<WorkDetailView> {
  late final Future<Map<String, Object?>?> workFuture;

  @override
  void initState() {
    super.initState();
    workFuture = widget.db.getWorkById(widget.workId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Object?>?>(
      future: workFuture,
      builder: (context, snapshot) {
        final work = snapshot.data;
        return Scaffold(
          appBar: AppBar(title: Text(work?['code']?.toString() ?? '')),
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
          ],
        ),
      ),
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
