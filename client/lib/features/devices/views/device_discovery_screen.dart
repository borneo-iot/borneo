import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/core/services/devices/device_module_registry.dart';
import 'package:borneo_app/core/services/group_manager.dart';
import 'package:borneo_app/core/services/i_app_notification_service.dart';
import 'package:borneo_app/features/devices/views/device_group_selection_sheet.dart';
import 'package:borneo_kernel_abstractions/models/supported_device_descriptor.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';

import '../../../core/services/device_manager.dart';
import '../view_models/device_discovery_view_model.dart';

class StartStopButton extends StatelessWidget {
  const StartStopButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<DeviceDiscoveryViewModel, (bool, bool, bool, bool)>(
      selector: (context, vm) => (vm.isBusy.value, vm.isSmartConfigEnabled, vm.isFormValid, vm.isDiscovering),
      builder: (context, tuple, child) {
        final (isBusy, isSmartConfigEnabled, isFormValid, isDiscovering) = tuple;
        final vm = context.read<DeviceDiscoveryViewModel>();
        return ElevatedButton(
          onPressed: (!isBusy && (!isSmartConfigEnabled || isFormValid)) ? vm.startStopDiscovery : null,
          child: isDiscovering
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDiscovering)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.inversePrimary),
                        ),
                      ),
                    SizedBox(width: 16),
                    Text(context.translate('Stop')),
                  ],
                )
              : Text(context.translate('Start')),
        );
      },
    );
  }
}

class SmartConfigFormPanel extends StatefulWidget {
  const SmartConfigFormPanel({super.key});

  @override
  State createState() => _SmartConfigFormPanelState();
}

class _SmartConfigFormPanelState extends State<SmartConfigFormPanel> {
  late TextEditingController _ssidController;
  late TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    final vm = context.read<DeviceDiscoveryViewModel>();
    _ssidController = TextEditingController(text: vm.ssid);
    _passwordController = TextEditingController(text: vm.password);
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).scaffoldBackgroundColor,
            alignment: Alignment.topLeft,
            child: Row(
              children: [
                Expanded(child: Text('Provisioning', style: Theme.of(context).textTheme.titleMedium)),
                Consumer<DeviceDiscoveryViewModel>(
                  builder: (context, vm, child) => Switch(
                    value: vm.isSmartConfigEnabled,
                    onChanged: !vm.isDiscovering && !vm.isBusy.value ? vm.toggleSmartConfigSwitch : null,
                  ),
                ),
              ],
            ),
          ),
          Container(
            alignment: Alignment.topLeft,
            padding: const EdgeInsets.all(0),
            child: Column(
              children: <Widget>[
                Column(
                  children: <Widget>[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Consumer<DeviceDiscoveryViewModel>(
                        builder: (context, vm, child) {
                          return TextField(
                            controller: _ssidController,
                            onChanged: (value) {
                              vm.ssid = value;
                            },
                            enabled: !vm.isDiscovering && !vm.isBusy.value && vm.isSmartConfigEnabled,
                            decoration: InputDecoration(
                              labelText: "2.4G WiFi Name (SSID)",
                              border: InputBorder.none,
                              icon: Icon(
                                Icons.wifi,
                                color: !vm.isSmartConfigEnabled
                                    ? Theme.of(context).disabledColor
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8.0),
                      child: const Divider(height: 1, thickness: 1),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Consumer<DeviceDiscoveryViewModel>(
                        builder: (context, vm, child) => TextField(
                          controller: _passwordController,
                          onChanged: (value) {
                            vm.password = value;
                          },
                          enabled: !vm.isDiscovering && !vm.isBusy.value && vm.isSmartConfigEnabled,
                          decoration: InputDecoration(
                            labelText: "2.4G WiFi Password",
                            border: InputBorder.none,
                            icon: Icon(
                              Icons.lock,
                              color: !vm.isSmartConfigEnabled
                                  ? Theme.of(context).disabledColor
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8.0),
                      child: const Divider(height: 1, thickness: 1),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NewDeviceAddedSnackBarListener extends StatelessWidget {
  final Widget child;
  const NewDeviceAddedSnackBarListener({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Selector<DeviceDiscoveryViewModel, DeviceEntity?>(
      selector: (_, viewModel) => viewModel.lastestAddedDevice,
      builder: (context, lastestAdded, child) {
        if (lastestAdded != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            toastification.dismissAll();
            Provider.of<IAppNotificationService>(
              context,
              listen: false,
            ).showSuccess(context.translate('A new device has been added.'), body: lastestAdded.name);

            /*
            Future.delayed(const Duration(seconds: 3), () {
              if (!vm.isDisposed) {
                vm.clearAddedDevice();
              }
            });
            */
          });
        }
        return child!;
      },
      child: child,
    );
  }
}

class DeviceDiscoveryScreen extends StatelessWidget {
  const DeviceDiscoveryScreen({super.key});

  DeviceDiscoveryViewModel createViewModel(BuildContext context) => DeviceDiscoveryViewModel(
    context.read<Logger>(),
    context.read<GroupManager>(),
    context.read<DeviceManager>(),
    context.read<IDeviceModuleRegistry>(),
    globalEventBus: context.read<EventBus>(),
  );

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DeviceDiscoveryViewModel>(
      create: createViewModel,
      builder: (context, child) => FutureBuilder(
        future: context.read<DeviceDiscoveryViewModel>().initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(body: Center(child: CircularProgressIndicator()));
          } else if (snapshot.hasError) {
            return Scaffold(body: Center(child: Text('Error: ︀{snapshot.error}')));
          } else {
            return Selector<DeviceDiscoveryViewModel, bool>(
              selector: (_, vm) => vm.isBusy.value,
              builder: (context, isBusy, _) => Scaffold(
                appBar: AppBar(
                  title: Text('Add new device'),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back),
                    onPressed: isBusy ? null : () => Navigator.of(context).maybePop(),
                  ),
                ),
                body: buildBody(context, isBusy),
              ),
            );
          }
        },
      ),
    );
  }

  Widget buildBody(BuildContext context, bool isBusy) {
    final vm = context.read<DeviceDiscoveryViewModel>();
    return PopScope(
      canPop: !isBusy,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        if (!vm.isDiscovering && !vm.isBusy.value) {
          Navigator.of(context).pop(vm.newDeviceCount > 0);
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.max,
          children: [
            Container(
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Input Fields
                  SmartConfigFormPanel(),
                  SizedBox(height: 8),
                  // Start/Stop Button
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    width: double.infinity,
                    child: StartStopButton(),
                  ),
                  SizedBox(height: 16),
                ],
              ),
            ),

            Expanded(
              child: Card(
                elevation: 0,
                margin: EdgeInsets.zero,
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ValueListenableBuilder<List<SupportedDeviceDescriptor>>(
                      valueListenable: vm.discoveredDevices,
                      builder: (context, devices, child) => devices.isNotEmpty ? child! : const SizedBox(height: 0),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text(
                          context.translate('Discovered Devices:'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ValueListenableBuilder<List<SupportedDeviceDescriptor>>(
                        valueListenable: vm.discoveredDevices,
                        builder: (context, value, child) => ListView.separated(
                          separatorBuilder: (BuildContext context, int index) => SizedBox(height: 12),
                          itemCount: vm.discoveredDevices.value.length,
                          itemBuilder: (context, index) {
                            final deviceDesc = vm.discoveredDevices.value[index];
                            Widget deviceIcon = _buildDeviceIcon(context, vm, deviceDesc);
                            return Container(
                              margin: EdgeInsets.symmetric(horizontal: 8),
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.horizontal(
                                  left: Radius.circular(16),
                                  right: Radius.circular(16),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  SizedBox(width: 48, height: 48, child: Center(child: deviceIcon)),
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.fromLTRB(16, 0, 0, 0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(deviceDesc.name, style: Theme.of(context).textTheme.bodyMedium),
                                          SizedBox(height: 4),
                                          Text(
                                            deviceDesc.address.toString(),
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Consumer<DeviceDiscoveryViewModel>(
                                    builder: (context, vm, child) => SizedBox(
                                      height: 48,
                                      width: 48,
                                      child: IconButton.filledTonal(
                                        onPressed: vm.isBusy.value || vm.isDiscovering
                                            ? null
                                            : () => _showAddDeviceSheet(context, vm, vm.discoveredDevices.value[index]),
                                        icon: const Icon(Icons.add_outlined, size: 32),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            NewDeviceAddedSnackBarListener(child: SizedBox()),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceIcon(BuildContext context, DeviceDiscoveryViewModel vm, SupportedDeviceDescriptor deviceDesc) {
    final meta = vm.deviceMdoules.metaModules.containsKey(deviceDesc.driverDescriptor.id)
        ? vm.deviceMdoules.metaModules[deviceDesc.driverDescriptor.id]
        : null;
    Widget iconWidget;
    if (meta != null) {
      iconWidget = meta.deviceIconBuilder(context, 40, true);
    } else {
      iconWidget = Icon(Icons.device_unknown, size: 40, color: Theme.of(context).colorScheme.outline);
    }
    // 增加边框和背景，参考 DeviceTile
    return Container(
      height: 48,
      width: 48,
      decoration: ShapeDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5.0),
          side: BorderSide(width: 1.5, color: Theme.of(context).colorScheme.primaryContainer),
        ),
      ),
      child: Center(child: iconWidget),
    );
  }

  void _showAddDeviceSheet(BuildContext context, DeviceDiscoveryViewModel vm, SupportedDeviceDescriptor deviceInfo) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => DeviceGroupSelectionSheet(
        availableGroups: vm.availableGroups,
        onTapGroup: (g) => vm.addNewDevice(deviceInfo, g),
        title: 'Registry "${deviceInfo.name}"',
        subtitle: 'Select the group to which the new device belongs:',
      ),
    );
  }
}
