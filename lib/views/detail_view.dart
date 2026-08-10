import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:avaca/l10n/app_localizations.dart';
import '../components/adaptive_page_layout.dart';
import '../components/app_snackbar.dart';
import '../controllers/detail_controller.dart';
import '../core/database.dart';
import '../core/layout.dart';

const double _detailControlRadius = 6.0;

enum _DetailMenuAction { edit, delete }

enum _DetailLayoutMode { compact, intermediate, wide }

ButtonStyle _detailOutlinedButtonStyle({Color? foregroundColor}) {
  return OutlinedButton.styleFrom(
    foregroundColor: foregroundColor,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_detailControlRadius),
    ),
  );
}

class DetailView extends StatefulWidget {
  const DetailView({super.key, required this.db, required this.actressId});

  final AppDatabase db;
  final int actressId;

  @override
  State<DetailView> createState() => _DetailViewState();
}

class _BirthDatePickerResult {
  const _BirthDatePickerResult({this.date, this.clear = false});

  final DateTime? date;
  final bool clear;
}

class _BirthDatePickerSheet extends StatefulWidget {
  const _BirthDatePickerSheet({required this.initialDate});

  final DateTime? initialDate;

  @override
  State<_BirthDatePickerSheet> createState() => _BirthDatePickerSheetState();
}

class _BirthDatePickerSheetState extends State<_BirthDatePickerSheet> {
  static const double _itemExtent = 48;
  static const int _firstYear = 1900;

  late final DateTime _today;
  late int _year;
  late int _month;
  late int _day;
  late final FixedExtentScrollController _yearController;
  late final FixedExtentScrollController _monthController;
  late final FixedExtentScrollController _dayController;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    final initial = widget.initialDate == null
        ? DateTime(_today.year - 20, _today.month, _today.day)
        : _clampToToday(widget.initialDate!);
    _year = initial.year.clamp(_firstYear, _today.year).toInt();
    _month = initial.month;
    _day = initial.day;
    _clampParts();
    _yearController = FixedExtentScrollController(
      initialItem: _today.year - _year,
    );
    _monthController = FixedExtentScrollController(initialItem: _month - 1);
    _dayController = FixedExtentScrollController(initialItem: _day - 1);
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    super.dispose();
  }

  DateTime _clampToToday(DateTime value) {
    final normalized = DateTime(value.year, value.month, value.day);
    return normalized.isAfter(_today) ? _today : normalized;
  }

  int get _maxMonth => _year == _today.year ? _today.month : 12;

  int get _maxDay {
    final monthDays = DateTime(_year, _month + 1, 0).day;
    if (_year == _today.year && _month == _today.month) {
      return monthDays < _today.day ? monthDays : _today.day;
    }
    return monthDays;
  }

  void _clampParts() {
    if (_month > _maxMonth) _month = _maxMonth;
    if (_day > _maxDay) _day = _maxDay;
  }

  void _syncControllers() {
    if (_monthController.hasClients &&
        _monthController.selectedItem != _month - 1) {
      _monthController.jumpToItem(_month - 1);
    }
    if (_dayController.hasClients && _dayController.selectedItem != _day - 1) {
      _dayController.jumpToItem(_day - 1);
    }
  }

  void _changeYear(int index) {
    setState(() {
      _year = _today.year - index;
      _clampParts();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncControllers());
  }

  void _changeMonth(int index) {
    setState(() {
      _month = index + 1;
      _clampParts();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncControllers());
  }

  void _changeDay(int index) {
    setState(() {
      _day = index + 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final overlay = Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(_detailControlRadius),
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.birthDate,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoPicker(
                      key: const Key('birth-date-year-picker'),
                      scrollController: _yearController,
                      itemExtent: _itemExtent,
                      useMagnifier: true,
                      magnification: 1.08,
                      selectionOverlay: overlay,
                      onSelectedItemChanged: _changeYear,
                      children: List.generate(
                        _today.year - _firstYear + 1,
                        (index) =>
                            Center(child: Text('${_today.year - index}')),
                      ),
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      key: const Key('birth-date-month-picker'),
                      scrollController: _monthController,
                      itemExtent: _itemExtent,
                      useMagnifier: true,
                      magnification: 1.08,
                      selectionOverlay: overlay,
                      onSelectedItemChanged: _changeMonth,
                      children: List.generate(
                        _maxMonth,
                        (index) => Center(child: Text('${index + 1}')),
                      ),
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      key: const Key('birth-date-day-picker'),
                      scrollController: _dayController,
                      itemExtent: _itemExtent,
                      useMagnifier: true,
                      magnification: 1.08,
                      selectionOverlay: overlay,
                      onSelectedItemChanged: _changeDay,
                      children: List.generate(
                        _maxDay,
                        (index) => Center(child: Text('${index + 1}')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(const _BirthDatePickerResult(clear: true)),
                  child: Text(l10n.clear),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    _BirthDatePickerResult(date: DateTime(_year, _month, _day)),
                  ),
                  child: Text(l10n.done),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailViewState extends State<DetailView> {
  late final DetailController controller;
  late final Future<void> initFuture;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController heightController = TextEditingController();
  final TextEditingController weightController = TextEditingController();
  final TextEditingController cupController = TextEditingController();
  final TextEditingController bwhController = TextEditingController();
  final TextEditingController memoController = TextEditingController();
  DateTime? birthDate;

  final Set<String> selectedAttrs = <String>{};

  @override
  void initState() {
    super.initState();

    controller = DetailController(db: widget.db, actressId: widget.actressId);
    controller.addListener(_handleControllerChanged);

    initFuture = _initialize();
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);

    nameController.dispose();
    heightController.dispose();
    weightController.dispose();
    cupController.dispose();
    bwhController.dispose();
    memoController.dispose();

    super.dispose();
  }

  Future<void> _initialize() async {
    await controller.init();
    _syncFieldsFromController();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _syncFieldsFromController() {
    final data = controller.actressData;

    nameController.text = data['name']?.toString() ?? '';
    heightController.text = data['height']?.toString() ?? '';
    weightController.text = data['weight']?.toString() ?? '';
    cupController.text = data['cup']?.toString() ?? '';
    bwhController.text = data['bwh']?.toString() ?? '';
    memoController.text = data['memo']?.toString() ?? '';
    birthDate = _parseBirthDate(data['birth_date']?.toString());

    selectedAttrs
      ..clear()
      ..addAll(controller.currentAttrs);
  }

  Future<void> _toggleEditMode() async {
    final editState = await controller.toggleEditMode(context, _getFormData());

    selectedAttrs
      ..clear()
      ..addAll(
        (editState['current_attrs'] as List<dynamic>? ?? []).map(
          (e) => e.toString(),
        ),
      );

    if (!controller.isEditing) {
      _syncFieldsFromController();
    }
  }

  void _cancelEditMode() {
    _dismissKeyboard();
    controller.cancelEditMode();
    _syncFieldsFromController();
  }

  Map<String, Object?> _getFormData() {
    return {
      'name': nameController.text,
      'img_path': controller.actressData['img_path']?.toString() ?? '',
      'main_type': selectedAttrs.join(','),
      'selected_attrs': selectedAttrs.toList(),
      'memo': memoController.text,
      'height': heightController.text,
      'weight': weightController.text,
      'bwh': bwhController.text,
      'cup': cupController.text,
      'birth_date': birthDate == null ? null : _toIsoDate(birthDate!),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return PopScope<void>(
          canPop: !controller.isEditing,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && controller.isEditing) {
              _cancelEditMode();
            }
          },
          child: Scaffold(
            backgroundColor: colorScheme.surface,
            appBar: AppBar(
              centerTitle: true,
              backgroundColor: colorScheme.surfaceContainerHighest,
              leading: controller.isEditing
                  ? IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _cancelEditMode,
                    )
                  : null,
              title: _buildAppBarTitle(),
              actions: controller.isEditing
                  ? [
                      IconButton(
                        key: const Key('detail-save-button'),
                        icon: const Icon(Icons.save),
                        onPressed: _toggleEditMode,
                      ),
                    ]
                  : [_buildOverflowMenu()],
            ),
            body: SafeArea(
              child: AdaptivePageLayout(
                padding: EdgeInsets.zero,
                compactBuilder: (context, tokens) =>
                    _buildDetailContent(tokens),
                expandedBuilder: (context, tokens) =>
                    _buildDetailContent(tokens),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailContent(AppLayoutTokens tokens) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final mode = tokens.canUseWideDetail(constraints.maxWidth, textScale)
            ? _DetailLayoutMode.wide
            : tokens.canUseIntermediateDetail(constraints.maxWidth, textScale)
            ? _DetailLayoutMode.intermediate
            : _DetailLayoutMode.compact;

        final content = switch (mode) {
          _DetailLayoutMode.compact || _DetailLayoutMode.intermediate => Column(
            children: [
              _buildProfilePanel(tokens),
              SizedBox(height: tokens.sectionGap),
              _buildInfoPanel(tokens),
            ],
          ),
          _DetailLayoutMode.wide => Column(
            children: [
              _buildWideDetailRow(tokens),
              SizedBox(height: tokens.sectionGap),
              _buildNotesPanel(tokens),
            ],
          ),
        };

        return SingleChildScrollView(
          padding: tokens.pagePadding,
          child: content,
        );
      },
    );
  }

  Widget _buildWideDetailRow(AppLayoutTokens tokens) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final gap = tokens.contentColumnGap;
        final leftWidth = tokens.detailImageMaxSize;
        final remaining = constraints.maxWidth - leftWidth - gap * 2;
        final middleMin = tokens.detailMiddleMinWidth * textScale;
        final middleWidth = math.max(middleMin, remaining / 2);
        final bodyWidth = remaining - middleWidth;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: leftWidth,
              child: _buildWideProfileVisual(leftWidth),
            ),
            SizedBox(width: gap),
            SizedBox(width: middleWidth, child: _buildMetadataPanel(tokens)),
            SizedBox(width: gap),
            SizedBox(width: bodyWidth, child: _buildBodyPanel(tokens)),
          ],
        );
      },
    );
  }

  Widget _buildWideProfileVisual(double imageSize) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = controller.actressData['name']?.toString() ?? '';

    return Container(
      key: const Key('detail-profile-panel'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildProfileImage(imageSize - 24),
          if (name.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetadataPanel(AppLayoutTokens tokens) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEditing = controller.isEditing;
    final actionButtonStyle = _detailOutlinedButtonStyle(
      foregroundColor: colorScheme.onSurface,
    );

    return Container(
      key: const Key('detail-metadata-panel'),
      padding: EdgeInsets.all(tokens.cardRadius),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('detail-works-button'),
                  onPressed: _openWorks,
                  style: actionButtonStyle,
                  child: Text(AppLocalizations.of(context).works),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${controller.workCount}',
                key: const Key('detail-works-count'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('detail-aliases-button'),
            onPressed: _openAliases,
            style: actionButtonStyle,
            child: Text(AppLocalizations.of(context).aliases),
          ),
          const SizedBox(height: 12),
          KeyedSubtree(
            key: const Key('detail-attributes'),
            child: isEditing ? _buildAttrEditRow() : _buildAttrViewRow(),
          ),
          if (isEditing) ...[const SizedBox(height: 12), _buildPhotoEditRow()],
        ],
      ),
    );
  }

  Widget _buildOverflowMenu() {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<_DetailMenuAction>(
      key: const Key('detail-overflow-menu'),
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        switch (action) {
          case _DetailMenuAction.edit:
            _toggleEditMode();
          case _DetailMenuAction.delete:
            _openDeleteDialog();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_DetailMenuAction>(
          key: const Key('detail-edit-menu-item'),
          value: _DetailMenuAction.edit,
          child: Row(
            children: [
              const Icon(Icons.edit),
              const SizedBox(width: 12),
              Text(l10n.edit),
            ],
          ),
        ),
        PopupMenuItem<_DetailMenuAction>(
          key: const Key('detail-delete-menu-item'),
          value: _DetailMenuAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete_forever, color: colorScheme.error),
              const SizedBox(width: 12),
              Text(
                l10n.delete,
                key: const Key('detail-delete-menu-label'),
                style: TextStyle(color: colorScheme.error),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAppBarTitle() {
    if (controller.isEditing) {
      return TextField(
        key: const Key('detail-name-field'),
        controller: nameController,
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          border: OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      );
    }

    return Text(
      controller.actressData['name']?.toString() ??
          AppLocalizations.of(context).dataNotFound,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
    );
  }

  // 顯示個人照片、照片操作與屬性內容。
  Widget _buildProfilePanel(AppLayoutTokens tokens) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEditing = controller.isEditing;
    final actionButtonStyle = _detailOutlinedButtonStyle(
      foregroundColor: colorScheme.onSurface,
    );

    return Container(
      key: const Key('detail-profile-panel'),
      padding: isEditing ? EdgeInsets.all(tokens.cardRadius) : EdgeInsets.zero,
      decoration: isEditing
          ? BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(tokens.cardRadius),
            )
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalGap = isEditing && tokens.isCompact
              ? 12.0
              : tokens.contentColumnGap;
          final availableWidth = constraints.maxWidth - horizontalGap;
          final imageSize = isEditing
              ? (availableWidth * 5 / 12).clamp(0.0, tokens.detailImageMaxSize)
              : (availableWidth / 2).clamp(0.0, tokens.detailImageMaxSize);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: imageSize, child: _buildProfileImage(imageSize)),
              SizedBox(width: horizontalGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 96,
                          child: OutlinedButton(
                            key: const Key('detail-works-button'),
                            onPressed: _openWorks,
                            style: actionButtonStyle,
                            child: Text(AppLocalizations.of(context).works),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${controller.workCount}',
                            key: const Key('detail-works-count'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: const Key('detail-aliases-button'),
                        onPressed: _openAliases,
                        style: actionButtonStyle,
                        child: Text(AppLocalizations.of(context).aliases),
                      ),
                    ),
                    const SizedBox(height: 12),
                    KeyedSubtree(
                      key: const Key('detail-attributes'),
                      child: isEditing
                          ? _buildAttrEditRow()
                          : _buildAttrViewRow(),
                    ),
                    if (isEditing) ...[
                      const SizedBox(height: 12),
                      _buildPhotoEditRow(),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProfileImage(double imageSize) {
    final imgPath = controller.actressData['img_path']?.toString() ?? '';
    final colorScheme = Theme.of(context).colorScheme;

    if (imgPath.isEmpty) {
      return Container(
        key: const Key('detail-profile-image'),
        width: imageSize,
        height: imageSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          Icons.person,
          size: 80,
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return ClipRRect(
      key: const Key('detail-profile-image'),
      borderRadius: BorderRadius.circular(20),
      child: Image.file(
        File(imgPath),
        width: imageSize,
        height: imageSize,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildPhotoEditRow() {
    final colorScheme = Theme.of(context).colorScheme;
    final actionTextStyle = Theme.of(
      context,
    ).textTheme.labelMedium!.copyWith(fontSize: 12);
    final changeStyle = OutlinedButton.styleFrom(
      foregroundColor: colorScheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: actionTextStyle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_detailControlRadius),
      ),
    );
    final deleteStyle = OutlinedButton.styleFrom(
      foregroundColor: colorScheme.error,
      side: BorderSide(color: colorScheme.error),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: actionTextStyle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_detailControlRadius),
      ),
    );

    return Row(
      key: const Key('detail-photo-actions'),
      children: [
        Expanded(
          child: SizedBox(
            height: 34,
            child: OutlinedButton(
              key: const Key('detail-change-photo-button'),
              onPressed: () {
                _dismissKeyboard();
                controller.changePhoto(context);
              },
              style: changeStyle,
              child: Text(AppLocalizations.of(context).changePhoto),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: SizedBox(
            height: 34,
            child: OutlinedButton(
              key: const Key('detail-delete-photo-button'),
              onPressed: controller.deletePhoto,
              style: deleteStyle,
              child: Text(AppLocalizations.of(context).deletePhoto),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttrViewRow() {
    final colorScheme = Theme.of(context).colorScheme;

    if (controller.currentAttrs.isEmpty) {
      return Text(
        AppLocalizations.of(context).noAttributesSet,
        style: TextStyle(fontSize: 13, color: colorScheme.outline),
      );
    }

    return Wrap(
      alignment: WrapAlignment.start,
      spacing: 14,
      runSpacing: 6,
      children: controller.currentAttrs.map((attr) {
        return Text(
          attr,
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAttrEditRow() {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      alignment: WrapAlignment.start,
      spacing: 4,
      runSpacing: 4,
      children: controller.getAttrOptions(context).map((option) {
        final selected = selectedAttrs.contains(option);

        return FilterChip(
          label: Text(
            option,
            style: TextStyle(
              fontSize: 14,
              color: selected
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: const VisualDensity(horizontal: -2, vertical: -4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          selected: selected,
          showCheckmark: false,
          selectedColor: colorScheme.primary.withValues(alpha: 0.28),
          onSelected: (selected) {
            setState(() {
              selected
                  ? selectedAttrs.add(option)
                  : selectedAttrs.remove(option);
            });
          },
        );
      }).toList(),
    );
  }

  Future<void> _openWorks() async {
    _dismissKeyboard();
    await Navigator.of(context).pushNamed('/works/${widget.actressId}');
    if (mounted) {
      await controller.refreshWorkCount();
    }
  }

  Future<void> _openAliases() async {
    _dismissKeyboard();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _AliasesDialog(
        initialAliases: controller.getCurrentAliases(),
        onSave: (aliases) => controller.saveAliases(aliases),
      ),
    );
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  // 顯示身體資料與私人筆記。
  Widget _buildInfoPanel(AppLayoutTokens tokens) {
    return Column(
      children: [
        _buildBodyPanel(tokens),
        SizedBox(height: tokens.sectionGap),
        _buildNotesPanel(tokens),
      ],
    );
  }

  Widget _buildBodyPanel(AppLayoutTokens tokens) {
    return _buildCard(
      title: AppLocalizations.of(context).bodyInfo,
      radius: tokens.cardRadius,
      child: Column(
        children: [
          _buildBirthDateField(),
          SizedBox(height: tokens.gridGap),
          _buildStatField(
            fieldKey: const Key('detail-height-field'),
            label: AppLocalizations.of(context).heightCm,
            controller: heightController,
          ),
          SizedBox(height: tokens.gridGap),
          _buildStatField(
            fieldKey: const Key('detail-weight-field'),
            label: AppLocalizations.of(context).weightKg,
            controller: weightController,
          ),
          SizedBox(height: tokens.gridGap),
          _buildStatField(
            fieldKey: const Key('detail-cup-field'),
            label: AppLocalizations.of(context).cup,
            controller: cupController,
          ),
          SizedBox(height: tokens.gridGap),
          _buildStatField(
            fieldKey: const Key('detail-measurements-field'),
            label: AppLocalizations.of(context).measurements,
            controller: bwhController,
          ),
        ],
      ),
    );
  }

  Widget _buildNotesPanel(AppLayoutTokens tokens) {
    return _buildCard(
      title: AppLocalizations.of(context).privateNotes,
      radius: tokens.cardRadius,
      child: controller.isEditing
          ? TextField(
              controller: memoController,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            )
          : Text(
              memoController.text.isEmpty
                  ? AppLocalizations.of(context).noNotes
                  : memoController.text,
              style: const TextStyle(fontSize: 14),
            ),
    );
  }

  Widget _buildBirthDateField() {
    final selectedDate = birthDate;
    final label = AppLocalizations.of(context).birthDate;
    final colorScheme = Theme.of(context).colorScheme;

    if (!controller.isEditing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (selectedDate != null)
              Text(
                AppLocalizations.of(context).ageWithBirthDate(
                  _ageOn(selectedDate, DateTime.now()),
                  _displayDate(selectedDate),
                ),
                style: const TextStyle(fontSize: 14),
              )
            else
              const Text('—', style: TextStyle(fontSize: 14)),
          ],
        ),
      );
    }

    return OutlinedButton(
      key: const Key('detail-birth-date-button'),
      onPressed: _openBirthDatePicker,
      style: _detailOutlinedButtonStyle(),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          selectedDate == null
              ? AppLocalizations.of(context).setBirthDate
              : _displayDate(selectedDate),
          style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Future<void> _openBirthDatePicker() async {
    _dismissKeyboard();
    final result = await showModalBottomSheet<_BirthDatePickerResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _BirthDatePickerSheet(initialDate: birthDate),
    );

    if (!mounted || result == null) return;
    setState(() {
      birthDate = result.clear ? null : result.date;
    });
  }

  DateTime? _parseBirthDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String _toIsoDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _displayDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}';
  }

  int _ageOn(DateTime birthDate, DateTime today) {
    var age = today.year - birthDate.year;
    final birthdayPassed =
        today.month > birthDate.month ||
        (today.month == birthDate.month && today.day >= birthDate.day);
    if (!birthdayPassed) age--;
    return age;
  }

  Widget _buildStatField({
    required Key fieldKey,
    required String label,
    required TextEditingController controller,
  }) {
    final isEditing = this.controller.isEditing;
    final colorScheme = Theme.of(context).colorScheme;

    if (!isEditing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              controller.text.isEmpty ? '—' : controller.text,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      );
    }

    return TextField(
      key: fieldKey,
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_detailControlRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_detailControlRadius),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_detailControlRadius),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required Widget child,
    double radius = 16,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // 開啟刪除確認視窗，實際刪除流程交給 controller 處理。
  Future<void> _openDeleteDialog() async {
    final dialogState = controller.openDeleteDialog();

    if (dialogState['open'] != true) return;

    _dismissKeyboard();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context).confirmDeleteTitle),
          content: Text(AppLocalizations.of(context).deleteWarningWithPhoto),
          actions: [
            TextButton(
              onPressed: () {
                controller.closeDeleteDialog();
                Navigator.of(dialogContext).pop();
              },
              child: Text(AppLocalizations.of(context).cancel),
            ),
            TextButton(
              onPressed: () async {
                controller.closeDeleteDialog();
                Navigator.of(dialogContext).pop();
                await controller.executeDelete(context);
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(AppLocalizations.of(context).confirmDelete),
            ),
          ],
        );
      },
    );
  }
}

class _AliasesDialog extends StatefulWidget {
  const _AliasesDialog({required this.initialAliases, required this.onSave});

  final List<String> initialAliases;
  final Future<bool> Function(Iterable<String> aliases) onSave;

  @override
  State<_AliasesDialog> createState() => _AliasesDialogState();
}

class _AliasesDialogState extends State<_AliasesDialog> {
  late final List<String> aliases;
  final inputController = TextEditingController();
  var saving = false;

  @override
  void initState() {
    super.initState();
    aliases = widget.initialAliases.toList();
  }

  @override
  void dispose() {
    inputController.dispose();
    super.dispose();
  }

  void _addAlias() {
    final value = inputController.text.trim();
    if (value.isEmpty ||
        aliases.any((alias) => alias.toLowerCase() == value.toLowerCase())) {
      return;
    }
    setState(() {
      aliases.add(value);
      inputController.clear();
    });
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    final success = await widget.onSave(aliases);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => saving = false);
    AppSnackBar.showError(
      context,
      AppLocalizations.of(context).saveFailedDuplicateName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const Key('detail-aliases-dialog'),
      title: Text(l10n.manageAliases),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('detail-alias-input'),
                      controller: inputController,
                      enabled: !saving,
                      decoration: InputDecoration(
                        hintText: l10n.aliasInputHint,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addAlias(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    key: const Key('detail-alias-add'),
                    tooltip: l10n.addAlias,
                    onPressed: saving ? null : _addAlias,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (aliases.isEmpty)
                Text(l10n.noAliases)
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final alias in aliases)
                      InputChip(
                        label: Text(alias),
                        onDeleted: saving
                            ? null
                            : () => setState(() => aliases.remove(alias)),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('detail-alias-save'),
          onPressed: saving ? null : _save,
          child: Text(l10n.saveAliases),
        ),
      ],
    );
  }
}
