import 'dart:async';

import 'package:borneo_app/core/events/app_events.dart';
import 'package:borneo_app/core/services/devices/ota/ota_service.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:flutter/foundation.dart';
import 'package:borneo_app/core/services/devices/ota/ota_providers.dart';
import 'package:borneo_kernel_abstractions/models/bound_device.dart';
import 'package:event_bus/event_bus.dart';

import '../../shared/view_models/base_view_model.dart';

enum OtaState { idle, checking, upToDate, updateAvailable, upgrading, success, error }

class DeviceOtaViewModel extends BaseViewModel with ViewModelEventBusMixin {
  final OtaProvider otaProvider;
  final BoundDevice boundDevice;

  /// Returns whether the device is currently reachable.
  /// Provided as a callback so the getter stays live after construction.
  final bool Function() _isOnlineProvider;

  OtaState _state = OtaState.idle;
  OtaState get state => _state;

  OtaUpgradeInfo? _upgradeInfo;
  OtaUpgradeInfo? get upgradeInfo => _upgradeInfo;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  CancellationToken? _cancelToken;

  bool get isChecking => _state == OtaState.checking;
  bool get isUpgrading => _state == OtaState.upgrading;
  bool get isSucceeded => _state == OtaState.success;
  bool get isError => _state == OtaState.error;
  bool get isUpToDate => _state == OtaState.upToDate;
  bool get hasUpdate => _state == OtaState.updateAvailable;

  bool get canCheck => _state != OtaState.checking && _state != OtaState.upgrading;

  bool get isOnline => _isOnlineProvider();

  bool get canUpgrade => isOnline && _state == OtaState.updateAvailable && (_upgradeInfo?.canUpgrade ?? false);

  /// In debug builds the user can force-push firmware even when already up to date.
  bool get canForceUpgrade =>
      kDebugMode &&
      isOnline &&
      _upgradeInfo != null &&
      (_state == OtaState.upToDate || _state == OtaState.updateAvailable);

  DeviceOtaViewModel({
    required this.otaProvider,
    required this.boundDevice,
    required bool Function() isOnlineProvider,
    required EventBus eventBus,
    required super.gt,
    super.logger,
  }) : _isOnlineProvider = isOnlineProvider {
    super.globalEventBus = eventBus;
  }

  Future<void> initialize() async {
    await checkUpdate();
  }

  Future<void> checkUpdate() async {
    if (!canCheck) return;
    _errorMessage = null;
    _upgradeInfo = null;
    _setState(OtaState.checking);
    _cancelToken = CancellationToken();
    final service = otaProvider.create(gt: gt, logger: logger);
    try {
      final info = await service.checkNewVersion(boundDevice, cancelToken: _cancelToken);
      _upgradeInfo = info;
      _setState(info.canUpgrade ? OtaState.updateAvailable : OtaState.upToDate);
    } catch (e, st) {
      _errorMessage = e.toString();
      _setState(OtaState.error);
      logger?.e('OTA check failed', error: e, stackTrace: st);
    }
  }

  Future<void> startUpgrade({bool force = false}) async {
    if (!force && !canUpgrade) return;
    if (force && !canForceUpgrade) return;
    _errorMessage = null;
    _setState(OtaState.upgrading);
    _cancelToken = CancellationToken();
    final service = otaProvider.create(gt: gt, logger: logger);
    try {
      await service.upgrade(boundDevice, cancelToken: _cancelToken, force: force);
      if (isDisposed) return;
      _setState(OtaState.success);
    } on CancelledException {
      if (isDisposed) return;
      // Restore to updateAvailable so the user can retry
      _setState(_upgradeInfo?.canUpgrade == true ? OtaState.updateAvailable : OtaState.upToDate);
    } catch (e, st) {
      _errorMessage = e.toString();
      _setState(OtaState.error);
      logger?.e('OTA upgrade failed', error: e, stackTrace: st);
    }
  }

  /// Cancels an in-progress upgrade.
  void cancelUpgrade() {
    if (!isUpgrading) return;
    _cancelToken?.cancel();
  }

  void _setState(OtaState newState) {
    _state = newState;
    if (!isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  void notifyAppError(String message, {Object? error, StackTrace? stackTrace}) {
    globalEventBus.fire(AppErrorEvent(message, error: error, stackTrace: stackTrace));
  }
}
