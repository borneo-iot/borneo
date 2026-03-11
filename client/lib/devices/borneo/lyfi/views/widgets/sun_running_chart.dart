import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/lyfi_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/widgets/lyfi_time_line_chart.dart';
import 'package:borneo_app/core/utils/hex_color.dart';
import 'package:borneo_common/datetime_ext.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const Duration _kSunChartAnimationDuration = Duration(milliseconds: 20);

class SunRunningChart extends StatefulWidget {
  final ScheduleTable sunInstants;
  final List<LyfiChannelInfo> channelInfoList;
  const SunRunningChart({required this.sunInstants, required this.channelInfoList, super.key});

  @override
  State<SunRunningChart> createState() => _SunRunningChartState();
}

class _SunRunningChartState extends State<SunRunningChart> {
  late List<LineChartBarData> _lineData;
  late int _lineDataSignature;

  @override
  void initState() {
    super.initState();
    _refreshLineData();
  }

  @override
  void didUpdateWidget(covariant SunRunningChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _buildLineDataSignature(widget.sunInstants, widget.channelInfoList);
    if (signature != _lineDataSignature) {
      _refreshLineData();
    }
  }

  void _refreshLineData() {
    _lineDataSignature = _buildLineDataSignature(widget.sunInstants, widget.channelInfoList);
    _lineData = _buildLineData(widget.sunInstants, widget.channelInfoList);
  }

  int _buildLineDataSignature(ScheduleTable instants, List<LyfiChannelInfo> channels) {
    return Object.hashAll([
      channels.length,
      for (final channel in channels) Object.hash(channel.name, channel.color, channel.wavelength),
      instants.length,
      for (final instant in instants) Object.hash(instant.instant, Object.hashAll(instant.color)),
    ]);
  }

  List<LineChartBarData> _buildLineData(ScheduleTable sunInstants, List<LyfiChannelInfo> channelInfoList) {
    final series = <LineChartBarData>[];
    for (int channelIndex = 0; channelIndex < channelInfoList.length; channelIndex++) {
      bool allZero = true;
      for (final instant in sunInstants) {
        if (instant.color[channelIndex] != 0) {
          allZero = false;
          break;
        }
      }
      if (allZero) {
        continue;
      }

      final spots = <FlSpot>[];
      for (final entry in sunInstants) {
        spots.add(FlSpot(entry.instant.inSeconds.toDouble(), entry.color[channelIndex].toDouble()));
      }
      series.add(
        LineChartBarData(
          isCurved: false,
          barWidth: 1.5,
          color: HexColor.fromHex(channelInfoList[channelIndex].color),
          dotData: const FlDotData(show: false),
          spots: spots,
        ),
      );
    }
    return series;
  }

  @override
  Widget build(BuildContext context) {
    LyfiViewModel vm = context.read<LyfiViewModel>();
    if (!vm.isOnline) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Selector<LyfiViewModel, DateTime>(
        selector: (context, vm) => vm.lyfiThing.getProperty<DateTime>('timestamp')!.toLocal(),
        shouldRebuild: (previous, next) => !previous.isEqualToSecond(next),
        builder: (context, clock, _) {
          final double sunriseInstant = widget.sunInstants.isNotEmpty
              ? (widget.sunInstants.first.instant.inSeconds / 3600.0).floorToDouble() * 3600
              : 0;
          final double sunsetInstant = widget.sunInstants.isNotEmpty
              ? (widget.sunInstants.last.instant.inSeconds / 3600.0).ceilToDouble() * 3600
              : 0;
          final int clockInSeconds = clock.hour * 3600 + clock.minute * 60 + clock.second;
          final bool isDaytime = clockInSeconds >= sunriseInstant && clockInSeconds <= sunsetInstant;
          final double minX = isDaytime ? sunriseInstant : 0;
          final double maxX = isDaytime ? sunsetInstant : 86400;
          return LyfiTimeLineChart(
            lineBarsData: _lineData,
            minX: minX,
            maxX: maxX,
            minY: 0,
            maxY: kLyfiBrightnessMax.toDouble(),
            currentTime: Duration(hours: clock.hour, minutes: clock.minute, seconds: clock.second),
            animationDuration: _kSunChartAnimationDuration,
          );
        },
      ),
    );
  }
}
