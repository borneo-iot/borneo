import 'package:borneo_app/devices/view_models/abstract_device_summary_view_model.dart';
import 'package:borneo_app/core/services/devices/device_module_registry.dart';
import 'package:borneo_app/features/devices/view_models/grouped_devices_view_model.dart';
import 'package:borneo_app/features/devices/views/state_icons.dart';
import 'package:borneo_app/shared/widgets/confirmation_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';

import '../models/device_entity.dart';
import '../../../routes/app_routes.dart';
import 'device_group_selection_sheet.dart';

class DeviceTile extends StatelessWidget {
  final bool isLast;
  const DeviceTile(this.isLast, {super.key});

  void openDevicePage(BuildContext context, DeviceEntity device) {
    var vm = context.read<AbstractDeviceSummaryViewModel>();
    Future.delayed(Duration(milliseconds: 200)).then((_) async {
      if (context.mounted) {
        await Navigator.of(context).pushNamed(AppRoutes.makeDeviceScreenRoute(device.driverID), arguments: device);
        vm.notifyListeners();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<AbstractDeviceSummaryViewModel>();
    final device = vm.deviceEntity;
    final moduleMeta = context.read<IDeviceModuleRegistry>().metaModules[device.driverID]!;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: Selector<AbstractDeviceSummaryViewModel, (bool, bool)>(
        selector: (_, vm) => (vm.isOnline, vm.isPowerOn),
        builder: (context, status, child) {
          final vm = context.watch<AbstractDeviceSummaryViewModel>();
          return ListTile(
            dense: false,
            tileColor: Theme.of(context).colorScheme.surfaceContainer,
            onTap: vm.isBusy.value ? null : () => openDevicePage(context, vm.deviceEntity),
            onLongPress: () => _showDevicePopMenu(context),
            leading: Container(
              height: 48,
              width: 48,
              decoration: ShapeDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5.0),
                  side: BorderSide(width: 1.5, color: Theme.of(context).colorScheme.primaryContainer),
                ),
              ),
              child: moduleMeta.deviceIconBuilder(context, 40, vm.isOnline),
            ),
            title: Text(vm.deviceEntity.name),
            subtitle: () {
              if (!status.$1) {
                return Text(
                  context.translate('Off-line'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                );
              }
              if (!status.$2) {
                return Text(
                  context.translate('OFF'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                );
              }
              final widgets = moduleMeta.secondaryStatesBuilder(context, vm);
              if (widgets.isEmpty) return const SizedBox.shrink();
              List<Widget> separated = [];
              for (int i = 0; i < widgets.length; i++) {
                separated.add(widgets[i]);
                if (i != widgets.length - 1) {
                  separated.add(
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.fiber_manual_record, size: 4, color: Theme.of(context).colorScheme.onSurface),
                    ),
                  );
                }
              }
              return Row(mainAxisSize: MainAxisSize.min, children: separated);
            }(),
            trailing: () {
              if (!status.$1) {
                return FlashingIcon(icon: Icon(Icons.link_off, size: 24, color: Theme.of(context).colorScheme.error));
              }
              if (!status.$2) {
                return Icon(Icons.power_settings_new, size: 24, color: Theme.of(context).colorScheme.error);
              }
              return moduleMeta.primaryStateIconBuilder(context, 24);
            }(),
          );
        },
      ),
    );
  }

  void _showDevicePopMenu(BuildContext context) {
    //final vm = context.read<DeviceSummaryViewModel>();
    Rect? rect;
    RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final renderObject = context.findRenderObject();
    final translation = renderObject?.getTransformTo(null).getTranslation();
    if (translation != null && renderObject?.paintBounds != null) {
      final offset = Offset(translation.x, translation.y);
      rect = renderObject!.paintBounds.shift(offset);
    }
    if (rect != null) {
      showMenu(
        context: context,
        position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
        items: <PopupMenuEntry<String>>[
          PopupMenuItem<String>(value: 'reconnect', child: Text('Reconnect')),
          PopupMenuDivider(),
          PopupMenuItem<String>(value: 'change-group', child: Text('Change group...')),
          PopupMenuItem<String>(value: 'delete', child: Text('Delete...')),
        ],
      ).then((value) {
        if (value != null) {
          // Handle the selected menu item
          if (context.mounted) {
            final parentVM = context.read<GroupedDevicesViewModel>();
            final selectedDeviceVM = context.read<AbstractDeviceSummaryViewModel>();
            switch (value) {
              case 'delete':
                {
                  if (context.mounted) {
                    ConfirmationSheet.show(
                      context,
                      message: 'Are you sure to delete the device "${selectedDeviceVM.name}" ?',
                      okPressed: () {
                        parentVM.deleteDevice(selectedDeviceVM.deviceEntity.id);
                      },
                    );
                  }
                  break;
                }
              case 'change-group':
                {
                  final groupEntites = parentVM.groups.where((gvm) => !gvm.isDummy).map((gvm) => gvm.model).toList();
                  showModalBottomSheet(
                    context: context,
                    builder: (BuildContext context) => DeviceGroupSelectionSheet(
                      availableGroups: groupEntites,
                      onTapGroup: (g) => parentVM.changeDeviceGroup(selectedDeviceVM.deviceEntity, g?.id),
                      title: 'Change Device Group',
                      subtitle: 'Select the group to which device "${selectedDeviceVM.name}" belongs:',
                    ),
                  );

                  break;
                }
              default:
                break;
            }
          }
        }
      });
    }
  }
}
