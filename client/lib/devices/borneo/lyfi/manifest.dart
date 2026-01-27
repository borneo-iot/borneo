import 'package:borneo_app/core/services/local_service.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/lyfi_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/summary_device_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/lyfi_view.dart';
import 'package:borneo_app/devices/view_models/abstract_device_summary_view_model.dart';
import 'package:borneo_app/features/devices/models/device_module_metadata.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_common/exceptions.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';
import 'package:logger/logger.dart';
import 'package:lw_wot/wot.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/wot.dart';
import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/api.dart';

import 'package:provider/provider.dart';

import 'package:borneo_kernel/drivers/borneo/lyfi/metadata.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';

class LyfiDeviceModuleMetadata extends DeviceModuleMetadata {
  LyfiDeviceModuleMetadata()
    : super(
        id: kLyfiDriverID,
        name: kLyfiDriverName,
        driverDescriptor: borneoLyfiDriverDescriptor,
        detailsViewBuilder: (_) => LyfiView(),
        detailsViewModelBuilder: (context, deviceID) => LyfiViewModel(
          deviceID: deviceID,
          deviceManager: context.read<IDeviceManager>(),
          globalEventBus: context.read<EventBus>(),
          notification: context.read<IAppNotificationService>(),
          localeService: context.read<ILocaleService>(),
          logger: context.read<Logger>(),
          gt: context.read<GettextLocalizations>(),
        ),
        deviceIconBuilder: _buildDeviceIcon,
        primaryStateIconBuilder: _buildPrimaryStateIcon,
        secondaryStatesBuilder: _secondaryStatesBuilder,
        createSummaryVM: (dev, dm, bus) => LyfiSummaryDeviceViewModel(dev, dm, bus),
        createWotThing: _createWotThing,
      );

  static Widget _buildDeviceIcon(BuildContext context, double iconSize, bool isOnline) {
    return Icon(
      Icons.light_outlined,
      size: iconSize,
      color: isOnline
          ? Theme.of(context).colorScheme.onPrimaryContainer
          : Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.38),
    );
  }

  static Widget _buildPrimaryStateIcon(BuildContext context, double iconSize) {
    return Icon(Icons.light_mode_outlined, size: iconSize, color: Theme.of(context).colorScheme.onSurface);
  }

  static List<Widget> _secondaryStatesBuilder(BuildContext context, AbstractDeviceSummaryViewModel vm) {
    final lvm = vm as LyfiSummaryDeviceViewModel;
    final modeWidget = Text(_modeText(context, lvm.ledMode), style: Theme.of(context).textTheme.labelSmall);
    final stateWidget = Text(_stateText(context, lvm.ledState), style: Theme.of(context).textTheme.labelSmall);
    return [modeWidget, stateWidget];
  }

  static String _modeText(BuildContext context, LyfiMode? mode) {
    switch (mode) {
      case LyfiMode.manual:
        return context.translate('Manual');
      case LyfiMode.scheduled:
        return context.translate('Scheduled');
      case LyfiMode.sun:
        return context.translate('Sun Simulation');
      default:
        return '-';
    }
  }

  static String _stateText(BuildContext context, LyfiState? state) {
    switch (state) {
      case LyfiState.normal:
        return context.translate('Running');
      case LyfiState.dimming:
        return context.translate('Dimming');
      case LyfiState.temporary:
        return context.translate('Temporary');
      case LyfiState.preview:
        return context.translate('Preview');
      default:
        return '-';
    }
  }

  static Future<WotThing> _createWotThing(DeviceEntity device, IDeviceManager deviceManager, {Logger? logger}) async {
    // Check if device is bound to get access to APIs
    if (!deviceManager.isBound(device.id)) {
      // Device not bound, create a basic WotThing with default values
      // This can happen during initialization before device binding is complete
      return _createBasicWotThing(device);
    }

    try {
      // Get the bound device and extract APIs
      final boundDevice = deviceManager.getBoundDevice(device.id);
      final borneoApi = boundDevice.api<IBorneoDeviceApi>();
      final lyfiApi = boundDevice.api<ILyfiDeviceApi>();
      final deviceEvents = boundDevice.device.driverData.deviceEvents;

      // Create the real LyfiThing with API connections
      final lyfiThing = LyfiThing(
        device: boundDevice.device,
        deviceEvents: deviceEvents,
        borneoApi: borneoApi,
        lyfiApi: lyfiApi,
        title: device.name,
        logger: logger,
      );

      // Initialize the LyfiThing asynchronously (hardware binding)
      // Note: This doesn't block creation, initialization happens in background
      await lyfiThing.initialize();
      return lyfiThing;
    } catch (e) {
      // If API access fails, fall back to basic WotThing
      throw InvalidOperationException(message: 'Warning: Failed to create LyfiThing with APIs for ${device.id}: $e');
    }
  }

  /// Creates a basic WotThing when device is not bound or APIs are unavailable
  static WotThing _createBasicWotThing(DeviceEntity device) {
    final thing = WotThing(
      id: device.id,
      title: device.name,
      type: ['Light'],
      description: 'Borneo LyFi LED Controller',
    );

    // Add Lyfi-specific properties with default values
    thing.addProperty(
      WotProperty(
        thing: thing,
        name: 'on',
        value: WotValue(initialValue: false),
        metadata: WotPropertyMetadata(title: 'On/Off', type: 'boolean', description: 'Whether the light is turned on'),
      ),
    );

    thing.addProperty(
      WotProperty(
        thing: thing,
        name: 'state',
        value: WotValue(initialValue: 'normal'),
        metadata: WotPropertyMetadata(
          title: 'State',
          type: 'string',
          description: 'Current light state',
          enumValues: ['normal', 'dimming', 'temporary', 'preview'],
        ),
      ),
    );

    thing.addProperty(
      WotProperty(
        thing: thing,
        name: 'mode',
        value: WotValue(initialValue: 'manual'),
        metadata: WotPropertyMetadata(
          title: 'Mode',
          type: 'string',
          description: 'Current light mode',
          enumValues: ['manual', 'scheduled', 'sun'],
        ),
      ),
    );

    thing.addProperty(
      WotProperty(
        thing: thing,
        name: 'color',
        value: WotValue(initialValue: '#FFFFFF'),
        metadata: WotPropertyMetadata(title: 'Color', type: 'string', description: 'Current light color'),
      ),
    );

    return thing;
  }
}
