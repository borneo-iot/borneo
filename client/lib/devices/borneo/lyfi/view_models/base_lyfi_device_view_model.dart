import 'dart:async';
import 'package:borneo_app/devices/borneo/view_models/base_borneo_device_view_model.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/coap_driver_data.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:borneo_wot/borneo/lyfi/wot_thing.dart';
import 'package:flutter/material.dart';

abstract class BaseLyfiDeviceViewModel extends BaseBorneoDeviceViewModel {
  ILyfiDeviceApi get lyfiDeviceApi => super.boundDevice!.driver as ILyfiDeviceApi;
  LyfiDeviceInfo get lyfiDeviceInfo => lyfiThing.getProperty<LyfiDeviceInfo>('lyfiDeviceInfo')!;

  LyfiDeviceStatus? get lyfiDeviceStatus => isAvailable ? lyfiThing.getProperty<LyfiDeviceStatus>('lyfiStatus') : null;

  AcclimationSettings? get acclimationSettings =>
      isAvailable ? lyfiThing.getProperty<AcclimationSettings>('acclimation') : null;

  bool get acclimationEnabled => isAvailable && (lyfiThing.getProperty<bool>('acclimationEnabled') ?? false);

  bool get acclimationActivated => isAvailable && (lyfiThing.getProperty<bool>('acclimationActivated') ?? false);

  MoonConfig? get moonConfig => isAvailable ? lyfiThing.getProperty<MoonConfig>('moonConfig') : null;

  MoonStatus? get moonStatus => isAvailable ? lyfiThing.getProperty<MoonStatus>('moonStatus') : null;

  bool get cloudActivated => isAvailable && (lyfiThing.getProperty<bool>('cloudActivated') ?? false);

  DateTime? get deviceTimestamp => isAvailable ? lyfiThing.getProperty<DateTime>('timestamp') : null;

  LyfiThing get lyfiThing => wotThing as LyfiThing;

  double? get nominalPower => lyfiDeviceInfo.nominalPower;
  bool get canMeasureCurrent =>
      super.isOnline && !super.isSuspectedOffline && isOn && lyfiThing.getProperty<double?>('current') != null;

  bool get canMeasurePower => canMeasureCurrent && canMeasureVoltage;

  StreamSubscription<String>? _stateSubscription;
  StreamSubscription<String>? _modeSubscription;
  StreamSubscription<LyfiDeviceStatus>? _statusSubscription;

  final ValueNotifier<double?> currentCurrent = ValueNotifier<double?>(null);
  final ValueNotifier<double?> currentWatts = ValueNotifier<double?>(null);

  bool hasFan = false;
  bool hasTempSensor = false;

  @override
  @protected
  Future<void> onInitialize() async {
    super.onInitialize();
    if (super.boundDevice != null) {
      final supportedResourcePaths = super.boundDevice!.device.data<LyfiCoapDriverData>().supportedResourcePaths;
      this.hasFan =
          supportedResourcePaths.contains(LyfiPaths.fanMode.path) ||
          supportedResourcePaths.contains(LyfiPaths.fanPower.path);
      this.hasTempSensor = supportedResourcePaths.contains(LyfiPaths.currentTemp.path);
    }

    _subscribeToLyfiThing();
  }

  void _subscribeToLyfiThing() {
    _stateSubscription =
        lyfiThing.findProperty('state')?.value.onUpdate.listen((stateName) {
              if (isAvailable && !isDisposed) {
                notifyListeners();
              }
            })
            as StreamSubscription<String>?;
    _modeSubscription =
        lyfiThing.findProperty('mode')?.value.onUpdate.listen((modeName) {
              if (isAvailable && !isDisposed) {
                notifyListeners();
              }
            })
            as StreamSubscription<String>?;

    _statusSubscription =
        lyfiThing.findProperty('lyfiStatus')?.value.onUpdate.listen((status) {
              if (isAvailable && !isDisposed) {
                notifyListeners();
              }
            })
            as StreamSubscription<LyfiDeviceStatus>?;
  }

  @override
  void onDeviceBound() {
    super.onDeviceBound();
    _unsubscribeFromLyfiThing();
    _subscribeToLyfiThing();
  }

  @override
  void onDeviceRemoved() {
    _unsubscribeFromLyfiThing();
    super.onDeviceRemoved();
  }

  @override
  void onDeviceDeleted() {
    _unsubscribeFromLyfiThing();
    super.onDeviceDeleted();
  }

  void _unsubscribeFromLyfiThing() {
    _stateSubscription?.cancel();
    _stateSubscription = null;
    _modeSubscription?.cancel();
    _modeSubscription = null;
    _statusSubscription?.cancel();
    _statusSubscription = null;
  }

  LyfiMode get mode => LyfiMode.fromString(lyfiThing.getProperty<String>('mode') ?? 'manual');

  void setMode(LyfiMode newMode) {
    if (newMode == this.mode) {
      return;
    }
    lyfiThing.performAction('switchMode', {'mode': newMode.name})!.start();
  }

  LyfiState get state => LyfiState.fromString(lyfiThing.getProperty<String>('state') ?? 'normal');

  void setState(LyfiState newState) {
    if (newState == this.state) {
      return;
    }
    lyfiThing.performAction('switchState', {'state': newState.name})!.start();
  }

  bool get isLocked => state.isLocked;

  BaseLyfiDeviceViewModel({
    required super.deviceManager,
    required super.globalEventBus,
    required super.notification,
    required super.wotThing,
    required super.gt,
    super.logger,
  });

  @override
  void dispose() {
    _unsubscribeFromLyfiThing();
    super.dispose();
  }
}
