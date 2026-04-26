import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/lyfi_view_model.dart';
import 'package:borneo_app/core/utils/hex_color.dart';
import 'package:borneo_common/datetime_ext.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
// import 'package:borneo_common/duration_ext.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'lyfi_time_line_chart.dart';

class ScheduleRunningChart extends StatelessWidget {
  const ScheduleRunningChart({super.key});

  @override
  Widget build(BuildContext context) {
    LyfiViewModel vm = context.read<LyfiViewModel>();
    if (!vm.isOnline) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Selector<LyfiViewModel, ({DateTime clock, int scheduleSignature})>(
        selector: (context, vm) => (
          clock: vm.lyfiThing.getProperty<DateTime>('timestamp')!.toLocal(),
          scheduleSignature: Object.hashAll(
            vm.scheduledInstants.map((e) => Object.hash(e.instant, Object.hashAll(e.color))),
          ),
        ),
        shouldRebuild: (previous, next) =>
            !previous.clock.isEqualToMinute(next.clock) || previous.scheduleSignature != next.scheduleSignature,
        builder: (context, data, _) {
          final clock = data.clock;
          const minSpanSeconds = 3 * 3600.0;
          final sortedInstants = _sortedInstants(vm);
          double minX = 0.0;
          double maxX = 24 * 3600.0;
          if (sortedInstants.isNotEmpty) {
            final hasCrossDay = sortedInstants.any((e) => e.instant.inHours >= 24);
            if (hasCrossDay) {
              minX = sortedInstants.first.instant.inSeconds.toDouble();
              maxX = sortedInstants.last.instant.inSeconds.toDouble();
              if (maxX - minX < minSpanSeconds) {
                maxX = minX + minSpanSeconds;
              }
            }
          }
          final maxScale = ((maxX - minX) / minSpanSeconds).clamp(1.0, double.infinity);
          return LyfiTimeLineChart(
            lineBarsData: buildLineData(vm, sortedInstants),
            minX: minX,
            maxX: maxX,
            minY: 0,
            maxY: kLyfiBrightnessMax.toDouble(),
            currentTime: Duration(hours: clock.hour, minutes: clock.minute, seconds: clock.second),
            allowZoom: true,
            maxScale: maxScale,
          );
        },
      ),
    );
  }

  List<LineChartBarData> buildLineData(LyfiViewModel vm, List<ScheduledInstant> instants) {
    final series = <LineChartBarData>[];
    for (int channelIndex = 0; channelIndex < vm.channels.length; channelIndex++) {
      bool allZero = true;
      for (final instant in instants) {
        if (instant.color[channelIndex] != 0) {
          allZero = false;
          break;
        }
      }
      if (allZero) {
        continue;
      }
      final spots = <FlSpot>[];
      for (final entry in instants) {
        double x = entry.instant.inSeconds.toDouble();
        double y = entry.color[channelIndex].toDouble();
        final spot = FlSpot(x, y);
        spots.add(spot);
      }
      series.add(
        LineChartBarData(
          isCurved: false,
          barWidth: 1.5,
          color: HexColor.fromHex(vm.lyfiDeviceInfo.channels[channelIndex].color),
          dotData: const FlDotData(show: false),
          spots: spots,
        ),
      );
    }
    return series;
  }

  List<ScheduledInstant> _sortedInstants(LyfiViewModel vm) {
    final sorted = vm.scheduledInstants.toList();
    sorted.sort((a, b) => a.instant.compareTo(b.instant));
    return sorted;
  }
}
