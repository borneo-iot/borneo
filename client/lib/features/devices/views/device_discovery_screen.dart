import 'package:borneo_app/features/devices/models/discoverable_device.dart';
import 'package:borneo_app/features/devices/providers/new_device_candidates_store.dart';
import 'package:borneo_app/features/devices/views/provisioning_screen.dart';
import 'package:borneo_kernel_abstractions/models/supported_device_descriptor.dart';
import 'package:flutter/material.dart';
import 'package:borneo_app/core/services/platform_service.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/services/devices/device_manager.dart';
import '../../../core/services/devices/ble_provisioner.dart';
import '../view_models/device_discovery_view_model.dart';
import 'package:borneo_app/core/services/devices/device_module_registry.dart';
import 'package:event_bus/event_bus.dart';
import 'package:logger/logger.dart';

class DeviceDiscoveryScreen extends StatelessWidget {
  const DeviceDiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gt = GettextLocalizations.of(context);
    return ChangeNotifierProvider(
      create: (cb) => DeviceDiscoveryViewModel(
        cb.read<Logger>(),
        cb.read<IDeviceManager>(),
        cb.read<NewDeviceCandidatesStore>(),
        cb.read<IBleProvisioner>(),
        cb.read<IDeviceModuleRegistry>(),
        cb.read<PlatformService>(), // injected platform helper
        globalEventBus: cb.read<EventBus>(),
        gt: gt,
        logger: cb.read<Logger>(),
      ),
      builder: (context, _) {
        final vm = context.read<DeviceDiscoveryViewModel>();
        return Scaffold(
          appBar: AppBar(
            title: Text(context.translate('Add Device')),
            actions: [
              Selector<DeviceDiscoveryViewModel, (bool, bool, bool)>(
                selector: (_, vm) => (vm.isDiscovering, vm.isInitialized, vm.isBusy),
                builder: (ctx, state, child) {
                  final (isDiscovering, isInitialized, isBusy) = state;
                  if (!isInitialized || isDiscovering) return const SizedBox();
                  return IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: isBusy ? null : () => ctx.read<DeviceDiscoveryViewModel>().startDiscovery(),
                    tooltip: context.translate('Refresh'),
                  );
                },
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Selector<DeviceDiscoveryViewModel, bool>(
                  selector: (_, vm) => vm.isBusy,
                  builder: (_, isBusy, _) =>
                      SizedBox(height: 2, child: isBusy ? const LinearProgressIndicator() : const SizedBox.expand()),
                ),
                Expanded(
                  child: FutureBuilder<void>(
                    future: vm.initFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text(snapshot.error.toString()));
                      }
                      return const _DeviceDiscoveryContent();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DeviceDiscoveryContent extends StatelessWidget {
  const _DeviceDiscoveryContent();

  @override
  Widget build(BuildContext context) {
    final vm = context.read<DeviceDiscoveryViewModel>();

    return Column(
      children: [
        if (!vm.isMobile)
          Container(
            color: Theme.of(context).colorScheme.secondaryContainer,
            padding: EdgeInsets.all(8),
            width: double.infinity,
            child: Text(
              context.translate('Bluetooth is not supported on this system; device WiFi provisioning is unavailable.'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer),
            ),
          ),
        ValueListenableBuilder<String?>(
          valueListenable: vm.scanError,
          builder: (context, error, child) {
            if (error == null) return const SizedBox();
            return Container(
              color: Theme.of(context).colorScheme.errorContainer,
              padding: EdgeInsets.all(8),
              width: double.infinity,
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer, size: 20),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      error,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onErrorContainer),
                    ),
                  ),
                  IconButton(
                    onPressed: () => vm.scanError.value = null,
                    icon: Icon(Icons.close, color: Theme.of(context).colorScheme.error, size: 20),
                    tooltip: context.translate('Close'),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(minWidth: 48, minHeight: 48),
                  ),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: Selector<DeviceDiscoveryViewModel, (bool, List<DiscoverableDevice>, int, bool)>(
            selector: (_, vm) => (vm.isDiscovering, vm.discoverableDevices.value, vm.remainingSeconds, vm.isBusy),
            builder: (context, state, child) {
              final (isDiscovering, devices, remainingSeconds, isBusy) = state;

              return Stack(
                children: [
                  if (devices.isEmpty && vm.isInitialized && !vm.isDiscovering && !vm.isBusy && !vm.isDisposed)
                    Center(
                      child: Column(
                        children: [
                          const SizedBox(height: 60),
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.media_bluetooth_off,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.38),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  context.translate('No devices found'),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.outline),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.separated(
                      primary: true,
                      itemCount: devices.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, indent: 80, thickness: 1),
                      itemBuilder: (context, index) {
                        final vm = context.read<DeviceDiscoveryViewModel>();
                        return _buildDeviceTile(context, vm, devices[index], isBusy);
                      },
                    ),
                  if (isDiscovering)
                    Container(
                      color: Colors.black.withValues(alpha: 0.3),
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
                                const SizedBox(height: 16),
                                Text(
                                  context.translate('Searching for devices...'),
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  context.translate('{0} seconds remaining', pArgs: [remainingSeconds]),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline),
                                ),
                                const SizedBox(height: 16),
                                TextButton(
                                  onPressed: () => context.read<DeviceDiscoveryViewModel>().stopDiscovery(),
                                  child: Text(context.translate('Stop')),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceTile(BuildContext context, DeviceDiscoveryViewModel vm, DiscoverableDevice device, bool isBusy) {
    // Wrap each tile in a keyed StatefulWidget so only newly inserted items animate.
    final Widget tile = (device.type == DiscoverableDeviceType.provisioned && device.provisionedData != null)
        ? _buildProvisionedTile(context, vm, device.provisionedData!, isBusy)
        : _buildUnprovisionedTile(context, vm, device, isBusy);

    return _AnimatedDeviceTile(key: ValueKey(device.id), child: tile);
  }

  Widget _buildProvisionedTile(
    BuildContext context,
    DeviceDiscoveryViewModel vm,
    SupportedDeviceDescriptor deviceDesc,
    bool isBusy,
  ) {
    return ListTile(
      leading: _buildDeviceIcon(context, vm, deviceDesc),
      title: Text(deviceDesc.name),
      subtitle: Text(context.translate('Detected on network')),
      trailing: Container(
        height: 48,
        width: 48,
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow, shape: BoxShape.circle),
        child: const Icon(Icons.add),
      ),
      onTap: isBusy
          ? null
          : () async {
              await vm.addNewDevice(deviceDesc);
              if (context.mounted) Navigator.pop(context);
            },
    );
  }

  Widget _buildUnprovisionedTile(
    BuildContext context,
    DeviceDiscoveryViewModel vm,
    DiscoverableDevice device,
    bool isBusy,
  ) {
    final bleName = device.bleName ?? '';
    return ListTile(
      leading: Container(
        height: 48,
        width: 48,
        decoration: ShapeDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5.0),
            side: BorderSide(width: 1.5, color: Theme.of(context).colorScheme.tertiaryContainer),
          ),
        ),
        child: Icon(Icons.bluetooth, size: 32, color: Theme.of(context).colorScheme.onTertiaryContainer),
      ),
      title: Text(device.name),
      subtitle: Text(context.translate('Ready to provision')),
      trailing: Container(
        height: 48,
        width: 48,
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow, shape: BoxShape.circle),
        child: const Icon(Icons.chevron_right),
      ),
      onTap: isBusy
          ? null
          : () async {
              if (vm.isMobile) {
                await vm.stopDiscovery();
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ProvisioningScreen(deviceName: bleName)),
                );
                if (context.mounted) {
                  await vm.startDiscovery();
                }
              }
            },
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
}

// Fade-in wrapper for newly inserted device list items.
class _AnimatedDeviceTile extends StatefulWidget {
  final Widget child;
  const _AnimatedDeviceTile({required Key key, required this.child}) : super(key: key);

  @override
  State<_AnimatedDeviceTile> createState() => _AnimatedDeviceTileState();
}

class _AnimatedDeviceTileState extends State<_AnimatedDeviceTile> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Respect user's reduce-motion accessibility preference.
    final reduceMotion = MediaQuery.of(context).accessibleNavigation;
    if (reduceMotion) return widget.child;

    return FadeTransition(
      opacity: _animation,
      child: SlideTransition(
        position: _animation.drive(Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)),
        child: widget.child,
      ),
    );
  }
}
