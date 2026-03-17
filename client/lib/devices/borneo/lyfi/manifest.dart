import 'package:borneo_app/core/services/local_service.dart';
import 'package:borneo_app/core/utils/hex_color.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/lyfi_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/summary_device_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/lyfi_view.dart';
import 'package:borneo_app/devices/view_models/abstract_device_summary_view_model.dart';
import 'package:borneo_app/features/devices/models/device_module_metadata.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:borneo_wot/borneo/lyfi/wot_thing.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:event_bus/event_bus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext.dart';
import 'package:logger/logger.dart';
import 'package:lw_wot/wot.dart';

import 'package:provider/provider.dart';

import 'package:borneo_kernel/drivers/borneo/lyfi/metadata.dart';

class LyfiDeviceModuleMetadata extends DeviceModuleMetadata {
  LyfiDeviceModuleMetadata()
    : super(
        id: kLyfiDriverID,
        name: kLyfiDriverName,
        driverDescriptor: borneoLyfiDriverDescriptor,
        detailsViewBuilder: (_) => LyfiView(),
        detailsViewModelBuilder: (context, deviceID) => LyfiViewModel(
          deviceManager: context.read<IDeviceManager>(),
          globalEventBus: context.read<EventBus>(),
          notification: context.read<IAppNotificationService>(),
          wotThing: context.read<IDeviceManager>().getWotThing(deviceID),
          localeService: context.read<ILocaleService>(),
          gt: GettextLocalizations.of(context),
          logger: context.read<Logger>(),
        ),
        deviceIconBuilder: _buildDeviceIcon,
        primaryStateIconBuilder: _buildPrimaryStateIcon,
        secondaryStatesBuilder: _secondaryStatesBuilder,
        summaryContentBuilder: _buildCardCenter,
        createSummaryVM: (dev, dm, bus, gt) => LyfiSummaryDeviceViewModel(dev, dm, bus, gt: gt),
        createWotThing: _createWotThing,
      );

  static Widget _buildDeviceIcon(BuildContext context, double iconSize, bool isOnline) {
    return Icon(Icons.light_outlined, size: iconSize, color: Theme.of(context).colorScheme.primary);
  }

  static Widget _buildPrimaryStateIcon(BuildContext context, double iconSize) {
    return Icon(Icons.light_mode_outlined, size: iconSize, color: Theme.of(context).colorScheme.onSurface);
  }

  static List<Widget> _secondaryStatesBuilder(BuildContext context, AbstractDeviceSummaryViewModel vm) {
    final stateWidget = Selector<AbstractDeviceSummaryViewModel, LyfiState?>(
      selector: (_, vm) => (vm as LyfiSummaryDeviceViewModel).ledState,
      builder: (context, state, child) =>
          Text(_stateText(context, state), style: Theme.of(context).textTheme.labelSmall),
    );
    final modeWidget = Selector<AbstractDeviceSummaryViewModel, LyfiMode?>(
      selector: (_, vm) => (vm as LyfiSummaryDeviceViewModel).ledMode,
      builder: (context, mode, child) => Text(_modeText(context, mode), style: Theme.of(context).textTheme.labelSmall),
    );
    return [stateWidget, modeWidget];
  }

  /// Custom card center: bar chart of per-channel brightness.
  /// Falls back to a large offline icon when disconnected, otherwise the device
  /// icon when powered off or data is unavailable.
  static Widget _buildCardCenter(BuildContext context, AbstractDeviceSummaryViewModel vm) {
    final lvm = vm as LyfiSummaryDeviceViewModel;
    return Selector<AbstractDeviceSummaryViewModel, LyfiDeviceInfo?>(
      selector: (_, vm) => (vm as LyfiSummaryDeviceViewModel).lyfiDeviceInfo,
      builder: (context, deviceInfo, _) {
        return Selector<AbstractDeviceSummaryViewModel, List<int>?>(
          selector: (_, vm) => (vm as LyfiSummaryDeviceViewModel).channelBrightness,
          builder: (context, brightness, _) {
            // Show large icon when offline, powered off, or data not yet available
            final showIcon =
                !lvm.isOnline ||
                !lvm.isPowerOn ||
                deviceInfo == null ||
                brightness == null ||
                deviceInfo.channels.isEmpty;
            if (showIcon) {
              return Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final iconSize = constraints.maxHeight * 0.72;
                    if (!lvm.isOnline) {
                      return Icon(
                        Icons.wifi_off,
                        size: iconSize,
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                      );
                    }
                    return _buildDeviceIcon(context, iconSize, lvm.isOnline);
                  },
                ),
              );
            }
            return _LyfiBrightnessChart(deviceInfo: deviceInfo, brightness: brightness);
          },
        );
      },
    );
  }

  static String _modeText(BuildContext context, LyfiMode? mode) {
    switch (mode) {
      case LyfiMode.manual:
        return context.translate('MANU');
      case LyfiMode.scheduled:
        return context.translate('SCHED');
      case LyfiMode.sun:
        return context.translate('SUN');
      default:
        return '-';
    }
  }

  static String _stateText(BuildContext context, LyfiState? state) => switch (state) {
    LyfiState.normal => context.translate('NORM'),
    LyfiState.dimming => context.translate('DIMM'),
    LyfiState.temporary => context.translate('TEMP'),
    LyfiState.preview => context.translate('PREV'),
    _ => '-',
  };

  static Future<WotThing> _createWotThing(
    DeviceEntity device,
    IDeviceManager deviceManager, {
    Logger? logger,
    CancellationToken? cancelToken,
  }) async => LyfiThing(kernel: deviceManager.kernel, deviceId: device.id, title: device.name, logger: logger);
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
      return _buildSingleChannelGauge(context, channelCount);
    }
    return _buildBarChart(context, channelCount);
  }

  Widget _buildSingleChannelGauge(BuildContext context, int channelCount) {
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

    // Adaptive bar width: shrink as channel count grows
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

      // Background rod: desaturate the channel color heavily and blend with the
      // surface so it looks muted but still carries a hint of the original hue.
      final hslColor = HSLColor.fromColor(primaryColor);
      final mutedColor = hslColor
          .withSaturation((hslColor.saturation * 0.25).clamp(0.0, 1.0))
          .withLightness(isDark ? 0.25 : 0.75)
          .toColor();
      // Blend with surface for a softer look
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
