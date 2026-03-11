import 'package:borneo_app/core/services/clock.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/acclimation_view_model.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_app/shared/widgets/app_bar_apply_button.dart';
import 'package:borneo_app/shared/widgets/settings_ui/settings_tile_extensions.dart';
import 'package:borneo_app/features/devices/views/device_availability_guard.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:flutter_settings_ui/flutter_settings_ui.dart';
import 'package:provider/provider.dart';

class AcclimationScreen extends StatelessWidget {
  final String deviceID;
  const AcclimationScreen({required this.deviceID, super.key});

  Color _valueColor(BuildContext context, bool hasError) {
    return hasError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;
  }

  @override
  Widget build(BuildContext context) {
    final vm = AcclimationViewModel(
      deviceManager: context.read<IDeviceManager>(),
      globalEventBus: context.read<EventBus>(),
      notification: context.read<IAppNotificationService>(),
      wotThing: context.read<IDeviceManager>().getWotThing(deviceID),
      clock: context.read<IClock>(),
      gt: context.read<GettextLocalizations>(),
      logger: context.read<Logger>(),
    );
    return ChangeNotifierProvider(
      create: (cb) => vm,
      builder: (context, child) {
        return DeviceAvailabilityGuard<AcclimationViewModel>(
          viewModel: vm,
          child: FutureBuilder(
            future: vm.initFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Scaffold(
                  appBar: AppBar(title: Text(context.translate('Acclimation'))),
                  body: Center(child: CircularProgressIndicator()),
                );
              } else if (snapshot.hasError) {
                if (!vm.isAvailable) {
                  return const SizedBox.shrink();
                }
                return Scaffold(
                  appBar: AppBar(title: Text(context.translate('Acclimation'))),
                  body: Center(child: Text('Error: ${snapshot.error}')),
                );
              } else {
                return Scaffold(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  appBar: AppBar(
                    title: Text(context.translate('Acclimation')),
                    actions: [
                      Consumer<AcclimationViewModel>(
                        builder: (context, vm, _) => AppBarApplyButton(
                          onPressed: vm.canSubmit ? () => onSubmit(vm, context) : null,
                          label: context.translate('Apply'),
                        ),
                      ),
                    ],
                  ),
                  body: _buildSettingsList(context),
                );
              }
            },
          ),
        );
      },
    );
  }

  SettingsList _buildSettingsList(BuildContext context) {
    // use watch to rebuild when values change
    final vm = context.watch<AcclimationViewModel>();

    return SettingsList(
      sections: [
        SettingsSection(
          title: Text(context.translate('SETTINGS')),
          tiles: [
            SettingsTile.switchTile(
              title: Text(context.translate('Enable acclimation')),
              initialValue: vm.enabled,
              onToggle: !vm.isBusy && vm.isOnline && vm.isOn ? vm.updateEnabled : null,
            ),
            SettingsTile.navigation(
              title: Text(context.translate('Start date')),
              value: Builder(
                builder: (ctx) {
                  final locale = Localizations.localeOf(ctx).toString();
                  return Text(
                    vm.startTimestamp.toLocal().year < 2025
                        ? context.translate('Not set')
                        : DateFormat.yMd(locale).format(vm.startTimestamp.toLocal()),
                    style: TextStyle(color: _valueColor(context, vm.hasStartDateError)),
                  );
                },
              ),
              onPressed: !vm.isBusy && vm.isOnline
                  ? (bc) async {
                      final now = context.read<IClock>().now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: vm.startTimestamp.toLocal().year < 2025 ? now : vm.startTimestamp.toLocal(),
                        firstDate: DateTime(2025, 1, 1),
                        lastDate: now.add(const Duration(days: 100)),
                      );
                      if (picked != null) {
                        vm.updateStartTimestamp(picked);
                      }
                    }
                  : null,
            ),
            settingsSliderTile(
              title: Text(context.translate('Duration')),
              value: vm.days.clamp(5, 100),
              min: 5,
              max: 100,
              divisions: 95,
              label: context.translate('{d} days', nArgs: {'d': vm.days.round().toString()}),
              trailing: Text(
                context.translate('{d} days', nArgs: {'d': vm.days.round().toString()}),
                style: TextStyle(
                  color: _valueColor(context, vm.hasDurationError),
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              enabled: !vm.isBusy && vm.isOnline,
              onChanged: (value) => vm.updateDays(value.roundToDouble()),
            ),
            settingsSliderTile(
              title: Text(context.translate('Start strength')),
              value: vm.startPercent.clamp(10, 90),
              min: 10,
              max: 90,
              divisions: 80,
              label: '${vm.startPercent.round()}%',
              trailing: Text(
                '${vm.startPercent.round()}%',
                style: TextStyle(
                  color: _valueColor(context, vm.hasStartPercentError),
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              enabled: !vm.isBusy && vm.isOnline,
              onChanged: (value) => vm.updateStartPercent(value.roundToDouble()),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> onSubmit(AcclimationViewModel vm, BuildContext context) async {
    final didSubmit = await vm.submitToDevice();
    if (didSubmit && context.mounted) {
      Provider.of<IAppNotificationService>(
        context,
        listen: false,
      ).showSuccess(context.translate('Update acclimation settings succeed.'));
      Navigator.of(context).pop();
    }
  }
}
