import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/easy_setup_screen.dart';
import 'package:borneo_app/core/infrastructure/duration.dart';
import 'package:borneo_app/core/infrastructure/time_of_day.dart';
import 'package:borneo_common/duration_ext.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:borneo_app/routes/platform_page_route.dart';

import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/schedule_editor_view_model.dart';
import 'package:borneo_app/core/utils/hex_color.dart';
import '../brightness_slider_list.dart';
import '../widgets/lyfi_time_line_chart.dart';

const Duration _kScheduleChartAnimationDuration = Duration(milliseconds: 20);

@immutable
class _ScheduleChartState {
  final List<ScheduleEntryViewModel> entries;
  final List<LyfiChannelInfo> channelInfo;
  final Duration? currentTime;
  final double minX;
  final double maxX;
  final double maxScale;
  final int signature;

  const _ScheduleChartState({
    required this.entries,
    required this.channelInfo,
    required this.currentTime,
    required this.minX,
    required this.maxX,
    required this.maxScale,
    required this.signature,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _ScheduleChartState &&
        other.signature == signature &&
        other.currentTime == currentTime &&
        other.minX == minX &&
        other.maxX == maxX &&
        other.maxScale == maxScale;
  }

  @override
  int get hashCode => Object.hash(signature, currentTime, minX, maxX, maxScale);
}

class ScheduleEditorView extends StatelessWidget {
  final ScheduleEditorViewModel viewModel;
  const ScheduleEditorView({super.key, required this.viewModel});

  _ScheduleChartState _buildChartState(ScheduleEditorViewModel vm) {
    const minSpanSeconds = 3 * 3600.0;
    final entries = vm.entries.toList(growable: false);
    final sortedEntries = entries.toList()..sort((a, b) => a.instant.compareTo(b.instant));
    double minX = 0.0;
    double maxX = 24 * 3600.0;
    if (sortedEntries.isNotEmpty) {
      final hasCrossDay = sortedEntries.any((e) => e.instant.inHours >= 24);
      if (hasCrossDay) {
        minX = sortedEntries.first.instant.inSeconds.toDouble();
        maxX = sortedEntries.last.instant.inSeconds.toDouble();
        if (maxX - minX < minSpanSeconds) {
          maxX = minX + minSpanSeconds;
        }
      }
    }
    final maxScale = ((maxX - minX) / minSpanSeconds).clamp(1.0, double.infinity);
    final signature = Object.hashAll([
      vm.deviceInfo.channels.length,
      for (final channel in vm.deviceInfo.channels) Object.hash(channel.name, channel.color, channel.wavelength),
      entries.length,
      for (final entry in entries) Object.hash(entry.instant, Object.hashAll(entry.channels)),
      vm.currentEntry?.instant,
      minX,
      maxX,
      maxScale,
    ]);
    return _ScheduleChartState(
      entries: entries,
      channelInfo: vm.deviceInfo.channels,
      currentTime: vm.currentEntry?.instant,
      minX: minX,
      maxX: maxX,
      maxScale: maxScale,
      signature: signature,
    );
  }

  ({
    bool canAddInstant,
    bool canRemoveCurrentInstant,
    bool canClearInstants,
    bool canPrevInstant,
    bool canNextInstant,
    Duration? currentInstant,
  })
  _buildBottomActionsState(ScheduleEditorViewModel vm) {
    return (
      canAddInstant: vm.canAddInstant,
      canRemoveCurrentInstant: vm.canRemoveCurrentInstant,
      canClearInstants: vm.canClearInstants,
      canPrevInstant: vm.canPrevInstant,
      canNextInstant: vm.canNextInstant,
      currentInstant: vm.currentEntry?.instant,
    );
  }

  Future<Duration?> showNewInstantDialog(BuildContext context, TimeOfDay initialTime) async {
    // bool isNextDay = false;
    final selectedTime = await showTimePicker(
      initialTime: initialTime,
      context: context,
      confirmText: context.translate('Add time point'),
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    return selectedTime?.toDuration();
  }

  Widget bottomTitleWidgets(BuildContext context, double value, TitleMeta meta) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(97),
    );

    final duration = Duration(seconds: value.toInt());
    return SideTitleWidget(
      space: 0,
      meta: meta,
      fitInside: SideTitleFitInsideData.fromTitleMeta(meta, distanceFromEdge: 0, enabled: false),
      child: Text(duration.toHH(), style: style, textAlign: TextAlign.right),
    );
  }

  Widget leftTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(fontSize: 10, color: Colors.white54);
    return SideTitleWidget(
      meta: meta,
      child: Text('${value + 0.5}', style: style),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: viewModel,
      builder: (context, child) {
        return SafeArea(
          top: false,
          child: Column(
            children: [
              // The chart
              SizedBox(
                height: 150,
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  padding: EdgeInsets.fromLTRB(8, 24, 8, 0),
                  child: Selector<ScheduleEditorViewModel, _ScheduleChartState>(
                    selector: (_, vm) => _buildChartState(vm),
                    builder: (context, chart, child) {
                      final vm = context.read<ScheduleEditorViewModel>();
                      return _ScheduleRunningChart(
                        entries: chart.entries,
                        channelInfo: chart.channelInfo,
                        minX: chart.minX,
                        maxX: chart.maxX,
                        currentTime: chart.currentTime,
                        maxScale: chart.maxScale,
                        lineTouchData: LineTouchData(
                          handleBuiltInTouches: true,
                          touchTooltipData: LineTouchTooltipData(getTooltipItems: (_) => []),
                          touchCallback: (event, response) async {
                            if (response == null || response.lineBarSpots == null || response.lineBarSpots!.isEmpty) {
                              return;
                            }
                            final spot = response.lineBarSpots!.first;
                            final x = spot.x.toInt();
                            final idx = vm.entries.indexWhere((e) => e.instant.inSeconds == x);
                            if (idx != -1) {
                              await vm.setCurrentEntryAndSyncDimmingColor(idx);
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),
              // Controls
              Expanded(
                child: Selector<ScheduleEditorViewModel, bool>(
                  selector: (_, editor) => editor.canChangeColor,
                  builder: (_, canChangeColor, _) => SingleChildScrollView(
                    child: BrightnessSliderList(
                      context.read<ScheduleEditorViewModel>(),
                      disabled: !canChangeColor,
                      padding: EdgeInsets.all(0),
                    ),
                  ),
                ),
              ),

              // Bottom buttons
              Selector<
                ScheduleEditorViewModel,
                ({
                  bool canAddInstant,
                  bool canRemoveCurrentInstant,
                  bool canClearInstants,
                  bool canPrevInstant,
                  bool canNextInstant,
                  Duration? currentInstant,
                })
              >(
                selector: (_, vm) => _buildBottomActionsState(vm),
                builder: (context, actions, child) {
                  final vm = context.read<ScheduleEditorViewModel>();
                  return Card(
                    margin: EdgeInsets.fromLTRB(8, 0, 8, 8),
                    elevation: 1,
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: Padding(
                      padding: EdgeInsetsGeometry.fromLTRB(8, 16, 8, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Easy Setup
                          _BottomActionButton(
                            icon: Icons.auto_fix_high_outlined,
                            label: context.translate('Easy'),
                            color: Theme.of(context).colorScheme.primary,
                            onPressed: () async {
                              await vm.easySetupEnter();
                              if (context.mounted) {
                                final route = platformPageRoute(builder: (context) => EasySetupScreen(vm));
                                final applied = await Navigator.push(context, route);
                                if (applied == true) {
                                  await vm.easySetupFinish();
                                  // stay on the Dimming screen (do not pop the parent route)
                                }
                              }
                            },
                          ),
                          // Add
                          _BottomActionButton(
                            icon: Icons.add_outlined,
                            label: context.translate('Add'),
                            color: actions.canAddInstant
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).disabledColor,
                            onPressed: actions.canAddInstant
                                ? () async {
                                    final initialTime =
                                        (actions.currentInstant ?? Duration(hours: 6, minutes: 30)) +
                                        ScheduleEditorViewModel.defaultInstantSpan;
                                    final safeInitialTime = Duration(
                                      hours: initialTime.inHours % 24,
                                      minutes: initialTime.inMinutes % 60,
                                    );
                                    final selectedTime = await showNewInstantDialog(
                                      context,
                                      safeInitialTime.toTimeOfDay(),
                                    );
                                    if (selectedTime != null) {
                                      vm.addInstant(selectedTime);
                                    }
                                  }
                                : null,
                          ),
                          // Remove
                          _BottomActionButton(
                            icon: Icons.remove,
                            label: context.translate('Remove'),
                            color: actions.canRemoveCurrentInstant
                                ? Theme.of(context).colorScheme.secondary
                                : Theme.of(context).disabledColor,
                            onPressed: actions.canRemoveCurrentInstant ? vm.removeCurrentInstant : null,
                          ),
                          // Clear
                          _BottomActionButton(
                            icon: Icons.clear,
                            label: context.translate('Clear'),
                            color: actions.canClearInstants
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).disabledColor,
                            onPressed: actions.canClearInstants ? () => _confirmClearEntries(context, vm) : null,
                          ),
                          // Prev
                          _BottomActionButton(
                            icon: Icons.skip_previous_outlined,
                            label: context.translate('Prev'),
                            color: actions.canPrevInstant
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).disabledColor,
                            onPressed: actions.canPrevInstant ? vm.prevInstant : null,
                          ),
                          // Next
                          _BottomActionButton(
                            icon: Icons.skip_next_outlined,
                            label: context.translate('Next'),
                            color: actions.canNextInstant
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).disabledColor,
                            onPressed: actions.canNextInstant ? vm.nextInstant : null,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmClearEntries(BuildContext context, ScheduleEditorViewModel vm) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(context.translate('Confirmation'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              Text(context.translate('Are you sure you want to remove all schedule entries?')),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                    child: Text(context.translate('Cancel')),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                    child: Text(context.translate('Confirm')),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ).then((value) {
      if (value != null && value) {
        vm.clearEntries();
      } else {
        //
      }
    });
  }
}

class _ScheduleRunningChart extends StatefulWidget {
  final List<ScheduleEntryViewModel> entries;
  final List<LyfiChannelInfo> channelInfo;
  final double minX;
  final double maxX;
  final Duration? currentTime;
  final double maxScale;
  final LineTouchData lineTouchData;

  const _ScheduleRunningChart({
    required this.entries,
    required this.channelInfo,
    required this.minX,
    required this.maxX,
    required this.currentTime,
    required this.maxScale,
    required this.lineTouchData,
  });

  @override
  State<_ScheduleRunningChart> createState() => _ScheduleRunningChartState();
}

class _ScheduleRunningChartState extends State<_ScheduleRunningChart> {
  late List<LineChartBarData> _lineData;
  late int _lineDataSignature;

  @override
  void initState() {
    super.initState();
    _refreshLineData();
  }

  @override
  void didUpdateWidget(covariant _ScheduleRunningChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _buildLineDataSignature(widget.entries, widget.channelInfo);
    if (signature != _lineDataSignature) {
      _refreshLineData();
    }
  }

  void _refreshLineData() {
    _lineDataSignature = _buildLineDataSignature(widget.entries, widget.channelInfo);
    _lineData = _buildLineData(widget.entries, widget.channelInfo);
  }

  int _buildLineDataSignature(List<ScheduleEntryViewModel> entries, List<LyfiChannelInfo> channelInfo) {
    return Object.hashAll([
      channelInfo.length,
      for (final channel in channelInfo) Object.hash(channel.name, channel.color, channel.wavelength),
      entries.length,
      for (final entry in entries) Object.hash(entry.instant, Object.hashAll(entry.channels)),
    ]);
  }

  List<LineChartBarData> _buildLineData(List<ScheduleEntryViewModel> entries, List<LyfiChannelInfo> channelInfo) {
    final sortedEntries = entries.toList()..sort((a, b) => a.instant.compareTo(b.instant));
    final series = <LineChartBarData>[];
    for (int channelIndex = 0; channelIndex < channelInfo.length; channelIndex++) {
      final spots = <FlSpot>[];
      for (final entry in sortedEntries) {
        spots.add(FlSpot(entry.instant.inSeconds.toDouble(), entry.channels[channelIndex].toDouble()));
      }
      series.add(
        LineChartBarData(
          isCurved: false,
          barWidth: 1.5,
          color: HexColor.fromHex(channelInfo[channelIndex].color),
          dotData: const FlDotData(show: true),
          spots: spots,
        ),
      );
    }
    return series;
  }

  @override
  Widget build(BuildContext context) {
    return LyfiTimeLineChart(
      lineBarsData: _lineData,
      minX: widget.minX,
      maxX: widget.maxX,
      minY: 0,
      maxY: kLyfiBrightnessMax.toDouble(),
      currentTime: widget.currentTime,
      allowZoom: true,
      maxScale: widget.maxScale,
      lineTouchData: widget.lineTouchData,
      animationDuration: _kScheduleChartAnimationDuration,
    );
  }
}

class _BottomActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  const _BottomActionButton({required this.icon, required this.label, required this.color, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = onPressed != null;
    final Color sysDisabled = theme.colorScheme.onSurface.withValues(alpha: 0.38);
    final Color borderColor = isEnabled ? color : sysDisabled;
    final Color iconColor = isEnabled ? color : sysDisabled;
    final Color iconBgColor = isEnabled ? theme.colorScheme.surfaceBright : Colors.transparent;
    final Color labelColor = isEnabled ? Theme.of(context).colorScheme.onSurface : sysDisabled;
    final TextStyle? labelStyle = theme.textTheme.labelSmall?.copyWith(color: labelColor);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 48,
              width: 48,
              child: OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  side: BorderSide(color: borderColor, width: 1.5),
                  foregroundColor: iconColor,
                  backgroundColor: iconBgColor,
                  padding: EdgeInsets.zero,
                  shadowColor: Colors.transparent,
                  disabledForegroundColor: sysDisabled,
                  disabledBackgroundColor: Colors.transparent,
                ),
                child: Icon(icon, size: 24, color: iconColor),
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
