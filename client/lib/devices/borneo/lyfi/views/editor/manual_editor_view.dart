import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/brightness_slider_list.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/color_chart.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/spectrum_chart.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:flutter/material.dart';

import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import 'package:borneo_app/core/utils/hex_color.dart';
import 'package:borneo_app/shared/widgets/value_listenable_builders.dart';
import '../../view_models/editor/manual_editor_view_model.dart';

class ManualEditorView extends StatelessWidget {
  final ManualEditorViewModel viewModel;
  const ManualEditorView({super.key, required this.viewModel});

  Widget buildSliders(BuildContext context) {
    return Selector<ManualEditorViewModel, ({bool isInitialized, bool canChangeColor})>(
      selector: (context, vm) => (canChangeColor: vm.canChangeColor, isInitialized: vm.isInitialized),
      builder: (context, props, _) {
        if (props.isInitialized) {
          return SingleChildScrollView(
            child: BrightnessSliderList(context.read<ManualEditorViewModel>(), disabled: !props.canChangeColor),
          );
        } else {
          return const SizedBox.shrink();
        }
      },
    );
  }

  List<BarChartGroupData> buildGroupDataItems(BuildContext context, ManualEditorViewModel vm) {
    int index = 0;
    if (vm.isInitialized) {
      return vm.deviceInfo.channels.map((ch) {
        final channel = vm.channels[index];
        final g = makeGroupData(context, ch, index, channel.value.toDouble());
        index++;
        return g;
      }).toList();
    } else {
      return [];
    }
  }

  BarChartGroupData makeGroupData(BuildContext context, LyfiChannelInfo ch, int x, double y) {
    final primaryColor = HexColor.fromHex(ch.color);
    final barBackColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    // Use a compressed gradient where small values remain light.
    // Full gradient (100%) is lightStart -> primaryColor; for x%, show only 0..x%.
    final lightStart = Color.lerp(primaryColor, Colors.white, 0.7)!;
    final double fraction = (y / kLyfiBrightnessMax).clamp(0.0, 1.0).toDouble();
    final currentEndColor = Color.lerp(lightStart, primaryColor, fraction)!;
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          borderSide: BorderSide(color: primaryColor),
          borderRadius: BorderRadius.circular(4),
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [lightStart, currentEndColor],
          ),
          width: 20,
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            fromY: 0,
            toY: kLyfiBrightnessMax.toDouble(),
            color: barBackColor,
          ),
        ),
      ],
    );
  }

  Widget buildTitles(BuildContext context, ManualEditorViewModel vm, double value) {
    if (vm.isInitialized) {
      final index = value.toInt();
      final ch = vm.deviceInfo.channels[index];
      return Text(
        ch.name,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.80)),
      );
    } else {
      return Text("N/A");
    }
  }

  Widget buildGraph(BuildContext context) {
    return Consumer<ManualEditorViewModel>(
      builder: (context, vm, _) {
        if (canRenderSpectrumChart(vm.deviceInfo.channels)) {
          return LyfiSpectrumChart(channels: vm.deviceInfo.channels, brightnessValues: vm.channels);
        }
        return MultiValueListenableBuilder<int>(
          valueNotifiers: vm.channels,
          builder: (context, values, _) => LyfiColorChart(
            BarChartData(
              barGroups: buildGroupDataItems(context, vm),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) => buildTitles(context, vm, value),
                  ),
                ),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(enabled: true),
              gridData: FlGridData(show: false),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: viewModel,
      builder: (context, child) => Column(
        spacing: 24,
        children: [
          SizedBox(
            height: 150,
            child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: buildGraph(context)),
          ),
          Expanded(child: buildSliders(context)),
        ],
      ),
    );
  }
}
