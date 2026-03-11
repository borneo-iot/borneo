import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_settings_ui/flutter_settings_ui.dart';

class AdaptiveSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final int? divisions;
  final String? label;
  final DevicePlatform? platform;

  const AdaptiveSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.platform,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePlatform = platform ?? _devicePlatformFromTarget(Theme.of(context).platform);

    if (_usesCupertinoSlider(effectivePlatform)) {
      return CupertinoSlider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      );
    }

    return Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      label: label,
      onChanged: onChanged,
      onChangeEnd: onChangeEnd,
    );
  }

  bool _usesCupertinoSlider(DevicePlatform platform) {
    return switch (platform) {
      DevicePlatform.iOS || DevicePlatform.macOS || DevicePlatform.windows => true,
      DevicePlatform.android ||
      DevicePlatform.fuchsia ||
      DevicePlatform.linux ||
      DevicePlatform.web ||
      DevicePlatform.device => false,
    };
  }

  DevicePlatform _devicePlatformFromTarget(TargetPlatform targetPlatform) {
    return switch (targetPlatform) {
      TargetPlatform.android => DevicePlatform.android,
      TargetPlatform.fuchsia => DevicePlatform.fuchsia,
      TargetPlatform.iOS => DevicePlatform.iOS,
      TargetPlatform.linux => DevicePlatform.linux,
      TargetPlatform.macOS => DevicePlatform.macOS,
      TargetPlatform.windows => DevicePlatform.windows,
    };
  }
}
