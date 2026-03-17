import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/lyfi_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/color_chart.dart';
import 'package:borneo_app/core/utils/hex_color.dart';
import 'package:borneo_app/shared/widgets/value_listenable_builders.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';

class ManualRunningChart extends StatelessWidget {
  const ManualRunningChart({super.key});

  List<BarChartGroupData> buildGroupDataItems(BuildContext context) {
    final vm = context.read<LyfiViewModel>();
    if (vm.lyfiDeviceInfo.channels.isEmpty || vm.channels.isEmpty) {
      return [];
    }
    int index = 0;
    return vm.lyfiDeviceInfo.channels.map((ch) {
      final channel = vm.channels[index];
      final g = makeGroupData(context, ch, index, channel.value.toDouble());
      index++;
      return g;
    }).toList();
  }

  BarChartGroupData makeGroupData(BuildContext context, LyfiChannelInfo ch, int x, double y) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = HexColor.fromHex(ch.color);
    // Compute a compressed gradient where small values remain light.
    // Define the full (100%) gradient as: lightStart -> primaryColor (darker).
    // For current value (x%), only show 0..x% of that gradient: lightStart -> colorAt(x%).
    final lightStart = Color.lerp(primaryColor, Colors.white, 0.7)!; // lighter start
    final double fraction = (y / kLyfiBrightnessMax).clamp(0.0, 1.0).toDouble();
    final currentEndColor = Color.lerp(lightStart, primaryColor, fraction)!;
    return BarChartGroupData(
      groupVertically: false,
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          borderRadius: BorderRadius.zero,
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            // Start from light -> progress toward primary only up to x% to keep small values light.
            colors: [lightStart, currentEndColor],
          ),
          width: 20,
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            fromY: 0,
            toY: kLyfiBrightnessMax.toDouble(),
            color: LyfiColorChart.computeBarBackColor(context, primaryColor),
          ),
        ),
      ],
    );
  }

  Widget buildTitles(BuildContext context, double value) {
    final vm = context.read<LyfiViewModel>();
    final index = value.toInt();
    final ch = vm.lyfiDeviceInfo.channels[index];
    return Text(
      context.translate(ch.name),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<LyfiViewModel>();
    assert(vm.isOnline);
    return MultiValueListenableBuilder<int>(
      valueNotifiers: vm.channels,
      builder: (context, values, _) => LyfiColorChart(
        BarChartData(
          alignment: BarChartAlignment.spaceEvenly,
          maxY: kLyfiBrightnessMax.toDouble(),
          minY: 0.0,
          baselineY: 1024,
          barGroups: buildGroupDataItems(context),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, _) => buildTitles(context, value)),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: true),
          gridData: FlGridData(show: false),
        ),
        duration: Duration(seconds: 1),
      ),
    );
  }
}
