import 'package:flutter/material.dart';
import 'package:flutter_settings_ui/flutter_settings_ui.dart';

import 'settings_tile_slider.dart';

/// Helpers that make it easier to build bespoke [SettingsTile] variants used
/// in the application.  The `flutter_settings_ui` package ships only a few
/// constructors; this module provides named helpers for common patterns we
/// reuse elsewhere.

/// Return a tile containing an adaptive slider inside its description slot.
///
/// Using a helper keeps call sites concise and avoids manual layout work.
///
/// Example:
///
/// ```dart
/// settingsSliderTile(
///   title: Text('Duration'),
///   value: vm.days,
///   min: 5,
///   max: 100,
///   onChanged: vm.updateDays,
///   trailing: Text('${vm.days.round()} days'),
/// );
/// ```
AbstractSettingsTile settingsSliderTile({
  required Widget title,
  required double value,
  required ValueChanged<double> onChanged,
  ValueChanged<double>? onChangeEnd,
  DevicePlatform? platform,
  double min = 0,
  double max = 1,
  Widget? leading,
  Widget? description,
  int? divisions,
  String? label,
  Widget? trailing,
  Color? backgroundColor,
  bool enabled = true,
  bool showStepButtons = false,
  Key? key,
}) {
  return SettingsTileSlider(
    key: key,
    title: title,
    leading: leading,
    description: description,
    value: value,
    platform: platform,
    min: min,
    max: max,
    divisions: divisions,
    label: label,
    onChanged: onChanged,
    onChangeEnd: onChangeEnd,
    trailing: trailing,
    backgroundColor: backgroundColor,
    enabled: enabled,
    showStepButtons: showStepButtons,
  );
}
