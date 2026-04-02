import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:community_material_icon/community_material_icon.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';

import 'package:borneo_app/devices/borneo/lyfi/views/dashboard/toufu_view.dart';
import 'package:gauge_indicator/gauge_indicator.dart';

import '../../view_models/lyfi_view_model.dart';
import '../widgets/rolling_integer.dart';

class DashboardTemperatureTile extends StatelessWidget {
  const DashboardTemperatureTile({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final greenBg = isDark ? Colors.green[800]!.withValues(alpha: 0.38) : Colors.green[100]!;
    final yellowBg = isDark ? Colors.amber[800]!.withValues(alpha: 0.38) : Colors.amber[100]!;
    final redBg = isDark ? Colors.red[800]!.withValues(alpha: 0.38) : Colors.red[100]!;

    final (isOnline, currentTempRaw, currentTemp, temperatureUnitText, fanPowerRatio) = context
        .select<LyfiViewModel, (bool, int?, int?, String, double?)>(
          (vm) =>
              (vm.isOnline, vm.currentTempRaw, vm.currentTemp, vm.localeService.temperatureUnitText, vm.fanPowerRatio),
        );
    final disabledColor = theme.colorScheme.onSurface.withValues(alpha: 0.38);
    final Color fgColor = theme.colorScheme.onSurface;

    Color progressColor;
    if (currentTempRaw != null && currentTempRaw <= 45) {
      progressColor = Colors.lightGreen;
    } else if (currentTempRaw != null && currentTempRaw > 45 && currentTempRaw < 65) {
      progressColor = theme.colorScheme.secondary;
    } else if (currentTempRaw != null && currentTempRaw >= 65) {
      progressColor = theme.colorScheme.error;
    } else {
      progressColor = theme.disabledColor;
    }

    return DashboardToufu(
      title: context.translate("Temperature & Fan"),
      icon: Icons.thermostat,
      foregroundColor: isOnline ? fgColor : disabledColor,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      arcColor: null,
      progressColor: progressColor,
      value: (currentTempRaw?.toDouble() ?? 0.0).clamp(0, 105),
      minValue: 0,
      maxValue: 105,
      center: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            mainAxisAlignment: MainAxisAlignment.center,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (isOnline && currentTemp != null)
                ...() {
                  final String tempStr = currentTemp.toString().padLeft(3, '0');
                  final List<String> digits = tempStr.split('');
                  final List<Widget> digitWidgets = [];
                  for (int i = 0; i < digits.length; i++) {
                    final String digit = digits[i];
                    final bool isLeadingZero =
                        i < digits.length - 1 && digit == '0' && digits.sublist(0, i).every((c) => c == '0');
                    final Color color = isLeadingZero ? theme.colorScheme.surfaceDim : progressColor;
                    digitWidgets.add(
                      RollingInteger(
                        value: int.parse(digit),
                        textStyle: theme.textTheme.headlineLarge?.copyWith(
                          color: color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        duration: const Duration(milliseconds: 300),
                      ),
                    );
                  }
                  return digitWidgets;
                }()
              else
                Text(
                  context.translate("N/A"),
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
              if (isOnline && currentTemp != null)
                Text(
                  temperatureUnitText,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: progressColor,
                  ),
                ),
            ],
          ),
          const Divider(height: 6, thickness: 1, indent: 24, endIndent: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isOnline && fanPowerRatio != null) ...[
                Icon(CommunityMaterialIcons.fan, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  '${fanPowerRatio.toInt().toString().padLeft(3)}%',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ] else
                Text(
                  context.translate("N/A"),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outlineVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ],
      ),
      segments: [
        GaugeSegment(from: 25, to: 45, color: greenBg),
        GaugeSegment(from: 45, to: 65, color: yellowBg),
        GaugeSegment(from: 65, to: 105, color: redBg),
      ],
    );
  }
}

// rolling integer moved to widgets/rolling_integer.dart
