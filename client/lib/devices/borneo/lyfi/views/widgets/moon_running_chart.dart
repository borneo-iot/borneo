import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/widgets/lyfi_time_line_chart.dart';
import 'package:borneo_app/core/utils/hex_color.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class MoonRunningChart extends StatefulWidget {
  final ScheduleTable moonInstants;
  final List<LyfiChannelInfo> channelInfoList;
  const MoonRunningChart({required this.moonInstants, required this.channelInfoList, super.key});

  @override
  State<MoonRunningChart> createState() => _MoonRunningChartState();
}

class _MoonRunningChartState extends State<MoonRunningChart> {
  late List<LineChartBarData> _lineData;
  late int _lineDataSignature;

  @override
  void initState() {
    super.initState();
    _refreshLineData();
  }

  @override
  void didUpdateWidget(covariant MoonRunningChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _buildLineDataSignature(widget.moonInstants, widget.channelInfoList);
    if (signature != _lineDataSignature) {
      _refreshLineData();
    }
  }

  void _refreshLineData() {
    _lineDataSignature = _buildLineDataSignature(widget.moonInstants, widget.channelInfoList);
    _lineData = _buildLineData(widget.moonInstants, widget.channelInfoList, kLyfiBrightnessMax.toDouble());
  }

  int _buildLineDataSignature(ScheduleTable moonInstants, List<LyfiChannelInfo> channelInfoList) {
    return Object.hashAll([
      channelInfoList.length,
      for (final channel in channelInfoList) Object.hash(channel.name, channel.color, channel.wavelength),
      moonInstants.length,
      for (final instant in moonInstants) Object.hash(instant.instant, Object.hashAll(instant.color)),
    ]);
  }

  List<LineChartBarData> _buildLineData(
    ScheduleTable moonInstants,
    List<LyfiChannelInfo> channelInfoList,
    double maxBrightness,
  ) {
    final series = <LineChartBarData>[];
    for (int channelIndex = 0; channelIndex < channelInfoList.length; channelIndex++) {
      bool allZero = true;
      for (final instant in moonInstants) {
        if (instant.color[channelIndex] != 0) {
          allZero = false;
          break;
        }
      }
      if (allZero) {
        continue;
      }
      final spots = <FlSpot>[];
      for (final instant in moonInstants) {
        final normalizedY = maxBrightness > 0 ? instant.color[channelIndex] / maxBrightness : 0.0;
        spots.add(FlSpot(instant.instant.inSeconds.toDouble(), normalizedY));
      }
      final primaryColor = HexColor.fromHex(channelInfoList[channelIndex].color);
      series.add(
        LineChartBarData(
          spots: spots,
          isCurved: false,
          color: primaryColor,
          barWidth: 1.5,
          dotData: FlDotData(show: true),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }
    return series;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: LyfiTimeLineChart(
        lineBarsData: _lineData,
        minX: widget.moonInstants.isNotEmpty ? widget.moonInstants.first.instant.inSeconds.toDouble() : 0,
        maxX: widget.moonInstants.isNotEmpty ? widget.moonInstants.last.instant.inSeconds.toDouble() : 24 * 3600,
        minY: 0,
        maxY: 1.0,
      ),
    );
  }
}
