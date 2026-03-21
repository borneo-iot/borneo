import 'dart:convert';
import 'package:borneo_app/core/services/devices/ota/ota_providers.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/controller_settings_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/settings_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/controller_settings_screen.dart';
import 'package:borneo_app/devices/view_models/device_ota_view_model.dart';
import 'package:borneo_app/devices/views/device_ota_screen.dart';
import 'package:borneo_app/app/themes/settings_list_theme.dart';
import 'package:borneo_app/shared/widgets/bottom_sheet_picker.dart';
import 'package:borneo_app/shared/widgets/confirmation_sheet.dart';
import 'package:borneo_app/features/devices/views/device_availability_guard.dart';
import 'package:borneo_app/shared/widgets/map_location_picker.dart';
import 'package:borneo_common/io/net/rssi.dart';
import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_earth_globe/globe_coordinates.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:flutter_settings_ui/flutter_settings_ui.dart';
import 'package:logger/logger.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';
import 'package:borneo_app/routes/platform_page_route.dart';

import 'package:provider/provider.dart';
import 'package:borneo_app/routes/app_routes.dart';

class SettingsScreen extends StatelessWidget {
  final SettingsViewModel vm;
  const SettingsScreen(this.vm, {super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: vm,
      builder: (context, child) => DeviceAvailabilityGuard<SettingsViewModel>(
        viewModel: vm,
        child: Scaffold(
          appBar: AppBar(title: Text(context.translate('Settings'))),
          body: SafeArea(child: _buildSettingsList(context)),
        ),
      ),
    );
  }

  Icon _buildWifiRssiIcon(BuildContext bc) {
    var rssi = vm.borneoStatus.wifiRssi;
    if (rssi != null) {
      return switch (RssiLevelExtension.fromRssi(rssi)) {
        RssiLevel.strong => Icon(Icons.wifi),
        RssiLevel.medium => Icon(Icons.wifi_2_bar),
        RssiLevel.weak => Icon(Icons.wifi_1_bar),
      };
    } else {
      return Icon(Icons.wifi_off, color: Theme.of(bc).colorScheme.error);
    }
  }

  Future<void> _pickLocation(BuildContext context, SettingsViewModel vm) async {
    // Build the route with the existing device location if available
    final GlobeCoordinates? initialLocation = vm.location != null
        ? GlobeCoordinates(vm.location!.lat, vm.location!.lng)
        : null;

    final route = platformPageRoute<GlobeCoordinates?>(
      builder: (context) => MapLocationPicker(initialLocation: initialLocation),
      fullscreenDialog: true,
    );

    try {
      // Navigate to the picker and await a GlobeCoordinates (null if cancelled)
      final GlobeCoordinates? selectedLocation = await Navigator.of(context).push<GlobeCoordinates?>(route);

      if (!context.mounted) {
        return;
      }

      if (selectedLocation != null) {
        await vm.updateGeoLocation(GeoLocation(lat: selectedLocation.latitude, lng: selectedLocation.longitude));
      }
    } catch (e, stackTrace) {
      if (context.mounted) {
        final log = context.read<Logger>();
        log.e("Failed select location", error: e, stackTrace: stackTrace);
      }
    }
  }

  SettingsList _buildSettingsList(BuildContext context) {
    final lvm = context.watch<SettingsViewModel>();
    return SettingsList(
      lightTheme: settingsListTheme(context),
      darkTheme: settingsListTheme(context),
      sections: [
        SettingsSection(
          title: Text(context.translate('DEVICE INFORMATION')),
          tiles: [
            SettingsTile.navigation(
              title: Text(context.translate('Name')),
              value: Text(lvm.name),
              onPressed: (bc) => _showNameDialog(bc, vm),
            ),
            SettingsTile(title: Text(context.translate('Manufacturer')), trailing: Text(lvm.borneoInfo.manufName)),
            SettingsTile(title: Text(context.translate('Model')), trailing: Text(lvm.borneoInfo.modelName)),
            SettingsTile(
              title: Text(context.translate('Serial Number')),
              trailing: Text(lvm.borneoInfo.serno.substring(0, 12)),
            ),
            SettingsTile(
              title: Text(context.translate('Device address')),
              trailing: _buildWifiRssiIcon(context),
              descriptionInlineIos: true,
              description: Text(lvm.address.toString()),
            ),
          ],
        ),

        SettingsSection(
          title: Text(context.translate('LOCATION & TIME')),
          tiles: [
            SettingsTile.navigation(
              title: Text(context.translate('Device Location')),
              description: Text(context.translate('Geographical location')),
              descriptionInlineIos: true,
              value: lvm.location != null
                  ? Text("(${lvm.location!.lat.toStringAsFixed(0)}, ${lvm.location!.lng.toStringAsFixed(0)})")
                  : Text(context.translate('Unknown'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              enabled: lvm.canUpdateGeoLocation,
              onPressed: (bc) async {
                if (bc.mounted) {
                  await _pickLocation(bc, vm);
                }
              },
            ),

            SettingsTile.navigation(
              title: Text(context.translate('Time zone')),
              descriptionInlineIos: true,
              value: Text(
                lvm.timezone ?? context.translate('No time zone'),
                style: lvm.hasTimezoneMismatch || lvm.timezone == null
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
              // if device timezone differs from local, show a brief warning description
              description: lvm.hasTimezoneMismatch
                  ? Text(
                      context.translate('Timezone mismatch'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    )
                  : null,
              enabled: lvm.canUpdateTimezone,
              onPressed: (bc) => vm.updateTimezone(),
            ),
          ],
        ),

        SettingsSection(
          title: Text(context.translate('DEVICE STATUS')),
          tiles: [
            SettingsTile.navigation(
              title: Text(context.translate('Power status at startup')),
              value: Text(_formatPowerBehavior(context, lvm.powerBehavior)),
              enabled: lvm.canUpdatePowerBehavior,
              onPressed: (bc) => _showPowerBehaviorPicker(bc, vm),
            ),
            SettingsTile(
              title: Text(context.translate('Last shutdown')),
              trailing: Text(lvm.borneoStatus.shutdownTimestamp?.toLocal().toString() ?? context.translate('N/A')),
              descriptionInlineIos: true,
              description: Text(
                context.translate("Reason code: {reasonCode}", nArgs: {"reasonCode": lvm.borneoStatus.shutdownReason}),
              ),
            ),
          ],
        ),

        SettingsSection(
          title: Text(context.translate('LIGHTING')),
          tiles: [
            SettingsTile.navigation(
              title: Text(context.translate('Correction curve')),
              value: Text(_formatCorrectionMethod(context, lvm.correctionMethod)),
              enabled: lvm.canUpdateCorrectionMethod,
              onPressed: (bc) => _showCorrectionMethodPicker(bc, vm),
            ),
            SettingsTile.navigation(
              title: Text(context.translate('Temporary light duration')),
              value: Text(_formatDuration(context, lvm.temporaryDuration)),
              enabled: lvm.canUpdateTemporaryDuration,
              onPressed: (bc) => _showTemporaryDurationPicker(bc, vm),
            ),
            SettingsTile.switchTile(
              title: Text(context.translate('Cloud simulation')),
              description: Text(context.translate('Simulate cloud shadow effect')),
              descriptionInlineIos: true,
              initialValue: lvm.cloudEnabled,
              enabled: lvm.canUpdateCloudEnabled,
              onToggle: lvm.canUpdateCloudEnabled
                  ? (bool value) async {
                      await vm.updateCloudEnabled(value);
                    }
                  : null,
            ),
          ],
        ),

        SettingsSection(
          title: Text(context.translate('THERMAL MANAGEMENT')),
          tiles: [
            SettingsTile.navigation(
              title: Text(context.translate('Fan mode')),
              value: Text(_formatFanMode(context, lvm.fanMode)),
              enabled: lvm.canUpdateFanMode,
              onPressed: (bc) => _showFanModePicker(bc, vm),
            ),
            SettingsTile.navigation(
              title: Text(context.translate('Manual fan power')),
              value: Text('${lvm.manualFanPower}%'),
              enabled: lvm.canUpdateManualFanPower,
              onPressed: lvm.canUpdateManualFanPower
                  ? (bc) => _showManualFanPowerDialog(bc, vm, lvm.manualFanPower)
                  : null,
            ),
          ],
        ),

        SettingsSection(
          title: Text(context.translate('VERSION & UPGRADE')),
          tiles: [
            SettingsTile(
              title: Text(context.translate('Hardware version')),
              trailing: Text(lvm.borneoInfo.hwVer.toString()),
            ),
            SettingsTile.navigation(
              title: Text(context.translate('Firmware version')),
              value: Text(lvm.borneoInfo.fwVer.toString() + (lvm.borneoInfo.isCE ? " (CE)" : " (PRO)")),
              descriptionInlineIos: false,
              onPressed: !vm.isOnline ? null : (cb) => _goToOtaScreen(context, vm),
            ),
          ],
        ),

        if (lvm.isControllerSettingsAvailable)
          SettingsSection(
            title: Text(context.translate('STANDALONE CONTROLLER')),
            tiles: [
              SettingsTile.navigation(
                title: Text(context.translate('Controller Settings')),
                onPressed: (bc) => _goControllerSettings(bc, vm),
              ),
            ],
          ),

        SettingsSection(
          title: Text(context.translate('DANGER ZONE')),
          tiles: [
            /*
            SettingsTile.navigation(
              title: Text(
                context.translate('Delete device'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onPressed: (bc) => _showDeleteDialog(bc, vm),
            ),
            */
            SettingsTile.navigation(
              title: Text(
                context.translate('Reset device network settings'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onPressed: (bc) => _showNetworkResetDialog(bc, vm),
            ),
            SettingsTile.navigation(
              title: Text(
                context.translate('Restore to factory settings'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onPressed: (bc) => _showFactoryResetDialog(bc, vm),
            ),
          ],
        ),
      ],
    );
  }

  void _goToOtaScreen(BuildContext context, SettingsViewModel svm) {
    final bound = svm.boundDevice;
    if (bound == null) return;
    final otaVm = DeviceOtaViewModel(
      otaProvider: context.read<OtaProvider>(),
      boundDevice: bound,
      isOnlineProvider: () => svm.isOnline,
      eventBus: context.read<EventBus>(),
      gt: context.read<GettextLocalizations>(),
      logger: context.read<Logger>(),
    );

    pushScreen(
      context,
      screen: DeviceOtaScreen(otaVm),
      withNavBar: false,
      pageTransitionAnimation: PageTransitionAnimation.platform,
    );
  }

  void _goControllerSettings(BuildContext context, SettingsViewModel svm) {
    final csvm = ControllerSettingsViewModel(
      deviceManager: svm.deviceManager,
      globalEventBus: svm.globalEventBus,
      notification: svm.notification,
      wotThing: svm.wotThing,
      gt: context.read<GettextLocalizations>(),
    );
    final route = platformPageRoute(builder: (context) => ControllerSettingsScreen(csvm));
    Navigator.push(context, route);
  }

  void _showFactoryResetDialog(BuildContext context, SettingsViewModel vm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(context.translate('Restore Factory Settings')),
        content: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.translate('Are you sure you want to restore this device to factory settings?')),
              SizedBox(height: 16),
              Text(context.translate('This action will:'), style: Theme.of(context).textTheme.titleSmall),
              SizedBox(height: 8),
              Text(context.translate('• Delete all custom settings and configurations')),
              Text(context.translate('• Disconnect the device from your network')),
              Text(context.translate('• Reset all schedules and modes to defaults')),
              SizedBox(height: 8),
              Text(
                context.translate('The device will need to be reconfigured after this operation.'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.translate('Cancel'))),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // after the factory reset completes navigate all the way back to the
              // device list (rather than just popping a single route). this matches
              // other flows such as provisioning where the user is returned to the
              // main list when a long‑running action finishes.
              vm.factoryReset().then((_) {
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.settings.name == AppRoutes.kDevices || route.isFirst);
                }
              });
            },
            child: Text(context.translate('Restore')),
          ),
        ],
      ),
    );
  }

  Future<void> _showNetworkResetDialog(BuildContext context, SettingsViewModel vm) async {
    final confirmed = await AsyncConfirmationSheet.show(
      context,
      message: context.translate(
        "Are you sure you want to reset this device's network settings?\nThe device will be removed and must be provisioned again.",
      ),
    );

    if (!confirmed) {
      return;
    }

    await vm.networkReset();

    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.settings.name == AppRoutes.kDevices || route.isFirst);
    }
  }

  /*
  Future<void> _showDeleteDialog(BuildContext context, SettingsViewModel vm) async {
    final confirmed = await AsyncConfirmationSheet.show(
      context,
      message: context.translate('Are you sure you want to delete this device?'),
    );

    if (!confirmed) return;

    vm.delete().then((_) {
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.settings.name == AppRoutes.kDevices || route.isFirst);
      }
    });
  }
  */

  void _showManualFanPowerDialog(BuildContext context, SettingsViewModel vm, int currentValue) {
    double tempValue = currentValue.toDouble();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog.adaptive(
          title: Text(context.translate('Set Manual Fan Power'), style: Theme.of(context).textTheme.titleMedium),
          content: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${tempValue.toInt()}%'),
                Slider.adaptive(
                  value: tempValue,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${tempValue.toInt()}%',
                  onChanged: (value) {
                    setState(() {
                      tempValue = value;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.translate('Cancel'))),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await vm.updateManualFanPower(tempValue.toInt());
              },
              child: Text(context.translate('Set')),
            ),
          ],
        ),
      ),
    );
  }

  void _showNameDialog(BuildContext context, SettingsViewModel vm) {
    final controller = TextEditingController(text: vm.name);
    String? errorText;

    String? validateName(String name) {
      if (name.isEmpty) {
        return context.translate('Device name cannot be empty.');
      }
      if (name.trim().isEmpty) {
        return context.translate('Device name cannot be pure whitespace.');
      }
      if (name.trim() != name) {
        return context.translate('Device name cannot have leading or trailing whitespace.');
      }
      if (utf8.encode(name).length > 63) {
        return context.translate('Device name is too long. Maximum length is 63 bytes when encoded as UTF-8.');
      }
      return null;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog.adaptive(
          title: Text(context.translate('Set Device Name')),
          content: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  selectAllOnFocus: true,
                  controller: controller,
                  decoration: InputDecoration(labelText: context.translate('Device Name'), errorText: errorText),
                  onChanged: (value) {
                    setState(() {
                      errorText = validateName(value);
                    });
                  },
                ),
                if (vm.isBusy) ...[SizedBox(height: 16), CircularProgressIndicator()],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: vm.isBusy ? null : () => Navigator.of(context).pop(),
              child: Text(context.translate('Cancel')),
            ),
            TextButton(
              onPressed: vm.isBusy || errorText != null
                  ? null
                  : () async {
                      final newName = controller.text.trim();
                      if (validateName(newName) == null) {
                        setState(() {});
                        await vm.updateName(newName);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      }
                    },
              child: Text(context.translate('Set')),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPowerBehavior(BuildContext context, PowerBehavior behavior) {
    return switch (behavior) {
      PowerBehavior.autoPowerOn => context.translate("Keep on"),
      PowerBehavior.maintainPowerOff => context.translate("Keep off"),
      PowerBehavior.lastPowerState => context.translate("Maintain last"),
    };
  }

  void _showPowerBehaviorPicker(BuildContext context, SettingsViewModel vm) {
    final options = [
      {'value': PowerBehavior.autoPowerOn, 'label': context.translate("Keep on")},
      {'value': PowerBehavior.maintainPowerOff, 'label': context.translate("Keep off")},
      {'value': PowerBehavior.lastPowerState, 'label': context.translate("Maintain last")},
    ];
    final currentIndex = options.indexWhere((option) => option['value'] == vm.powerBehavior);

    BottomSheetPicker.show(
      context: context,
      title: context.translate('Select power status'),
      items: options.map((option) => option['label'] as String).toList(),
      selectedIndex: currentIndex >= 0 ? currentIndex : 0,
      onItemSelected: (index) async {
        final selectedOption = options[index];
        await vm.updatePowerBehavior(selectedOption['value'] as PowerBehavior);
      },
    );
  }

  String _formatCorrectionMethod(BuildContext context, LedCorrectionMethod method) {
    return switch (method) {
      LedCorrectionMethod.log => context.translate("Logarithmic"),
      LedCorrectionMethod.linear => context.translate("Linear"),
      LedCorrectionMethod.exp => context.translate("Exponential"),
      LedCorrectionMethod.gamma => context.translate("Gamma"),
      LedCorrectionMethod.cie1931 => context.translate("CIE1931"),
    };
  }

  void _showCorrectionMethodPicker(BuildContext context, SettingsViewModel vm) {
    final options = [
      {'value': LedCorrectionMethod.log, 'label': context.translate("Logarithmic")},
      {'value': LedCorrectionMethod.linear, 'label': context.translate("Linear")},
      {'value': LedCorrectionMethod.exp, 'label': context.translate("Exponential")},
      {'value': LedCorrectionMethod.gamma, 'label': context.translate("Gamma")},
      {'value': LedCorrectionMethod.cie1931, 'label': context.translate("CIE1931")},
    ];
    final currentIndex = options.indexWhere((option) => option['value'] == vm.correctionMethod);

    BottomSheetPicker.show(
      context: context,
      title: context.translate('Select correction curve'),
      items: options.map((option) => option['label'] as String).toList(),
      selectedIndex: currentIndex >= 0 ? currentIndex : 0,
      onItemSelected: (index) async {
        final selectedOption = options[index];
        await vm.updateLedCorrectionMethod(selectedOption['value'] as LedCorrectionMethod);
      },
    );
  }

  String _formatDuration(BuildContext context, Duration duration) {
    if (duration.inMinutes == 5) return context.translate("5 minutes");
    if (duration.inMinutes == 10) return context.translate("10 minutes");
    if (duration.inMinutes == 20) return context.translate("20 minutes");
    if (duration.inHours == 1) return context.translate("1 hour");
    if (duration.inHours == 2) return context.translate("2 hours");
    if (duration.inHours == 4) return context.translate("4 hours");
    if (duration.inHours == 8) return context.translate("8 hours");
    if (duration.inHours == 12) return context.translate("12 hours");
    return duration.toString();
  }

  void _showTemporaryDurationPicker(BuildContext context, SettingsViewModel vm) {
    final options = [
      {'value': Duration(minutes: 5), 'label': context.translate("5 minutes")},
      {'value': Duration(minutes: 10), 'label': context.translate("10 minutes")},
      {'value': Duration(minutes: 20), 'label': context.translate("20 minutes")},
      {'value': Duration(hours: 1), 'label': context.translate("1 hour")},
      {'value': Duration(hours: 2), 'label': context.translate("2 hours")},
      {'value': Duration(hours: 4), 'label': context.translate("4 hours")},
      {'value': Duration(hours: 8), 'label': context.translate("8 hours")},
      {'value': Duration(hours: 12), 'label': context.translate("12 hours")},
    ];
    final currentIndex = options.indexWhere((option) => option['value'] == vm.temporaryDuration);

    BottomSheetPicker.show(
      context: context,
      title: context.translate('Select duration'),
      items: options.map((option) => option['label'] as String).toList(),
      selectedIndex: currentIndex >= 0 ? currentIndex : 0,
      onItemSelected: (index) async {
        final selectedOption = options[index];
        await vm.updateTemporaryDuration(selectedOption['value'] as Duration);
      },
    );
  }

  String _formatFanMode(BuildContext context, FanMode mode) {
    return switch (mode) {
      FanMode.pid => context.translate("PID Adaptive"),
      FanMode.manual => context.translate("Manual"),
    };
  }

  void _showFanModePicker(BuildContext context, SettingsViewModel vm) {
    final options = [
      {'value': FanMode.pid, 'label': context.translate("PID Adaptive")},
      {'value': FanMode.manual, 'label': context.translate("Manual")},
    ];
    final currentIndex = options.indexWhere((option) => option['value'] == vm.fanMode);

    BottomSheetPicker.show(
      context: context,
      title: context.translate('Select fan mode'),
      items: options.map((option) => option['label'] as String).toList(),
      selectedIndex: currentIndex >= 0 ? currentIndex : 0,
      onItemSelected: (index) async {
        final selectedOption = options[index];
        await vm.updateFanMode(selectedOption['value'] as FanMode);
      },
    );
  }
}
