import 'package:flutter/material.dart';

import '../controllers/works_controller.dart';
import '../core/database.dart';
import '../l10n/app_localizations.dart';

class WorksView extends StatefulWidget {
  const WorksView({super.key, required this.db, required this.actressId});

  final AppDatabase db;
  final int actressId;

  @override
  State<WorksView> createState() => _WorksViewState();
}

class _WorksViewState extends State<WorksView> {
  late final WorksController controller;
  late final Future<void> initFuture;

  @override
  void initState() {
    super.initState();
    controller = WorksController(db: widget.db, actressId: widget.actressId);
    initFuture = controller.init();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snapshot) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(_buildTitle(context)),
          ),
          body: _buildBody(context),
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
      WorksLoadStatus.loaded => const SizedBox.shrink(),
    };
  }
}
