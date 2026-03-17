import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class LyfiColorChart extends BarChart {
  LyfiColorChart(super.data, {super.key, super.duration, super.curve});

  static Color computeBarBackColor(BuildContext context, Color primaryColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hslColor = HSLColor.fromColor(primaryColor);
    final mutedColor = hslColor
        .withSaturation((hslColor.saturation * 0.25).clamp(0.0, 1.0))
        .withLightness(isDark ? 0.25 : 0.75)
        .toColor();
    // Blend with surface for a softer look
    final barBackColor = Color.lerp(theme.colorScheme.surfaceContainerLow, mutedColor, 0.65)!;
    return barBackColor;
  }
}
