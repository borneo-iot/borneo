import 'package:borneo_app/devices/borneo/lyfi/views/brightness_slider_list.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/widgets/sun_running_chart.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';

import 'package:provider/provider.dart';

import '../../view_models/editor/sun_editor_view_model.dart';

class SunEditorView extends StatelessWidget {
  final SunEditorViewModel viewModel;
  const SunEditorView({super.key, required this.viewModel});

  Widget buildSliders(BuildContext context) {
    return Selector<SunEditorViewModel, ({bool isInitialized, bool canChangeColor})>(
      selector: (_, editor) => (isInitialized: editor.isInitialized, canChangeColor: editor.canChangeColor),
      builder: (context, editor, _) {
        if (!editor.isInitialized) {
          return const SizedBox.shrink();
        }

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: BrightnessSliderList(context.read<SunEditorViewModel>(), disabled: !editor.canChangeColor),
          ),
        );
      },
    );
  }

  Widget buildTitles(BuildContext context, SunEditorViewModel vm, double value) {
    if (vm.isInitialized) {
      final index = value.toInt();
      final ch = vm.deviceInfo.channels[index];
      return Text(ch.name, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor));
    } else {
      return Text(context.translate("N/A"));
    }
  }

  Widget buildGraph(BuildContext context) {
    return Selector<SunEditorViewModel, ({List<LyfiChannelInfo> channels, ScheduleTable instants})>(
      selector: (context, vm) => (channels: vm.parent.lyfiDeviceInfo.channels, instants: vm.sunInstants),
      builder: (context, selected, _) => RepaintBoundary(
        child: SunRunningChart(sunInstants: selected.instants, channelInfoList: selected.channels),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: viewModel,
      builder: (context, child) => Column(
        spacing: 16,
        children: [
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.all(0),
            child: SizedBox(height: 150, child: buildGraph(context)),
          ),
          Expanded(child: buildSliders(context)),
        ],
      ),
    );
  }
}
