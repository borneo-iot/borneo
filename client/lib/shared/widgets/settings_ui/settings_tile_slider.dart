import 'package:flutter/material.dart';
import 'package:flutter_settings_ui/flutter_settings_ui.dart';
// ignore: implementation_imports
import 'package:flutter_settings_ui/src/tiles/platforms/ios_settings_tile.dart' show IOSSettingsTileAdditionalInfo;

import '../adaptive_slider.dart';

class SettingsTileSlider extends AbstractSettingsTile {
  const SettingsTileSlider({
    required this.title,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.platform,
    this.leading,
    this.trailing,
    this.description,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.enabled = true,
    this.showStepButtons = false,
    this.backgroundColor,
    super.key,
  });

  final Widget title;
  final Widget? leading;
  final Widget? trailing;
  final Widget? description;
  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final DevicePlatform? platform;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final bool enabled;
  final bool showStepButtons;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = SettingsTheme.of(context);
    final effectivePlatform = platform ?? theme.platform;

    switch (effectivePlatform) {
      case DevicePlatform.android:
      case DevicePlatform.fuchsia:
      case DevicePlatform.linux:
        return _MaterialSettingsTileSlider(
          platform: effectivePlatform,
          leading: leading,
          title: title,
          trailing: trailing,
          description: description,
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          onChanged: enabled ? onChanged : null,
          onChangeEnd: enabled ? onChangeEnd : null,
          enabled: enabled,
          showStepButtons: showStepButtons,
          backgroundColor: backgroundColor,
        );
      case DevicePlatform.iOS:
      case DevicePlatform.macOS:
      case DevicePlatform.windows:
        return _IosSettingsTileSlider(
          platform: effectivePlatform,
          leading: leading,
          title: title,
          trailing: trailing,
          description: description,
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          onChanged: enabled ? onChanged : null,
          onChangeEnd: enabled ? onChangeEnd : null,
          enabled: enabled,
          showStepButtons: showStepButtons,
          backgroundColor: backgroundColor,
        );
      case DevicePlatform.web:
        return _MaterialSettingsTileSlider(
          platform: effectivePlatform,
          leading: leading,
          title: title,
          trailing: trailing,
          description: description,
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          onChanged: enabled ? onChanged : null,
          onChangeEnd: enabled ? onChangeEnd : null,
          enabled: enabled,
          showStepButtons: showStepButtons,
          backgroundColor: backgroundColor,
          transparentBackground: true,
        );
      case DevicePlatform.device:
        throw Exception(
          "You can't use the DevicePlatform.device in this context. Incorrect platform: SettingsTileSlider.build",
        );
    }
  }
}

class _MaterialSettingsTileSlider extends StatelessWidget {
  const _MaterialSettingsTileSlider({
    required this.platform,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.showStepButtons,
    this.transparentBackground = false,
    this.leading,
    this.trailing,
    this.description,
    this.divisions,
    this.label,
    this.onChanged,
    this.onChangeEnd,
    this.backgroundColor,
  });

  final DevicePlatform platform;
  final Widget title;
  final Widget? leading;
  final Widget? trailing;
  final Widget? description;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final bool enabled;
  final bool showStepButtons;
  final Color? backgroundColor;
  final bool transparentBackground;

  @override
  Widget build(BuildContext context) {
    final theme = SettingsTheme.of(context);
    final scaleFactor = MediaQuery.textScalerOf(context).scale(1);
    final trailingColor = enabled ? theme.themeData.settingsTileTextColor : theme.themeData.inactiveTitleColor;
    final step = _resolveStepSize(min: min, max: max, divisions: divisions);

    return IgnorePointer(
      ignoring: !enabled,
      child: Material(
        color: backgroundColor ?? Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 24, top: 20),
                child: IconTheme(
                  data: IconTheme.of(
                    context,
                  ).copyWith(color: enabled ? theme.themeData.leadingIconsColor : theme.themeData.inactiveTitleColor),
                  child: leading!,
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: 24,
                  end: 24,
                  top: 16 * scaleFactor,
                  bottom: 12 * scaleFactor,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DefaultTextStyle(
                            style: TextStyle(
                              color: enabled
                                  ? theme.themeData.settingsTileTextColor
                                  : theme.themeData.inactiveTitleColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w400,
                            ),
                            child: title,
                          ),
                        ),
                        if (trailing != null)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 12),
                            child: DefaultTextStyle(
                              style: TextStyle(color: trailingColor),
                              child: trailing!,
                            ),
                          ),
                      ],
                    ),
                    if (description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: DefaultTextStyle(
                          style: TextStyle(
                            color: enabled
                                ? theme.themeData.tileDescriptionTextColor
                                : theme.themeData.inactiveSubtitleColor,
                          ),
                          child: description!,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 8),
                      child: _SliderControlRow(
                        platform: platform,
                        value: value,
                        min: min,
                        max: max,
                        divisions: divisions,
                        label: label,
                        onChanged: onChanged,
                        onChangeEnd: onChangeEnd,
                        showStepButtons: showStepButtons,
                        step: step,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IosSettingsTileSlider extends StatelessWidget {
  const _IosSettingsTileSlider({
    required this.platform,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.showStepButtons,
    this.leading,
    this.trailing,
    this.description,
    this.divisions,
    this.label,
    this.onChanged,
    this.onChangeEnd,
    this.backgroundColor,
  });

  final DevicePlatform platform;
  final Widget title;
  final Widget? leading;
  final Widget? trailing;
  final Widget? description;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final bool enabled;
  final bool showStepButtons;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final additionalInfo = IOSSettingsTileAdditionalInfo.of(context);
    final theme = SettingsTheme.of(context);
    final scaleFactor = MediaQuery.textScalerOf(context).scale(1);
    final trailingColor = enabled ? theme.themeData.settingsTileTextColor : theme.themeData.inactiveTitleColor;
    final step = _resolveStepSize(min: min, max: max, divisions: divisions);

    Widget content = Container(
      width: MediaQuery.of(context).size.width,
      color: backgroundColor ?? theme.themeData.settingsSectionBackground,
      padding: const EdgeInsetsDirectional.only(start: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 14, end: 12),
              child: IconTheme.merge(
                data: IconThemeData(
                  color: enabled ? theme.themeData.leadingIconsColor : theme.themeData.inactiveTitleColor,
                ),
                child: leading!,
              ),
            ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsetsDirectional.only(top: 12.5 * scaleFactor, bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: DefaultTextStyle(
                                style: TextStyle(
                                  color: enabled
                                      ? theme.themeData.settingsTileTextColor
                                      : theme.themeData.inactiveTitleColor,
                                  fontSize: 16,
                                ),
                                child: title,
                              ),
                            ),
                            if (trailing != null)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(start: 12),
                                child: DefaultTextStyle(
                                  style: TextStyle(color: trailingColor, fontSize: 17),
                                  child: trailing!,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (description != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: DefaultTextStyle(
                                  style: TextStyle(color: theme.themeData.titleTextColor, fontSize: 13),
                                  child: description!,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(bottom: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: _SliderControlRow(
                            platform: platform,
                            value: value,
                            min: min,
                            max: max,
                            divisions: divisions,
                            label: label,
                            onChanged: onChanged,
                            onChangeEnd: onChangeEnd,
                            showStepButtons: showStepButtons,
                            step: step,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (additionalInfo.needToShowDivider)
                  Divider(height: 0, thickness: 0.7, color: theme.themeData.dividerColor),
              ],
            ),
          ),
        ],
      ),
    );

    if (detectPlatform(context) != DevicePlatform.iOS) {
      content = Material(color: Colors.transparent, child: content);
    }

    return IgnorePointer(
      ignoring: !enabled,
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: additionalInfo.enableTopBorderRadius ? const Radius.circular(12) : Radius.zero,
          bottom: additionalInfo.enableBottomBorderRadius ? const Radius.circular(12) : Radius.zero,
        ),
        child: content,
      ),
    );
  }
}

class _SliderControlRow extends StatelessWidget {
  const _SliderControlRow({
    required this.platform,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.showStepButtons,
    this.divisions,
    this.label,
    this.onChanged,
    this.onChangeEnd,
  });

  final DevicePlatform platform;
  final double value;
  final double min;
  final double max;
  final double step;
  final bool showStepButtons;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(min, max);

    if (!showStepButtons) {
      return AdaptiveSlider(
        platform: platform,
        value: clampedValue,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      );
    }

    return Row(
      children: [
        _SliderStepButton(
          icon: Icons.remove,
          onPressed: onChanged == null || clampedValue <= min
              ? null
              : () => _stepTo(onChanged!, onChangeEnd, clampedValue, min, max, -step),
        ),
        Expanded(
          child: AdaptiveSlider(
            platform: platform,
            value: clampedValue,
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        _SliderStepButton(
          icon: Icons.add,
          onPressed: onChanged == null || clampedValue >= max
              ? null
              : () => _stepTo(onChanged!, onChangeEnd, clampedValue, min, max, step),
        ),
      ],
    );
  }

  void _stepTo(
    ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
    double currentValue,
    double min,
    double max,
    double delta,
  ) {
    final nextValue = (currentValue + delta).clamp(min, max);
    onChanged(nextValue);
    onChangeEnd?.call(nextValue);
  }
}

class _SliderStepButton extends StatelessWidget {
  const _SliderStepButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

double _resolveStepSize({required double min, required double max, int? divisions}) {
  if (divisions != null && divisions > 0) {
    return (max - min) / divisions;
  }

  return 1;
}
