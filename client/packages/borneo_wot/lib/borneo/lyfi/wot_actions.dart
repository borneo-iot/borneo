// dart format width=120

import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:borneo_kernel_abstractions/device.dart';
import 'package:logger/logger.dart';
import 'package:lw_wot/wot.dart';

/// Custom action for switching Lyfi states
class LyfiSwitchStateAction extends WotAction<Map<String, dynamic>> {
  final ILyfiDeviceApi lyfiApi;
  final Device device;
  final Logger? logger;

  LyfiSwitchStateAction({
    required super.id,
    required super.thing,
    required this.lyfiApi,
    required this.device,
    required super.input,
    this.logger,
  }) : super(name: 'switchState');

  @override
  Future<void> performAction() async {
    try {
      final targetState = LyfiState.fromString(input['state']);
      await lyfiApi.switchState(device, targetState);
      thing.findProperty('state')?.value.notifyOfExternalUpdate(input['state']);
    } catch (e, st) {
      logger?.e('switchState failed for device ${device.id}', error: e, stackTrace: st);
      rethrow;
    }
  }
}

/// Custom action for switching Lyfi modes
class LyfiSwitchModeAction extends WotAction<Map<String, dynamic>?> {
  final ILyfiDeviceApi lyfiApi;
  final Device device;
  final Logger? logger;

  LyfiSwitchModeAction({
    required super.id,
    required super.thing,
    required this.lyfiApi,
    required this.device,
    required super.input,
    this.logger,
  }) : super(name: 'switchMode');

  @override
  Future<void> performAction() async {
    try {
      final targetMode = LyfiMode.fromString(input!['mode']);
      final targetColor = input?['color'];
      await lyfiApi.switchMode(device, targetMode);
      thing.findProperty('mode')?.value.notifyOfExternalUpdate(input!['mode']);
      if (targetColor != null && targetMode == LyfiMode.manual) {
        await lyfiApi.setColor(device, targetColor);
      }
    } catch (e, st) {
      logger?.e('switchMode failed for device ${device.id}', error: e, stackTrace: st);
      rethrow;
    }
  }
}

/// Custom action for setting LED colors
class LyfiSetColorAction extends WotAction<Map<String, dynamic>> {
  final List<int> color;
  final ILyfiDeviceApi lyfiApi;
  final Device device;
  final Logger? logger;

  LyfiSetColorAction({
    required super.id,
    required super.thing,
    required this.color,
    required this.lyfiApi,
    required this.device,
    this.logger,
  }) : super(name: 'setColor', input: {'color': color});

  @override
  Future<void> performAction() async {
    try {
      await lyfiApi.setColor(device, color);
      thing.findProperty('color')!.value.notifyOfExternalUpdate(color);
    } catch (e, st) {
      logger?.e('setColor failed for device ${device.id}', error: e, stackTrace: st);
      rethrow;
    }
  }
}

/// Custom action for setting LED schedule
class LyfiSetScheduleAction extends WotAction<Map<String, dynamic>> {
  final ScheduleTable schedule;
  final ILyfiDeviceApi lyfiApi;
  final Device device;
  final Logger? logger;

  LyfiSetScheduleAction({
    required super.id,
    required super.thing,
    required this.schedule,
    required this.lyfiApi,
    required this.device,
    this.logger,
  }) : super(name: 'setSchedule', input: {'schedule': schedule.map((s) => s.toPayload()).toList()});

  @override
  Future<void> performAction() async {
    try {
      await lyfiApi.setSchedule(device, schedule);
      thing.findProperty('schedule')!.value.notifyOfExternalUpdate(schedule);
    } catch (e, st) {
      logger?.e('setSchedule failed for device ${device.id}', error: e, stackTrace: st);
      rethrow;
    }
  }
}

/// Custom action for setting acclimation settings
class LyfiSetAcclimationAction extends WotAction<Map<String, dynamic>> {
  final ILyfiDeviceApi lyfiApi;
  final Device device;
  final Logger? logger;

  LyfiSetAcclimationAction({
    required super.id,
    required super.thing,
    required this.lyfiApi,
    required this.device,
    required super.input,
    this.logger,
  }) : super(name: 'setAcclimation');

  @override
  Future<void> performAction() async {
    try {
      final settings = AcclimationSettings.fromMap(input);
      await lyfiApi.setAcclimation(device, settings);
      thing.findProperty('acclimation')?.value.notifyOfExternalUpdate(settings);
      thing.findProperty('acclimationEnabled')?.value.notifyOfExternalUpdate(settings.enabled);

      // Temporary Lyfi status property for refactoring - TODO: Remove after refactoring
      final status = await lyfiApi.getLyfiStatus(device);
      thing.findProperty('lyfiStatus')?.value.notifyOfExternalUpdate(status);
      thing.findProperty('acclimationActivated')?.value.notifyOfExternalUpdate(status.acclimationActivated);
    } catch (e, st) {
      logger?.e('setAcclimation failed for device ${device.id}', error: e, stackTrace: st);
      rethrow;
    }
  }
}

/// Custom action for setting geographic location
class LyfiSetLocationAction extends WotAction<Map<String, dynamic>> {
  final GeoLocation location;
  final ILyfiDeviceApi lyfiApi;
  final Device device;
  final Logger? logger;

  LyfiSetLocationAction({
    required super.id,
    required super.thing,
    required this.location,
    required this.lyfiApi,
    required this.device,
    this.logger,
  }) : super(name: 'setLocation', input: {'lat': location.lat, 'lng': location.lng});

  @override
  Future<void> performAction() async {
    try {
      await lyfiApi.setLocation(device, location);
    } catch (e, st) {
      logger?.e('setLocation failed for device ${device.id}', error: e, stackTrace: st);
      rethrow;
    }
  }
}

/// Custom action for setting LED correction method
class LyfiSetCorrectionMethodAction extends WotAction<Map<String, dynamic>> {
  final LedCorrectionMethod method;
  final ILyfiDeviceApi lyfiApi;
  final Device device;
  final Logger? logger;

  LyfiSetCorrectionMethodAction({
    required super.id,
    required super.thing,
    required this.method,
    required this.lyfiApi,
    required this.device,
    this.logger,
  }) : super(name: 'setCorrectionMethod', input: {'method': method.name});

  @override
  Future<void> performAction() async {
    try {
      await lyfiApi.setCorrectionMethod(device, method);
    } catch (e, st) {
      logger?.e('setCorrectionMethod failed for device ${device.id}', error: e, stackTrace: st);
      rethrow;
    }
  }
}

/// Custom action for setting power behavior
class LyfiSetPowerBehaviorAction extends WotAction<Map<String, dynamic>> {
  final PowerBehavior behavior;
  final IBorneoDeviceApi borneoApi;
  final Device device;
  final Logger? logger;

  LyfiSetPowerBehaviorAction({
    required super.id,
    required super.thing,
    required this.behavior,
    required this.borneoApi,
    required this.device,
    this.logger,
  }) : super(name: 'setPowerBehavior', input: {'behavior': behavior.name});

  @override
  Future<void> performAction() async {
    try {
      await borneoApi.setPowerBehavior(device, behavior);
    } catch (e, st) {
      logger?.e('setPowerBehavior failed for device ${device.id}', error: e, stackTrace: st);
      rethrow;
    }
  }
}

/// Custom action for setting moon configuration
class LyfiSetMoonConfigAction extends WotAction<Map<String, dynamic>> {
  final MoonConfig config;
  final ILyfiDeviceApi lyfiApi;
  final Device device;
  final Logger? logger;

  LyfiSetMoonConfigAction({
    required super.id,
    required super.thing,
    required this.config,
    required this.lyfiApi,
    required this.device,
    this.logger,
  }) : super(name: 'setMoonConfig', input: {'config': config.toPayload()});

  @override
  Future<void> performAction() async {
    try {
      await lyfiApi.setMoonConfig(device, config);
      final curve = await lyfiApi.getMoonCurve(device);
      thing.findProperty('moonConfig')!.value.notifyOfExternalUpdate(config);
      thing.findProperty('moonCurve')!.value.notifyOfExternalUpdate(curve);
    } catch (e, st) {
      logger?.e('setMoonConfig failed for device ${device.id}', error: e, stackTrace: st);
      rethrow;
    }
  }
}
