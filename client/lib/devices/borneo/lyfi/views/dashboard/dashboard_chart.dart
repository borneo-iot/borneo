import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../view_models/lyfi_view_model.dart';
import '../widgets/manual_running_chart.dart';
import '../widgets/schedule_running_chart.dart';
import '../widgets/sun_running_chart.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';

class DashboardChart extends StatelessWidget {
  const DashboardChart({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<LyfiViewModel, ({LyfiMode mode, LyfiState? state, bool isOn})>(
      selector: (_, vm) => (mode: vm.mode, state: vm.ledState, isOn: vm.isOn),
      builder: (context, props, _) {
        final Widget widget = switch (props.mode) {
          LyfiMode.manual => ManualRunningChart(),
          LyfiMode.scheduled => ScheduleRunningChart(),
          LyfiMode.sun => Selector<LyfiViewModel, ({List<LyfiChannelInfo> channels, List<ScheduledInstant> instants})>(
            selector: (context, vm) => (channels: vm.lyfiDeviceInfo.channels, instants: vm.sunInstants),
            builder: (context, selected, _) =>
                SunRunningChart(sunInstants: selected.instants, channelInfoList: selected.channels),
          ),
        };

        return AnimatedSwitcher(
          duration: Duration(milliseconds: 100),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.1),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutQuart)),
              child: child,
            );
          },
          child: widget,
        );
      },
    );
  }
}
