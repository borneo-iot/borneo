import 'package:borneo_app/shared/widgets/app_bar_apply_button.dart';
import 'package:borneo_app/shared/widgets/screen_top_rounded_container.dart';
import 'package:borneo_common/duration_ext.dart';
import 'package:flutter/material.dart';

import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/schedule_editor_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/ieditor.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:progressive_time_picker/progressive_time_picker.dart';
import 'package:provider/provider.dart';

import 'brightness_slider_list.dart';

extension _DurationExtension on Duration {
  PickedTime toPickedTime() {
    int totalMinutes = inMinutes;
    int hours = totalMinutes ~/ 60;
    int minutes = totalMinutes % 60;
    return PickedTime(h: hours, m: minutes);
  }
}

class EasySetupScreen extends StatelessWidget {
  final ScheduleEditorViewModel editor;

  const EasySetupScreen(this.editor, {super.key});

  final clockTimeFormat = ClockTimeFormat.twentyFourHours;
  final clockIncrementTimeFormat = ClockIncrementTimeFormat.thirtyMin;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: editor,
      builder: (context, child) {
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop) {
              return;
            }
            await editor.easySetupViewModel.restoreIfNeeded(editor);
            editor.easySetupViewModel.endSession();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(context.translate('Easy Setup')),
              actions: [
                AppBarApplyButton(
                  label: context.translate('Apply'),
                  onPressed: () {
                    editor.easySetupViewModel.markApplied();
                    if (Navigator.canPop(context)) {
                      Navigator.of(context).pop(true);
                    } else {
                      Navigator.of(context).pop(true);
                    }
                  },
                ),
              ],
            ),
            body: Container(color: Theme.of(context).colorScheme.surface, child: child),
          ),
        );
      },
      child: buildBody(context),
    );
  }

  Widget buildBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: buildList(context),
    );
  }

  List<Widget> buildList(BuildContext context) {
    final listenableDuration = Listenable.merge([
      editor.easySetupViewModel.startTime,
      editor.easySetupViewModel.endTime,
    ]);
    return [
      AspectRatio(
        aspectRatio: 1.0,
        child: TimePicker(
          drawInitHandlerOnTop: true,
          primarySectors: clockTimeFormat.value,
          secondarySectors: clockTimeFormat.value * 2,
          decoration: TimePickerDecoration(
            baseColor: Theme.of(context).colorScheme.surfaceContainerLow,
            pickerBaseCirclePadding: 0,
            sweepDecoration: TimePickerSweepDecoration(
              pickerStrokeWidth: 48.0,
              pickerColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
              showConnector: false,
            ),
            initHandlerDecoration: TimePickerHandlerDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
              radius: 20.0,
              icon: Icon(Icons.wb_sunny_outlined, size: 24.0, color: Theme.of(context).colorScheme.onInverseSurface),
            ),
            endHandlerDecoration: TimePickerHandlerDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
              radius: 20.0,
              icon: Icon(Icons.mode_night_outlined, size: 24.0, color: Theme.of(context).colorScheme.onInverseSurface),
            ),
            primarySectorsDecoration: TimePickerSectorDecoration(
              color: Theme.of(context).colorScheme.onSurface,
              width: 1.0,
              size: 4.0,
              radiusPadding: 0.0,
            ),
            secondarySectorsDecoration: TimePickerSectorDecoration(
              color: Theme.of(context).colorScheme.onSurface,
              width: 1.0,
              size: 2.0,
              radiusPadding: 0,
            ),
            clockNumberDecoration: TimePickerClockNumberDecoration(
              defaultTextColor: Theme.of(context).colorScheme.onSurface,
              positionFactor: 0.5,
              showNumberIndicators: true,
              clockTimeFormat: clockTimeFormat,
              clockIncrementTimeFormat: clockIncrementTimeFormat,
              clockIncrementHourFormat: ClockIncrementHourFormat.three,
            ),
          ),
          initTime: editor.easySetupViewModel.startTime.value.toPickedTime(),
          endTime: editor.easySetupViewModel.endTime.value.toPickedTime(),
          onSelectionChange: (start, end, isDisableRange) {
            editor.easySetupViewModel.startTime.value = Duration(hours: start.h, minutes: start.m);
            editor.easySetupViewModel.endTime.value = Duration(hours: end.h, minutes: end.m);
          },
          onSelectionEnd: (start, end, isDisableRange) async {
            editor.easySetupViewModel.startTime.value = Duration(hours: start.h, minutes: start.m);
            editor.easySetupViewModel.endTime.value = Duration(hours: end.h, minutes: end.m);
          },
          child: Column(
            spacing: 8,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                spacing: 1,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AnimatedBuilder(
                    animation: listenableDuration,
                    builder: (context, child) => Text(
                      (editor.easySetupViewModel.duration.inMinutes ~/ 60).toString().padLeft(2, '0'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  Text(
                    context.translate("Hrs"),
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.outline),
                  ),
                  SizedBox(width: 4),
                  AnimatedBuilder(
                    animation: listenableDuration,
                    builder: (context, child) => Text(
                      (editor.easySetupViewModel.duration.inMinutes % 60).toString().padLeft(2, '0'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  Text(
                    context.translate("Mins"),
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              ),
              Row(
                spacing: 1,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ValueListenableBuilder<Duration>(
                    valueListenable: editor.easySetupViewModel.startTime,
                    builder: (context, value, child) {
                      return Text(
                        editor.easySetupViewModel.startTime.value.toHHMM(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_right_alt_outlined, size: 24, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 2),
                  ValueListenableBuilder<Duration>(
                    valueListenable: editor.easySetupViewModel.endTime,
                    builder: (context, value, child) {
                      return Text(
                        editor.easySetupViewModel.endTime.value.toHHMM(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      );
                    },
                  ),
                ],
              ),
              /*
                  Text(
                    '${intl.NumberFormat('00').format(intervalBedTime.h)}Hr ${intl.NumberFormat('00').format(intervalBedTime.m)}Min',
                    style: TextStyle(
                      fontSize: 12.0,
                      color: isSleepGoal ? Color(0xFF3CDAF7) : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  */
            ],
          ),
        ),
      ),
      Expanded(
        child: Selector<ScheduleEditorViewModel, bool>(
          selector: (_, editor) => editor.canEdit,
          builder: (context, canEdit, child) {
            // Use a temporary editor adapter so Easy Setup slider changes are
            // local to the EasySetupViewModel until the user taps Apply.
            final viewModel = context.read<ScheduleEditorViewModel>();
            final tempEditor = _EasySetupTempEditor(viewModel);
            return ScreenTopRoundedContainer(
              padding: EdgeInsets.fromLTRB(0, 24, 0, 0),
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: SafeArea(
                child: SingleChildScrollView(
                  child: BrightnessSliderList(
                    tempEditor,
                    disabled: !canEdit,
                    padding: EdgeInsets.fromLTRB(0, 24, 0, 16),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ];
  }
}

class _EasySetupTempEditor extends ChangeNotifier implements IEditor {
  final ScheduleEditorViewModel _parent;

  _EasySetupTempEditor(this._parent);

  bool get _hasEasyChannels => _parent.easySetupViewModel.channels.isNotEmpty;

  @override
  bool get canEdit => _parent.canEdit;

  @override
  bool get isChanged => false;

  @override
  Future<void> save({CancellationToken? cancelToken}) async {}

  @override
  Future<void> initialize({CancellationToken? cancelToken}) async {}

  @override
  Future<void> updateChannelValue(int index, int value) async {
    if (_hasEasyChannels && index >= 0 && index < _parent.easySetupViewModel.channels.length) {
      _parent.easySetupViewModel.channels[index].value = value;

      // Provide a live preview of the new color values while the user adjusts
      // sliders, without committing the changes to the schedule until Apply.
      if (!_parent.parent.isSuspectedOffline && _parent.parent.boundDevice != null) {
        final newColor = _parent.easySetupViewModel.channelValues;
        _parent.colorChangeRateLimiter.call(() {
          if (_parent.parent.isSuspectedOffline || _parent.parent.boundDevice == null) return;
          _parent.lyfiThing.setProperty('color', newColor);
        });
      }
    }
  }

  @override
  int get availableChannelCount => _parent.availableChannelCount;

  @override
  LyfiDeviceInfo get deviceInfo => _parent.deviceInfo;

  @override
  List<ValueNotifier<int>> get channels => _hasEasyChannels ? _parent.easySetupViewModel.channels : _parent.channels;
}
