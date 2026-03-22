import 'package:borneo_app/core/utils/hex_color.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/summary_device_view_model.dart';
import 'package:borneo_app/devices/view_models/abstract_device_summary_view_model.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LyfiSummaryCardCenter extends StatelessWidget {
  const LyfiSummaryCardCenter({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<
      AbstractDeviceSummaryViewModel,
      ({bool isOnline, bool isPowerOn, LyfiDeviceInfo? deviceInfo, List<int>? brightness})
    >(
      selector: (_, vm) {
        final lvm = vm as LyfiSummaryDeviceViewModel;
        return (
          isOnline: lvm.isOnline,
          isPowerOn: lvm.isPowerOn,
          deviceInfo: lvm.lyfiDeviceInfo,
          brightness: lvm.channelBrightness,
        );
      },
      builder: (context, props, _) {
        final showIcon =
            !props.isOnline ||
            !props.isPowerOn ||
            props.deviceInfo == null ||
            props.brightness == null ||
            props.deviceInfo!.channels.isEmpty;
        if (showIcon) {
          return Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final iconSize = constraints.maxHeight * 0.72;
                if (!props.isOnline) {
                  return Icon(
                    Icons.wifi_off,
                    size: iconSize,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                  );
                }
                if (!props.isPowerOn) {
                  return Icon(
                    Icons.power_off_outlined,
                    size: iconSize,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                  );
                }
                return _buildDeviceIcon(context, iconSize);
              },
            ),
          );
        }
        return _LyfiBrightnessChart(deviceInfo: props.deviceInfo!, brightness: props.brightness!);
      },
    );
  }

  Widget _buildDeviceIcon(BuildContext context, double iconSize) {
    return Icon(Icons.light_outlined, size: iconSize, color: Theme.of(context).colorScheme.primary);
  }
}

/// A compact bar chart that displays Lyfi per-channel brightness.
/// For a single channel, renders a circular progress indicator instead.
class _LyfiBrightnessChart extends StatelessWidget {
  final LyfiDeviceInfo deviceInfo;
  final List<int> brightness;

  const _LyfiBrightnessChart({required this.deviceInfo, required this.brightness});

  @override
  Widget build(BuildContext context) {
    final channelCount = deviceInfo.channels.length.clamp(0, brightness.length);
    if (channelCount == 1) {
      return _buildSingleChannelGauge(context);
    }
    return _buildBarChart(context, channelCount);
  }

  Widget _buildSingleChannelGauge(BuildContext context) {
    final ch = deviceInfo.channels[0];
    final value = brightness[0];
    final fraction = (value / kLyfiBrightnessMax).clamp(0.0, 1.0).toDouble();
    final pct = (fraction * 100).round();
    final primaryColor = HexColor.fromHex(ch.color);
    final trackColor = Theme.of(context).colorScheme.surfaceContainerHigh;
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest.shortestSide;
          return SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: fraction,
                  strokeWidth: size * 0.09,
                  backgroundColor: trackColor,
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  strokeCap: StrokeCap.round,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$pct%',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontSize: (size * 0.22).clamp(12.0, 22.0),
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    Text(
                      ch.name,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: (size * 0.13).clamp(8.0, 13.0),
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBarChart(BuildContext context, int channelCount) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final barWidth =
        (channelCount <= 4
                ? 18.0
                : channelCount <= 6
                ? 13.0
                : channelCount <= 8
                ? 10.0
                : 7.0)
            .toDouble();
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < channelCount; i++) {
      final ch = deviceInfo.channels[i];
      final value = brightness[i].toDouble();
      final primaryColor = HexColor.fromHex(ch.color);

      final hslColor = HSLColor.fromColor(primaryColor);
      final mutedColor = hslColor
          .withSaturation((hslColor.saturation * 0.25).clamp(0.0, 1.0))
          .withLightness(isDark ? 0.25 : 0.75)
          .toColor();
      final barBackColor = Color.lerp(colorScheme.surfaceContainerLow, mutedColor, 0.65)!;

      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: value,
              borderRadius: BorderRadius.zero,
              color: primaryColor,
              width: barWidth,
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                fromY: 0,
                toY: kLyfiBrightnessMax.toDouble(),
                color: barBackColor,
              ),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        barGroups: groups,
        maxY: kLyfiBrightnessMax.toDouble(),
        groupsSpace: channelCount > 6 ? 4 : 8,
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        barTouchData: const BarTouchData(enabled: false),
      ),
      duration: const Duration(seconds: 1),
    );
  }
}
