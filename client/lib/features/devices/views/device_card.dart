import 'package:borneo_app/core/services/devices/device_module_registry.dart';
import 'package:borneo_app/devices/view_models/abstract_device_summary_view_model.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/features/devices/view_models/grouped_devices_view_model.dart';
import 'package:borneo_app/features/devices/views/device_error_dialog.dart';
import 'package:borneo_app/features/devices/views/device_group_selection_sheet.dart';
import 'package:borneo_app/routes/app_routes.dart';
import 'package:borneo_app/shared/widgets/confirmation_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:provider/provider.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({super.key});

  void _openDevicePage(BuildContext context, DeviceEntity device) {
    final vm = context.read<AbstractDeviceSummaryViewModel>();
    Navigator.of(context).pushNamed(AppRoutes.makeDeviceScreenRoute(device.driverID), arguments: device).then((_) {
      if (!vm.isDisposed) {
        vm.notifyListeners();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<AbstractDeviceSummaryViewModel>();
    final device = vm.deviceEntity;
    final moduleMeta = context.read<IDeviceModuleRegistry>().metaModules[device.driverID]!;

    return Selector<AbstractDeviceSummaryViewModel, ({bool isOnline, bool isPowerOn, String name})>(
      selector: (_, vm) => (isOnline: vm.isOnline, isPowerOn: vm.isPowerOn, name: vm.deviceEntity.name),
      builder: (context, status, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final bgColor = colorScheme.surfaceContainer;
        final fgColor = colorScheme.onSurface;

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            color: bgColor,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: vm.isBusy ? null : () => _openDevicePage(context, vm.deviceEntity),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 4, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top row: small device icon + name (left) + three-dot menu (right)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          moduleMeta.deviceIconBuilder(context, 24, status.isOnline),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              status.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                context,
                              ).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                            ),
                          ),
                          _buildPopupMenu(context, fgColor),
                        ],
                      ),
                      // Central content area
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(2, 4, 8, 8),
                          child: moduleMeta.summaryContentBuilder != null
                              ? moduleMeta.summaryContentBuilder!(context, vm)
                              : Center(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final iconSize = constraints.maxHeight * 0.72;
                                      return moduleMeta.deviceIconBuilder(context, iconSize, status.isOnline);
                                    },
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Status row
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildStatusRow(context, status, vm, moduleMeta.secondaryStatesBuilder, fgColor),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusRow(
    BuildContext context,
    ({bool isOnline, bool isPowerOn, String name}) status,
    AbstractDeviceSummaryViewModel vm,
    List<Widget> Function(BuildContext, AbstractDeviceSummaryViewModel) secondaryStatesBuilder,
    Color fgColor,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!status.isOnline) {
      final errorMessage = vm.deviceEntity.lastErrorMessage;
      if (errorMessage != null && errorMessage.isNotEmpty) {
        return Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => DeviceErrorDialog(errorMessage: errorMessage),
              );
            },
            borderRadius: BorderRadius.circular(4),
            child: Row(
              spacing: 4,
              children: [
                Icon(Icons.error_outline, size: 24, color: colorScheme.error),
                Text(
                  context.translate('OFF-LINE'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.error),
                ),
              ],
            ),
          ),
        );
      }
      return Row(
        children: [
          Icon(Icons.wifi_off, size: 12, color: colorScheme.error),
          const SizedBox(width: 4),
          Text(
            context.translate('OFF-LINE'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.error),
          ),
        ],
      );
    }

    if (!status.isPowerOn) {
      return Row(
        children: [
          Icon(Icons.power_settings_new, size: 12, color: fgColor.withValues(alpha: 0.6)),
          const SizedBox(width: 4),
          Text(
            context.translate('OFF'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fgColor.withValues(alpha: 0.6)),
          ),
        ],
      );
    }

    final widgets = secondaryStatesBuilder(context, vm);
    if (widgets.isEmpty) return const SizedBox(height: 14);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < widgets.length; i++) ...[
            if (i > 0)
              SizedBox(
                height: 12,
                width: 12,
                child: Icon(Icons.circle, size: 4, color: fgColor.withValues(alpha: 0.38)),
              ),
            widgets[i],
          ],
        ],
      ),
    );
  }

  Widget _buildPopupMenu(BuildContext context, Color fgColor) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      iconSize: 18,
      icon: Icon(Icons.more_vert, color: fgColor.withValues(alpha: 0.7)),
      onSelected: (value) => _handleMenuAction(context, value),
      itemBuilder: (BuildContext ctx) {
        final gvm = ctx.read<GroupedDevicesViewModel>();
        final dvm = ctx.read<AbstractDeviceSummaryViewModel>();
        final showChangeGroup = gvm.groups.length > 1;

        return <PopupMenuEntry<String>>[
          if (!dvm.isOnline) PopupMenuItem<String>(value: 'reconnect', child: Text(context.translate('Reconnect'))),

          if (!dvm.isOnline) const PopupMenuDivider(),

          if (showChangeGroup)
            PopupMenuItem<String>(value: 'change-group', child: Text(context.translate('Change group...'))),

          if (dvm.canDelete) PopupMenuItem<String>(value: 'delete', child: Text(context.translate('Delete...'))),
        ];
      },
    );
  }

  void _handleMenuAction(BuildContext context, String value) {
    final parentVM = context.read<GroupedDevicesViewModel>();
    final selectedDeviceVM = context.read<AbstractDeviceSummaryViewModel>();
    switch (value) {
      case 'delete':
        ConfirmationSheet.show(
          context,
          message: context.translate(
            'Are you sure to delete the device "{deviceName}"?',
            nArgs: {'deviceName': selectedDeviceVM.name},
          ),
          okPressed: () {
            parentVM.deleteDevice(selectedDeviceVM.deviceEntity.id);
          },
        );
        break;
      case 'change-group':
        final groupEntities = parentVM.groups.where((gvm) => !gvm.isDummy).map((gvm) => gvm.model).toList();
        showModalBottomSheet(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          context: context,
          builder: (BuildContext ctx) => DeviceGroupSelectionSheet(
            availableGroups: groupEntities,
            onTapGroup: (g) => parentVM.changeDeviceGroup(selectedDeviceVM.deviceEntity, g?.id),
            title: context.translate('Change Device Group'),
            subtitle: context.translate(
              'Select the group to which device "{deviceName}" belongs:',
              nArgs: {'deviceName': selectedDeviceVM.name},
            ),
            excludeGroupId: selectedDeviceVM.deviceEntity.groupID,
          ),
        );
        break;
      default:
        break;
    }
  }
}
