import 'dart:async';

import 'package:flutter/material.dart';
import 'package:avaca/l10n/app_localizations.dart';

import '../controllers/software_update_controller.dart';
import '../models/software_update_models.dart';

class SoftwareUpdateView extends StatefulWidget {
  const SoftwareUpdateView({
    super.key,
    required this.controller,
    this.shrinkWrap = false,
  });

  final SoftwareUpdateController controller;
  final bool shrinkWrap;

  @override
  State<SoftwareUpdateView> createState() => _SoftwareUpdateViewState();
}

class _SoftwareUpdateViewState extends State<SoftwareUpdateView> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.currentVersion == null) {
      unawaited(widget.controller.initialize());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final localizations = AppLocalizations.of(context);
        final controller = widget.controller;
        final current = controller.currentVersion?.version ?? '—';
        final latest = controller.latestRelease?.version.toString() ?? '—';

        return ListView(
          key: const PageStorageKey('software-update-settings-scroll'),
          padding: EdgeInsets.zero,
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : null,
          children: [
            Text(
              localizations.softwareUpdateDescription,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _VersionRow(label: localizations.currentVersion, value: current),
            const SizedBox(height: 8),
            _VersionRow(label: localizations.latestVersion, value: latest),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(localizations.autoCheckUpdates),
              value: controller.autoCheckUpdates,
              onChanged: controller.isBusy
                  ? null
                  : controller.setAutoCheckUpdates,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('software-update-check'),
                onPressed: controller.isBusy ? null : _checkForUpdates,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(localizations.checkForUpdates),
              ),
            ),
            if (controller.status == UpdateStatus.checking ||
                controller.status == UpdateStatus.downloading ||
                controller.status == UpdateStatus.verifying ||
                controller.status == UpdateStatus.handingOff) ...[
              const SizedBox(height: 12),
              _StatusMessage(controller: controller),
            ],
            if (controller.status == UpdateStatus.failed ||
                controller.status == UpdateStatus.unavailable ||
                controller.status == UpdateStatus.notSupported) ...[
              const SizedBox(height: 12),
              _StatusMessage(controller: controller),
            ],
          ],
        );
      },
    );
  }

  Future<void> _checkForUpdates() async {
    final result = await widget.controller.check();
    if (!mounted) return;
    await showSoftwareUpdateDialog(context, widget.controller, result);
  }
}

Future<void> showSoftwareUpdateDialog(
  BuildContext context,
  SoftwareUpdateController controller,
  SoftwareUpdateResult result, {
  bool automatic = false,
}) async {
  final localizations = AppLocalizations.of(context);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final canUpdate = result.hasUpdate && result.asset != null;
      return AlertDialog(
        title: Text(_dialogTitle(localizations, result.status)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result.release != null) ...[
              Text(
                '${localizations.currentVersion}: '
                '${result.current.version}',
              ),
              const SizedBox(height: 4),
              Text(
                '${localizations.latestVersion}: '
                '${result.release!.version}',
              ),
              const SizedBox(height: 8),
            ],
            Text(_dialogMessage(localizations, result)),
            if (canUpdate) ...[
              const SizedBox(height: 8),
              Text(
                localizations.updateDataPreserved,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(localizations.updateLater),
          ),
          if (canUpdate)
            FilledButton(
              key: const ValueKey('software-update-now'),
              onPressed: () async {
                Navigator.pop(dialogContext);
                final installResult = await controller.update();
                if (!context.mounted || installResult?.started == true) return;
                await _showInstallFailure(
                  context,
                  controller,
                  installResult?.requiresUserAction == true,
                );
              },
              child: Text(localizations.updateNow),
            ),
        ],
      );
    },
  );
}

String _dialogTitle(AppLocalizations localizations, UpdateStatus status) {
  return switch (status) {
    UpdateStatus.updateAvailable => localizations.updateAvailable,
    UpdateStatus.upToDate => localizations.upToDate,
    UpdateStatus.unavailable => localizations.updateUnavailable,
    UpdateStatus.notSupported => localizations.updateNotSupported,
    _ => localizations.updateCheckFailed,
  };
}

String _dialogMessage(
  AppLocalizations localizations,
  SoftwareUpdateResult result,
) {
  return switch (result.status) {
    UpdateStatus.updateAvailable => localizations.updateAvailable,
    UpdateStatus.upToDate => localizations.upToDate,
    UpdateStatus.unavailable => localizations.updateUnavailable,
    UpdateStatus.notSupported => localizations.updateNotSupported,
    _ => switch (result.error?.reason) {
      UpdateFailureReason.integrity => localizations.updateIntegrityFailed,
      UpdateFailureReason.assetUnavailable => localizations.updateUnavailable,
      UpdateFailureReason.notSupported => localizations.updateNotSupported,
      _ => localizations.updateCheckFailed,
    },
  };
}

Future<void> _showInstallFailure(
  BuildContext context,
  SoftwareUpdateController controller,
  bool requiresUserAction,
) {
  final localizations = AppLocalizations.of(context);
  final message = requiresUserAction
      ? localizations.updateInstallPermissionRequired
      : localizations.updateInstallerFailed;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(localizations.updateCheckFailed),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(localizations.updateLater),
        ),
      ],
    ),
  );
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.controller});

  final SoftwareUpdateController controller;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final message = switch (controller.status) {
      UpdateStatus.downloading => localizations.downloadingUpdate,
      UpdateStatus.checking => localizations.checkingForUpdates,
      UpdateStatus.verifying => localizations.verifyingUpdate,
      UpdateStatus.handingOff => localizations.installingUpdate,
      UpdateStatus.unavailable => localizations.updateUnavailable,
      UpdateStatus.notSupported => localizations.updateNotSupported,
      _ => localizations.updateCheckFailed,
    };
    final progress = controller.downloadProgress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        if (progress != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress.clamp(0, 1)),
        ],
      ],
    );
  }
}
