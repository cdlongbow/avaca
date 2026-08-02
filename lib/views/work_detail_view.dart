import 'dart:io';

import 'package:flutter/material.dart';

import '../core/database.dart';
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
    final l10n = AppLocalizations.of(context);
    final title = work['title']?.toString() ?? '';
    final imagePath = work['detail_image_path']?.toString() ?? '';
    final duration = work['duration_minutes'];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        ClipRRect(
          key: const Key('work-detail-image'),
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(aspectRatio: 1.48, child: _detailImage(imagePath)),
        ),
        const SizedBox(height: 20),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _value(work['code']?.toString()),
        _value(work['release_date']?.toString()),
        if (duration is int) _value(l10n.durationMinutes(duration)),
        _labeledValue(l10n.studio, work['studio']?.toString()),
        _labeledValue(l10n.publisher, work['publisher']?.toString()),
        _labeledValue(l10n.series, work['series']?.toString()),
      ],
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
