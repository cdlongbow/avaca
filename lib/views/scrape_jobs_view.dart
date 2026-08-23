import 'dart:async';

import 'package:flutter/material.dart';

import '../components/adaptive_page_layout.dart';
import '../components/aligned_app_bar_back_button.dart';
import '../core/database.dart';
import '../core/layout.dart';
import '../l10n/app_localizations.dart';
import '../models/scrape_job.dart';
import '../services/scrape_job_coordinator.dart';
import 'scrape_job_detail_view.dart';

class ScrapeJobsView extends StatefulWidget {
  const ScrapeJobsView({
    super.key,
    required this.db,
    required this.coordinator,
  });

  final AppDatabase db;
  final ScrapeJobCoordinator coordinator;

  @override
  State<ScrapeJobsView> createState() => _ScrapeJobsViewState();
}

class _ScrapeJobsViewState extends State<ScrapeJobsView> {
  List<ScrapeJob> _jobs = const <ScrapeJob>[];
  Object? _loadError;
  bool _loading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _loadGeneration++;
    widget.coordinator.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    if (_jobs.isEmpty && !_loading) {
      setState(() => _loading = true);
    }
    unawaited(_loadLatest(generation));
  }

  Future<void> _loadLatest(int generation) async {
    try {
      final jobs = await widget.coordinator.listJobs();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
        _loadError = null;
      });
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const AlignedAppBarBackButton(),
        title: Text(l10n.scrapeJobsTitle),
      ),
      body: AdaptivePageLayout(
        compactBuilder: (context, tokens) => _buildBody(context, tokens),
        expandedBuilder: (context, tokens) => _buildBody(context, tokens),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLayoutTokens tokens) {
    if (_loading && _jobs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_jobs.isEmpty) {
      return Center(
        child: Text(
          _loadError == null
              ? AppLocalizations.of(context).scrapeJobsEmpty
              : _loadError.toString(),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(bottom: tokens.sectionGap * 2),
      itemCount: _jobs.length,
      separatorBuilder: (_, _) => SizedBox(height: tokens.sectionGap),
      itemBuilder: (context, index) {
        final job = _jobs[index];
        final l10n = AppLocalizations.of(context);
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: _stateIcon(job.state),
            title: Text(job.actressNameSnapshot),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_stateLabel(context, job.state)} · '
                  '${l10n.scrapeJobProgress(job.processedCount, job.savedCount, job.failedCount)}',
                ),
                if (job.lastError != null)
                  Text(
                    job.lastError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => ScrapeJobDetailView(
                  db: widget.db,
                  coordinator: widget.coordinator,
                  jobId: job.id,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Icon _stateIcon(ScrapeJobState state) {
    return Icon(switch (state) {
      ScrapeJobState.succeeded => Icons.check_circle_outline,
      ScrapeJobState.partial => Icons.warning_amber_outlined,
      ScrapeJobState.failed => Icons.error_outline,
      ScrapeJobState.cancelled => Icons.cancel_outlined,
      ScrapeJobState.paused => Icons.pause_circle_outline,
      ScrapeJobState.waitingForVerification => Icons.verified_user_outlined,
      _ => Icons.sync_outlined,
    });
  }

  String _stateLabel(BuildContext context, ScrapeJobState state) {
    final l10n = AppLocalizations.of(context);
    return switch (state) {
      ScrapeJobState.queued => l10n.scrapeJobStateQueued,
      ScrapeJobState.running => l10n.scrapeJobStateRunning,
      ScrapeJobState.paused => l10n.scrapeJobStatePaused,
      ScrapeJobState.waitingForVerification => l10n.scrapeJobStateWaiting,
      ScrapeJobState.succeeded => l10n.scrapeJobStateSucceeded,
      ScrapeJobState.partial => l10n.scrapeJobStatePartial,
      ScrapeJobState.failed => l10n.scrapeJobStateFailed,
      ScrapeJobState.cancelled => l10n.scrapeJobStateCancelled,
    };
  }
}
