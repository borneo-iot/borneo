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

class MoonScreen extends StatelessWidget {
  final String deviceID;
  const MoonScreen({required this.deviceID, super.key});

  Widget buildGraph(BuildContext context, MoonViewModel vm) {
    return Selector<MoonViewModel, ({List<LyfiChannelInfo> channels, ScheduleTable instants})>(
      selector: (context, vm) => (channels: vm.editor.deviceInfo.channels, instants: vm.editor.moonInstants),
      builder: (context, selected, _) =>
          MoonRunningChart(moonInstants: selected.instants, channelInfoList: selected.channels),
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
          child: Scaffold(
            appBar: AppBar(
              title: Text(context.translate('Moonlight')),
              actions: [
                Consumer<MoonViewModel>(
                  builder: (context, vm, _) => Switch.adaptive(
                    value: vm.enabled,
                    onChanged: !vm.isBusy && vm.isOnline && vm.isOn ? vm.setEnabled : null,
                  ),
                ),
                Consumer<MoonViewModel>(
                  builder: (context, vm, _) => AppBarApplyButton(
                    label: context.translate('Apply'),
                    onPressed: vm.canSubmit ? () => onSubmit(vm, context) : null,
                  ),
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
                          SizedBox(
                            height: 180,
                            child: Consumer<MoonViewModel>(builder: (context, vm, _) => buildGraph(context, vm)),
                          ),
                          Expanded(
                            child: Consumer<MoonViewModel>(
                              builder: (context, vm, _) => ScreenTopRoundedContainer(
                                color: Theme.of(context).colorScheme.surfaceContainer,
                                padding: EdgeInsets.fromLTRB(0, 24, 0, 0),
                                child: SafeArea(
                                  child: SingleChildScrollView(
                                    child: BrightnessSliderList(vm.editor, disabled: !vm.enabled || !vm.canEdit),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                }
              },
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
