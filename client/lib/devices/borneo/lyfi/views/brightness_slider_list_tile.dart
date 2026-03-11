import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_xlider/flutter_xlider.dart';

class BrightnessSliderListTile extends StatelessWidget {
  final Color color;
  final bool disabled;
  final int min;
  final int max;
  final int value;
  final String channelName;
  final Widget? trailing;
  final void Function(int) onChanged;

  const BrightnessSliderListTile({
    super.key,
    required this.channelName,
    required this.value,
    required this.color,
    this.disabled = false,
    this.min = 0,
    this.max = kLyfiBrightnessMax,
    this.trailing,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final handlerSize = 24.0;
    final trackBarBorder = Border.all(color: Theme.of(context).colorScheme.surfaceContainerHigh, width: 1);
    return ListTile(
      dense: true,
      minVerticalPadding: 0,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
      title: FlutterSlider(
        selectByTap: true,
        jump: true,
        disabled: disabled,
        handlerWidth: handlerSize,
        handlerHeight: handlerSize,
        handler: FlutterSliderHandler(
          child: Material(
            type: MaterialType.canvas,
            borderRadius: BorderRadius.circular(32),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Center(
              child: Icon(
                Icons.circle,
                color: disabled ? color.withValues(alpha: 0.38) : color,
                size: handlerSize * 0.60,
              ),
            ),
          ),
        ),
        step: const FlutterSliderStep(step: 1, isPercentRange: false),
        values: [value.toDouble()],
        handlerAnimation: const FlutterSliderHandlerAnimation(
          curve: Curves.elasticOut,
          reverseCurve: Curves.bounceIn,
          duration: Duration(milliseconds: 100),
          scale: 1.5,
        ),
        max: max.toDouble(),
        min: min.toDouble(),
        tooltip: FlutterSliderTooltip(disabled: true),
        trackBar: FlutterSliderTrackBar(
          activeTrackBarHeight: 6,
          inactiveTrackBarHeight: 6,
          activeDisabledTrackBarColor: color.withValues(alpha: 0.15),
          inactiveDisabledTrackBarColor: color.withValues(alpha: 0.15),
          activeTrackBar: BoxDecoration(border: trackBarBorder, color: color, borderRadius: BorderRadius.circular(3)),
          inactiveTrackBar: BoxDecoration(
            border: trackBarBorder,
            color: color.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        onDragging: (index, low, _) => onChanged(low.toInt()),
        onDragCompleted: (index, low, _) => onChanged(low.toInt()),
      ),
      trailing: trailing,
    );
  }
}
