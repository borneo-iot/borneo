import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:provider/provider.dart';

import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';

import '../../view_models/lyfi_view_model.dart';
import '../widgets/manual_running_chart.dart';
import '../widgets/schedule_running_chart.dart';
import '../widgets/sun_running_chart.dart';

class DashboardChart extends StatelessWidget {
  const DashboardChart({super.key});

  @override
  Widget build(BuildContext context) {
    // only rebuild when online status changes (taking suspectedOffline into account)
    return Selector<LyfiViewModel, bool>(
      selector: (_, vm) => vm.isOnline && !vm.isSuspectedOffline,
      builder: (context, isActuallyOnline, _) {
        if (!isActuallyOnline) {
          return Container(
            constraints: const BoxConstraints(minHeight: 200),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: Icon(
                      Icons.wifi_off,
                      size: null,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                    ),
                  ),
                ),
                Text(
                  context.translate('Device Offline'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  context.translate('Please check device connection'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          );
        } else {
          // device is online, show charts with finer selectors
          return Selector<LyfiViewModel, LyfiMode>(
            selector: (_, vm) => vm.mode,
            builder: (context, mode, _) {
              final chartWidget = switch (mode) {
                LyfiMode.manual => ManualRunningChart(),
                LyfiMode.scheduled => ScheduleRunningChart(),
                LyfiMode.sun => Selector<LyfiViewModel, ({List<LyfiChannelInfo> channels, ScheduleTable instants})>(
                  selector: (context, vm) => (channels: vm.lyfiDeviceInfo.channels, instants: vm.sunInstants),
                  builder: (context, selected, _) =>
                      SunRunningChart(sunInstants: selected.instants, channelInfoList: selected.channels),
                ),
              };

              return AnimatedSwitcher(
                duration: Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.0, 0.1),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutQuart)),
                    child: child,
                  );
                },
                child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 200), child: chartWidget),
              );
            },
          );
        }
      },
    );
  }
}
