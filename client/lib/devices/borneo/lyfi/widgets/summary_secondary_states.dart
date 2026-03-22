import 'package:borneo_app/devices/borneo/lyfi/view_models/summary_device_view_model.dart';
import 'package:borneo_app/devices/view_models/abstract_device_summary_view_model.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:provider/provider.dart';

class LyfiSummaryStateLabel extends StatelessWidget {
  const LyfiSummaryStateLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AbstractDeviceSummaryViewModel, LyfiState?>(
      selector: (_, vm) => (vm as LyfiSummaryDeviceViewModel).ledState,
      builder: (context, state, child) =>
          Text(_stateText(context, state), style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class LyfiSummaryModeLabel extends StatelessWidget {
  const LyfiSummaryModeLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AbstractDeviceSummaryViewModel, LyfiMode?>(
      selector: (_, vm) => (vm as LyfiSummaryDeviceViewModel).ledMode,
      builder: (context, mode, child) => Text(_modeText(context, mode), style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

String _modeText(BuildContext context, LyfiMode? mode) {
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

String _stateText(BuildContext context, LyfiState? state) => switch (state) {
  LyfiState.normal => context.translate('NORM'),
  LyfiState.dimming => context.translate('DIMM'),
  LyfiState.temporary => context.translate('TEMP'),
  LyfiState.preview => context.translate('PREV'),
  _ => '-',
};
