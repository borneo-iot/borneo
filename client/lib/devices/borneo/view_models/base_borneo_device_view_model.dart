import 'dart:async';

import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_app/features/devices/view_models/base_device_view_model.dart';
import 'package:borneo_app/core/infrastructure/timezone.dart';
import 'package:borneo_common/io/net/rssi.dart';
import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:flutter/material.dart';

abstract class BaseBorneoDeviceViewModel extends BaseDeviceViewModel {
  GeneralBorneoDeviceStatus? get borneoDeviceStatus =>
      isAvailable && isOnline ? wotThing.getProperty<GeneralBorneoDeviceStatus>('generalStatus') : null;

  IBorneoDeviceApi get borneoDeviceApi => super.boundDevice!.driver as IBorneoDeviceApi;

  bool get isOn => isAvailable && (wotThing.getProperty<bool>('on') ?? false);

  bool get canMeasureVoltage => super.isOnline && isOn && borneoDeviceStatus?.powerVoltage != null;

  final ValueNotifier<double?> currentVoltage = ValueNotifier<double?>(null);
  final IAppNotificationService notification;

  StreamSubscription? _generalStatusSubscription;
  StreamSubscription? _onOffSubscription;

  @override
  RssiLevel? get rssiLevel =>
      borneoDeviceStatus?.wifiRssi != null ? RssiLevelExtension.fromRssi(borneoDeviceStatus!.wifiRssi!) : null;

  String? get deviceTimezone => isAvailable ? wotThing.getProperty<String>('timezone') : null;

  String? _localPosixTimezone;
  String? get localPosixTimezone => _localPosixTimezone;

  bool get hasTimezoneMismatch =>
      deviceTimezone != null && _localPosixTimezone != null && deviceTimezone != _localPosixTimezone;

  BaseBorneoDeviceViewModel({
    required super.deviceManager,
    required super.globalEventBus,
    required this.notification,
    required super.wotThing,
    required super.gt,
    super.logger,
  }) {
    _subscribeToGeneralStatus();
  }

  @override
  @protected
  Future<void> onInitialize() async {
    await _initializeTimezone();
  }

  @override
  void dispose() {
    if (!isDisposed) {
      _unsubscribeFromGeneralStatus();
      super.dispose();
    }
  }

  @override
  void onDeviceBound() {}

  @override
  void onDeviceRemoved() {}

  @override
  void onDeviceDeleted() {
    _unsubscribeFromGeneralStatus();
    super.onDeviceDeleted();
  }

  Future<void> _initializeTimezone() async {
    try {
      final tzc = TimezoneConverter();
      await tzc.init();
      _localPosixTimezone = await tzc.getLocalPosixTimezone();
    } catch (e, stackTrace) {
      notifyAppError(
        gt.translate('Failed to initialize local timezone: {msg}', nArgs: {'msg': e.toString()}),
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _subscribeToGeneralStatus() {
    _generalStatusSubscription = wotThing.findProperty('generalStatus')?.value.onUpdate.listen((status) {
      if (!isAvailable || isDisposed) return;
      notifyListeners();
    });

    _onOffSubscription = wotThing.findProperty('on')?.value.onUpdate.listen((value) {
      if (!isAvailable || isDisposed) return;
      notifyListeners();
    });
  }

  void _unsubscribeFromGeneralStatus() {
    _generalStatusSubscription?.cancel();
    _generalStatusSubscription = null;
    _onOffSubscription?.cancel();
    _onOffSubscription = null;
  }

  Future<void> syncDeviceTimezone() async {
    final success = await _syncDeviceTimezone();
    if (success) {
      notification.showSuccess(gt.translate('Timezone synchronized successfully'));
    }
  }

  Future<bool> _syncDeviceTimezone() async {
    if (!isBusy || !super.isOnline || _localPosixTimezone == null) {
      return false;
    }
    setBusy(true);

    try {
      await borneoDeviceApi.setTimeZone(super.boundDevice!.device, _localPosixTimezone!);
      wotThing.findProperty('timezone')?.value.notifyOfExternalUpdate(_localPosixTimezone);
      return true;
    } catch (e, stackTrace) {
      notifyAppError(
        gt.translate('Failed to sync timezone: {msg}', nArgs: {'msg': e.toString()}),
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      setBusy(false);
    }
  }
}
