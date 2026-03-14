import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/moon_editor_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/moon_view_model.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/widgets/moon_running_chart.dart';
import 'package:borneo_app/shared/widgets/app_bar_apply_button.dart';
import 'package:borneo_app/shared/widgets/screen_top_rounded_container.dart';
import 'package:borneo_app/features/devices/views/device_availability_guard.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';
import 'package:logger/logger.dart';

import 'package:provider/provider.dart';
import 'brightness_slider_list.dart';

@immutable
class _MoonGraphState {
  final bool isInitialized;
  final List<LyfiChannelInfo> channels;
  final ScheduleTable instants;
  final int signature;

  const _MoonGraphState({
    required this.isInitialized,
    required this.channels,
    required this.instants,
    required this.signature,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _MoonGraphState && other.isInitialized == isInitialized && other.signature == signature;
  }

  @override
  int get hashCode => Object.hash(isInitialized, signature);
}

class MoonScreen extends StatelessWidget {
  final String deviceID;
  const MoonScreen({required this.deviceID, super.key});

  _MoonGraphState _buildGraphState(MoonEditorViewModel editor) {
    final channels = editor.deviceInfo.channels;
    final instants = editor.moonInstants;
    final signature = Object.hashAll([
      channels.length,
      for (final channel in channels) Object.hash(channel.name, channel.color, channel.wavelength),
      instants.length,
      for (final instant in instants) Object.hash(instant.instant, Object.hashAll(instant.color)),
    ]);

    return _MoonGraphState(
      isInitialized: editor.isInitialized,
      channels: channels,
      instants: instants,
      signature: signature,
    );
  }

  Widget buildGraph(BuildContext context) {
    return Selector<MoonEditorViewModel, _MoonGraphState>(
      selector: (context, editor) => _buildGraphState(editor),
      builder: (context, selected, _) => !selected.isInitialized
          ? const SizedBox.shrink()
          : RepaintBoundary(
              child: MoonRunningChart(moonInstants: selected.instants, channelInfoList: selected.channels),
            ),
    );
  }

  Widget buildSliders(BuildContext context) {
    return Selector<MoonViewModel, ({bool enabled, bool canEdit})>(
      selector: (_, vm) => (enabled: vm.enabled, canEdit: vm.canEdit),
      builder: (context, state, _) => ScreenTopRoundedContainer(
        color: Theme.of(context).colorScheme.surfaceContainer,
        padding: EdgeInsets.fromLTRB(0, 24, 0, 0),
        child: SafeArea(
          child: SingleChildScrollView(
            child: BrightnessSliderList(
              context.read<MoonEditorViewModel>(),
              disabled: !state.enabled || !state.canEdit,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = MoonViewModel(
      deviceManager: context.read<IDeviceManager>(),
      globalEventBus: context.read<EventBus>(),
      notification: context.read<IAppNotificationService>(),
      wotThing: context.read<IDeviceManager>().getWotThing(deviceID),
      gt: context.read<GettextLocalizations>(),
      logger: context.read<Logger>(),
    );
    return ChangeNotifierProvider(
      create: (cb) => vm,
      builder: (context, child) {
        return DeviceAvailabilityGuard<MoonViewModel>(
          viewModel: vm,
          child: ChangeNotifierProvider<MoonEditorViewModel>.value(
            value: vm.editor,
            child: Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(
                  title: Text(context.translate('Moonlight')),
                  actions: [
                    Selector<MoonViewModel, ({bool enabled, bool canToggle})>(
                      selector: (_, vm) => (enabled: vm.enabled, canToggle: !vm.isBusy && vm.isOnline && vm.isOn),
                      builder: (context, state, _) => Switch.adaptive(
                        value: state.enabled,
                        onChanged: state.canToggle ? context.read<MoonViewModel>().setEnabled : null,
                      ),
                    ),
                    ListenableBuilder(
                      listenable: Listenable.merge([
                        context.read<MoonViewModel>(),
                        context.read<MoonEditorViewModel>(),
                      ]),
                      builder: (context, _) {
                        final vm = context.read<MoonViewModel>();
                        return AppBarApplyButton(
                          label: context.translate('Apply'),
                          onPressed: vm.canSubmit ? () => onSubmit(vm, context) : null,
                        );
                      },
                    ),
                  ],
                ),
                body: FutureBuilder(
                  future: vm.initFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      if (!vm.isAvailable) {
                        return const SizedBox.shrink();
                      }
                      return Center(child: Text('Error: ${snapshot.error}'));
                    } else {
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          return Column(
                            spacing: 8,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              SizedBox(height: 180, child: buildGraph(context)),
                              Expanded(child: buildSliders(context)),
                            ],
                          );
                        },
                      );
                    }
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> onSubmit(MoonViewModel vm, BuildContext context) async {
    final didSubmit = await vm.submitToDevice();
    if (!didSubmit || !context.mounted) {
      return;
    }

    Provider.of<IAppNotificationService>(
      context,
      listen: false,
    ).showSuccess(context.translate('Update moon settings succeed.'));
    Navigator.of(context).pop();
  }
}
