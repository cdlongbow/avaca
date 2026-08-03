import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:avaca/l10n/app_localizations.dart';
import '../controllers/settings_controller.dart';
import '../core/database.dart';

class _SettingsInteractionTheme extends StatelessWidget {
  const _SettingsInteractionTheme({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final overlayColor = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) {
        return Colors.transparent;
      }
      if (states.contains(WidgetState.focused)) {
        return base.colorScheme.primary.withValues(alpha: 0.12);
      }
      if (states.contains(WidgetState.hovered)) {
        return base.colorScheme.primary.withValues(alpha: 0.08);
      }
      return null;
    });

    return Theme(
      data: base.copyWith(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        textButtonTheme: TextButtonThemeData(
          style:
              base.textButtonTheme.style?.copyWith(
                overlayColor: overlayColor,
              ) ??
              ButtonStyle(overlayColor: overlayColor),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style:
              base.filledButtonTheme.style?.copyWith(
                overlayColor: overlayColor,
              ) ??
              ButtonStyle(overlayColor: overlayColor),
        ),
        iconButtonTheme: IconButtonThemeData(
          style:
              base.iconButtonTheme.style?.copyWith(
                overlayColor: overlayColor,
              ) ??
              ButtonStyle(overlayColor: overlayColor),
        ),
        radioTheme: base.radioTheme.copyWith(overlayColor: overlayColor),
        switchTheme: base.switchTheme.copyWith(overlayColor: overlayColor),
      ),
      child: child,
    );
  }
}

class _SettingsTapFeedback extends StatefulWidget {
  const _SettingsTapFeedback({required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  State<_SettingsTapFeedback> createState() => _SettingsTapFeedbackState();
}

class _SettingsTapFeedbackState extends State<_SettingsTapFeedback> {
  static const double _dotSize = 12;
  static const Duration _fadeDuration = Duration(milliseconds: 120);

  Timer? _removalTimer;
  Offset? _position;
  bool _visible = false;

  @override
  void dispose() {
    _removalTimer?.cancel();
    super.dispose();
  }

  void _show(PointerDownEvent event) {
    _removalTimer?.cancel();
    setState(() {
      _position = event.localPosition;
      _visible = true;
    });
  }

  void _hide(PointerEvent event) {
    if (_position == null) return;

    setState(() => _visible = false);
    _removalTimer?.cancel();
    _removalTimer = Timer(_fadeDuration, () {
      if (!mounted) return;
      setState(() => _position = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;

    return Listener(
      onPointerDown: _show,
      onPointerUp: _hide,
      onPointerCancel: _hide,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          widget.child,
          if (position != null)
            Positioned(
              left: position.dx - (_dotSize / 2),
              top: position.dy - (_dotSize / 2),
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: _fadeDuration,
                  curve: Curves.easeOut,
                  child: SizedBox.square(
                    dimension: _dotSize,
                    child: DecoratedBox(
                      key: ValueKey('settings-feedback-dot-${widget.id}'),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.28),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.db,
    required this.onThemeChanged,
    required this.onLocaleChanged,
  });

  final AppDatabase db;
  final void Function(
    ThemeMode themeMode,
    bool isPureBlack,
    Map<String, Color>? customColors,
  )
  onThemeChanged;
  final void Function(Locale? locale) onLocaleChanged;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  static const double _settingsCardRadius = 12;
  static const AnimationStyle _expansionAnimationStyle = AnimationStyle(
    duration: Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  late final SettingsController controller;

  @override
  void initState() {
    super.initState();
    controller = SettingsController(db: widget.db);
    // 載入目前儲存的外觀設定
    controller.loadFromPrefs();
    controller.loadCustomTheme();
    // 監聽設定變更並同步更新畫面
    controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  // 將 controller 的外觀與語言狀態同步給外層，並重建目前畫面
  void _onControllerChanged() {
    if (!mounted) return;
    widget.onThemeChanged(
      controller.themeMode,
      controller.isPureBlack,
      controller.isCustomTheme ? controller.customColors : null,
    );
    widget.onLocaleChanged(controller.appLocale);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsInteractionTheme(
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context).settings),
          leading: _SettingsTapFeedback(
            id: 'settings-back',
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        body: _buildSettingsCategories(),
      ),
    );
  }

  Widget _buildSettingsCategories() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _categoryCard(
          feedbackId: 'category-theme-colors',
          icon: Icons.palette_outlined,
          title: AppLocalizations.of(context).themeAndColors,
          onTap: () => _openCategory(
            titleBuilder: (context) =>
                AppLocalizations.of(context).themeAndColors,
            bodyBuilder: _buildThemeAndColors,
          ),
        ),
        const SizedBox(height: 8),
        _categoryCard(
          feedbackId: 'category-interface',
          icon: Icons.language,
          title: AppLocalizations.of(context).interfaceSettings,
          onTap: () => _openCategory(
            titleBuilder: (context) =>
                AppLocalizations.of(context).interfaceSettings,
            bodyBuilder: _buildInterfaceSettings,
          ),
        ),
      ],
    );
  }

  Widget _categoryCard({
    required String feedbackId,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return _SettingsTapFeedback(
      id: feedbackId,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerHighest,
        elevation: 0,
        shape: _outlinedCardShape(context),
        child: ListTile(leading: Icon(icon), title: Text(title), onTap: onTap),
      ),
    );
  }

  RoundedRectangleBorder _outlinedCardShape(BuildContext context) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_settingsCardRadius),
      side: BorderSide(width: 1, color: Theme.of(context).colorScheme.outline),
    );
  }

  Future<void> _openCategory({
    required String Function(BuildContext context) titleBuilder,
    required Widget Function(BuildContext context) bodyBuilder,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _SettingsCategoryPage(
          controller: controller,
          titleBuilder: titleBuilder,
          bodyBuilder: bodyBuilder,
        ),
      ),
    );
  }

  Widget _buildThemeAndColors(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [_themeModeSelector(context)],
    );
  }

  Widget _buildInterfaceSettings(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [_languageSelector(context)],
    );
  }

  Widget _themeModeSelector(BuildContext context) {
    final current = controller.themeModeString;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final shape = _outlinedCardShape(context);

    return _SettingsTapFeedback(
      id: 'theme-mode',
      child: ExpansionTile(
        key: const PageStorageKey('theme-mode'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        backgroundColor: colorScheme.surfaceContainerHighest,
        collapsedBackgroundColor: colorScheme.surfaceContainerHighest,
        shape: shape,
        collapsedShape: shape,
        clipBehavior: Clip.antiAlias,
        expansionAnimationStyle: _expansionAnimationStyle,
        title: Text(AppLocalizations.of(context).themeMode),
        children: [
          RadioGroup<String>(
            groupValue: current,
            onChanged: (selected) async {
              if (selected != null) {
                await controller.themeModeChanged(selected);
              }
            },
            child: Column(
              children: [
                _themeModeRadioOption(context, 'system'),
                _themeModeRadioOption(context, 'light'),
                if (isDark && !controller.isCustomTheme)
                  _expandableThemeModeOption(
                    context,
                    key: const PageStorageKey('theme-option-dark'),
                    value: 'dark',
                    child: _pureBlackSwitch(context),
                  )
                else
                  _themeModeRadioOption(context, 'dark'),
                if (controller.isCustomTheme)
                  _expandableThemeModeOption(
                    context,
                    key: const PageStorageKey('theme-option-custom'),
                    value: 'custom',
                    child: _customThemeEditor(context),
                  )
                else
                  _themeModeRadioOption(context, 'custom'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _themeModeRadioOption(BuildContext context, String value) {
    return RadioListTile<String>(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(_themeModeLabel(context, value)),
      value: value,
    );
  }

  Widget _expandableThemeModeOption(
    BuildContext context, {
    required Key key,
    required String value,
    required Widget child,
  }) {
    return ExpansionTile(
      key: key,
      leading: Radio<String>(value: value),
      title: Text(_themeModeLabel(context, value)),
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      shape: const Border(),
      collapsedShape: const Border(),
      expansionAnimationStyle: _expansionAnimationStyle,
      children: [child],
    );
  }

  Widget _languageSelector(BuildContext context) {
    final current = controller.localeString;
    final colorScheme = Theme.of(context).colorScheme;
    final shape = _outlinedCardShape(context);

    return _SettingsTapFeedback(
      id: 'language',
      child: ExpansionTile(
        key: const PageStorageKey('language'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        backgroundColor: colorScheme.surfaceContainerHighest,
        collapsedBackgroundColor: colorScheme.surfaceContainerHighest,
        shape: shape,
        collapsedShape: shape,
        clipBehavior: Clip.antiAlias,
        expansionAnimationStyle: _expansionAnimationStyle,
        title: Text(AppLocalizations.of(context).language),
        children: [
          RadioGroup<String>(
            groupValue: current,
            onChanged: (selected) async {
              if (selected != null) {
                await controller.languageChanged(selected);
              }
            },
            child: Column(
              children: controller.getLocaleOptions().map((value) {
                return RadioListTile<String>(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(_localeLabel(context, value)),
                  value: value,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _themeModeLabel(BuildContext context, String value) {
    return switch (value) {
      'system' => AppLocalizations.of(context).followSystem,
      'light' => AppLocalizations.of(context).lightTheme,
      'dark' => AppLocalizations.of(context).darkTheme,
      'custom' => AppLocalizations.of(context).customTheme,
      _ => value,
    };
  }

  String _localeLabel(BuildContext context, String value) {
    return switch (value) {
      'system' => AppLocalizations.of(context).followSystem,
      'zh_TW' => AppLocalizations.of(context).traditionalChineseTaiwan,
      'zh_CN' => AppLocalizations.of(context).simplifiedChinese,
      'ja_JP' => AppLocalizations.of(context).japanese,
      'en' => AppLocalizations.of(context).english,
      _ => value,
    };
  }

  Widget _pureBlackSwitch(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(AppLocalizations.of(context).pureBlackAmoled),
      subtitle: Text(AppLocalizations.of(context).pureBlackOnlyDark),
      value: controller.isPureBlack,
      onChanged: (value) async {
        await controller.pureBlackChanged(value);
      },
    );
  }

  Widget _customThemeEditor(BuildContext context) {
    return Column(
      children: controller.customColors.entries
          .map((entry) => _customColorTile(context, entry))
          .toList(),
    );
  }

  Widget _customColorTile(BuildContext context, MapEntry<String, Color> entry) {
    return ListTile(
      title: Text(_colorLabel(context, entry.key)),
      trailing: _colorPreview(entry.value),
      onTap: () => _openColorPicker(context, entry.key),
    );
  }

  Widget _colorPreview(Color color) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black26),
      ),
    );
  }

  String _colorLabel(BuildContext context, String key) {
    return switch (key) {
      'surface' => AppLocalizations.of(context).colorSurface,
      'surfaceContainer' => AppLocalizations.of(context).colorSurfaceContainer,
      'onSurface' => AppLocalizations.of(context).colorOnSurface,
      'onSurfaceVariant' => AppLocalizations.of(context).colorOnSurfaceVariant,
      'primary' => AppLocalizations.of(context).colorPrimary,
      'onPrimary' => AppLocalizations.of(context).colorOnPrimary,
      'outline' => AppLocalizations.of(context).colorOutline,
      'snackbarBackground' => AppLocalizations.of(
        context,
      ).colorSnackbarBackground,
      _ => key,
    };
  }

  Future<void> _openColorPicker(BuildContext context, String key) async {
    Color temp = controller.customColors[key]!;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => _SettingsTapFeedback(
          id: 'color-dialog',
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_settingsCardRadius),
              side: BorderSide(width: 1, color: temp),
            ),
            title: Text(
              AppLocalizations.of(
                context,
              ).adjustColorTitle(_colorLabel(context, key)),
            ),
            content: SingleChildScrollView(
              child: ColorPicker(
                pickerColor: temp,
                onColorChanged: (color) {
                  setDialogState(() => temp = color);
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(AppLocalizations.of(context).cancel),
              ),
              FilledButton(
                onPressed: () async {
                  controller.customColors[key] = temp;
                  await controller.saveCustomTheme();
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: Text(AppLocalizations.of(context).apply),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCategoryPage extends StatelessWidget {
  const _SettingsCategoryPage({
    required this.controller,
    required this.titleBuilder,
    required this.bodyBuilder,
  });

  final SettingsController controller;
  final String Function(BuildContext context) titleBuilder;
  final Widget Function(BuildContext context) bodyBuilder;

  @override
  Widget build(BuildContext context) {
    return _SettingsInteractionTheme(
      child: Scaffold(
        appBar: AppBar(
          title: Text(titleBuilder(context)),
          leading: _SettingsTapFeedback(
            id: 'category-back',
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => bodyBuilder(context),
        ),
      ),
    );
  }
}
