import 'package:borneo_app/core/services/local_service.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/lyfi_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/summary_device_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/lyfi_view.dart';
import 'package:borneo_app/devices/borneo/lyfi/widgets/summary_card_center.dart';
import 'package:borneo_app/devices/borneo/lyfi/widgets/summary_secondary_states.dart';
import 'package:borneo_app/devices/view_models/abstract_device_summary_view_model.dart';
import 'package:borneo_app/features/devices/models/device_module_metadata.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_wot/borneo/lyfi/wot_thing.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext.dart';
import 'package:logger/logger.dart';
import 'package:lw_wot/wot.dart';

import 'package:provider/provider.dart';

import 'package:borneo_kernel/drivers/borneo/lyfi/metadata.dart';

class LyfiDeviceModuleMetadata extends DeviceModuleMetadata {
  LyfiDeviceModuleMetadata()
    : super(
        id: kLyfiDriverID,
        name: kLyfiDriverName,
        driverDescriptor: borneoLyfiDriverDescriptor,
        detailsViewBuilder: (_) => LyfiView(),
        detailsViewModelBuilder: (context, deviceID) => LyfiViewModel(
          deviceManager: context.read<IDeviceManager>(),
          globalEventBus: context.read<EventBus>(),
          notification: context.read<IAppNotificationService>(),
          wotThing: context.read<IDeviceManager>().getWotThing(deviceID),
          localeService: context.read<ILocaleService>(),
          gt: GettextLocalizations.of(context),
          logger: context.read<Logger>(),
        ),
        deviceIconBuilder: _buildDeviceIcon,
        primaryStateIconBuilder: _buildPrimaryStateIcon,
        secondaryStatesBuilder: _secondaryStatesBuilder,
        summaryContentBuilder: _buildCardCenter,
        createSummaryVM: (dev, dm, bus, gt) => LyfiSummaryDeviceViewModel(dev, dm, bus, gt: gt),
        createWotThing: _createWotThing,
      );

  static Widget _buildDeviceIcon(BuildContext context, double iconSize, bool isOnline) {
    return Icon(Icons.light_outlined, size: iconSize, color: Theme.of(context).colorScheme.primary);
  }

  static Widget _buildPrimaryStateIcon(BuildContext context, double iconSize) {
    return Icon(Icons.light_mode_outlined, size: iconSize, color: Theme.of(context).colorScheme.onSurface);
  }

  static List<Widget> _secondaryStatesBuilder(BuildContext context, AbstractDeviceSummaryViewModel vm) {
    return const [LyfiSummaryStateLabel(), LyfiSummaryModeLabel()];
  }

  /// Custom card center: bar chart of per-channel brightness.
  /// Falls back to a large offline icon when disconnected, otherwise the device
  /// icon when powered off or data is unavailable.
  static Widget _buildCardCenter(BuildContext context, AbstractDeviceSummaryViewModel vm) =>
      const LyfiSummaryCardCenter();

  static Future<WotThing> _createWotThing(
    DeviceEntity device,
    IDeviceManager deviceManager, {
    Logger? logger,
    CancellationToken? cancelToken,
  }) async => LyfiThing(kernel: deviceManager.kernel, deviceId: device.id, title: device.name, logger: logger);
}
