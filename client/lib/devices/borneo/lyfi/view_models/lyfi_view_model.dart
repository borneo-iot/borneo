import 'dart:async';
import 'dart:io';
import 'package:borneo_app/core/services/local_service.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/base_lyfi_device_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/settings_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/sun_editor_view_model.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';
import 'package:intl/intl.dart';

import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/manual_editor_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/schedule_editor_view_model.dart';

import 'editor/ieditor.dart';

class LyfiViewModel extends BaseLyfiDeviceViewModel {
  static const initializationTimeout = Duration(seconds: 5);
  static const Duration _commandTimeout = Duration(seconds: 3);
  static const Duration _rapidProbeTimeout = Duration(seconds: 1);
  static const Duration _rapidProbeInterval = Duration(milliseconds: 600);
  static const int _rapidProbeAttempts = 3;
  static const int tempMax = 105;
  static final int tempSetpoint = 45;

  static final DateFormat deviceDateFormat = DateFormat('yyyy-MM-dd HH:mm');

  bool _isDisposed = false;

  final GettextLocalizations gt;

  final ILocaleService localeService;
  Future<void>? _rapidProbeTask;

  ILyfiDeviceApi get _deviceApi => super.borneoDeviceApi as ILyfiDeviceApi;

  Duration _temporaryDuration = Duration.zero;
  Duration get temporaryDuration => _temporaryDuration;

  final ValueNotifier<Duration> _temporaryRemaining = ValueNotifier<Duration>(Duration.zero);
  ValueNotifier<Duration> get temporaryRemaining => _temporaryRemaining;

  Duration get commandTimeout => _commandTimeout;

  bool get canLockOrUnlock => !isBusy && !isSuspectedOffline && isOn;
  bool get canUnlock =>
      !isBusy &&
      super.isOnline &&
      !isSuspectedOffline &&
      isOn &&
      isLocked &&
      (super.state == LyfiState.normal || super.state == LyfiState.temporary);

  bool get canChangeSettings =>
      !isBusy &&
      super.isOnline &&
      !isSuspectedOffline &&
      isLocked &&
      (super.state == LyfiState.normal || super.state == LyfiState.temporary);

  bool get canTimedOn => !isBusy && !isSuspectedOffline && (!isOn || super.mode == LyfiMode.scheduled);

  IEditor? currentEditor;
  final ScheduleTable scheduledInstants = [];
  final ScheduleTable sunInstants = [];

  int? get currentTempRaw => super.lyfiDeviceStatus?.temperature;
  int? get currentTemp => super.lyfiDeviceStatus?.temperature == null
      ? null
      : localeService.convertTemperatureValue(super.lyfiDeviceStatus!.temperature!.toDouble()).toInt();

  String get temperatureUnitText => localeService.temperatureUnitText;

  // LyFi device status and info
  double? _fanPowerRatio = 0.0;
  double? get fanPowerRatio => _fanPowerRatio;

  double _overallBrightness = 0;
  double get overallBrightness => _overallBrightness;

  final List<ValueNotifier<int>> _channels = [];
  List<ValueNotifier<int>> get channels => _channels;

  Future<void> updateChannelValue(int index, int value) async {
    if (index >= 0 && index < _channels.length) {
      _channels[index].value = value;
    }
  }

  LyfiViewModel({
    required super.deviceID,
    required super.deviceManager,
    required super.globalEventBus,
    required super.notification,
    required this.localeService,
    required this.gt,
    super.logger,
  });

  Future<T> executeLyfiCommand<T>(
    Future<T> Function() action, {
    Duration? timeout,
    bool resetSuspectedOnSuccess = true,
  }) {
    return runDeviceCommand(
      action,
      timeout: timeout ?? _commandTimeout,
      resetSuspectedOnSuccess: resetSuspectedOnSuccess,
    );
  }

  @override
  void onDeviceSuspectedOffline() {
    super.onDeviceSuspectedOffline();
    if (_rapidProbeTask != null || boundDevice == null || isDisposed) {
      return;
    }
    _rapidProbeTask = _runRapidProbe().whenComplete(() {
      _rapidProbeTask = null;
    });
  }

  Future<void> _runRapidProbe() async {
    for (var attempt = 0; attempt < _rapidProbeAttempts; attempt++) {
      if (isDisposed || boundDevice == null || !super.isOnline) {
        return;
      }

      try {
        await _deviceApi.getLyfiStatus(boundDevice!.device).timeout(_rapidProbeTimeout);
        super.clearSuspectedOffline();
        await refreshStatus();
        return;
      } on TimeoutException {
        // continue to next attempt
      } on SocketException catch (e, stackTrace) {
        logger?.w('Lyfi rapid probe socket error: $e', error: e, stackTrace: stackTrace);
      } on IOException catch (e, stackTrace) {
        logger?.w('Lyfi rapid probe IO error: $e', error: e, stackTrace: stackTrace);
      } catch (e, stackTrace) {
        logger?.w('Lyfi rapid probe unexpected error: $e', error: e, stackTrace: stackTrace);
      }

      if (attempt < _rapidProbeAttempts - 1) {
        await Future.delayed(_rapidProbeInterval);
      }
    }
  }

  @override
  Future<void> onInitialize() async {
    await super.onInitialize();
    if (super.isOnline && !isSuspectedOffline && boundDevice != null) {
      _temporaryDuration = await executeLyfiCommand(() => _deviceApi.getTemporaryDuration(boundDevice!.device));
    }

    //_channels.length * lyfiBrightnessMax.toDouble();

    await refreshStatus();

    if (super.isOnline && !isSuspectedOffline && boundDevice != null) {
      switch (mode) {
        case LyfiMode.scheduled:
          scheduledInstants.addAll(await executeLyfiCommand(() => _deviceApi.getSchedule(boundDevice!.device)));
          break;

        case LyfiMode.sun:
          sunInstants.addAll(await executeLyfiCommand(() => _deviceApi.getSunSchedule(boundDevice!.device)));
          break;

        default:
          break;
      }
    }

    // Update schedule
    // final schedule = await _deviceApi.getSchedule(boundDevice.device);
    if (!super.isLocked) {
      await _toggleEditor(super.mode);
    }
  }

  @override
  void dispose() {
    //
    if (!_isDisposed) {
      for (final cvn in _channels) {
        cvn.dispose();
      }
      if (!super.isLocked && super.isOnline && !isSuspectedOffline) {
        try {
          Future.microtask(() async {
            if (super.state != LyfiState.normal) {
              await super.setState(LyfiState.normal);
            }
          });
        } catch (e, stackTrace) {
          logger?.e('Failed to setMode of the device(${super.deviceEntity})', error: e, stackTrace: stackTrace);
        }
      }
      /*
    for (final ch in _channels) {
      ch.dispose();
    }
    */
      super.dispose();
      _isDisposed = true;
    }
  }

  @override
  Future<void> onDeviceBound() async {
    super.onDeviceBound();

    if (boundDevice == null) {
      return;
    }

    _temporaryDuration = await executeLyfiCommand(() => _deviceApi.getTemporaryDuration(boundDevice!.device));

    await refreshStatus();

    switch (mode) {
      case LyfiMode.scheduled:
        if (scheduledInstants.isEmpty) {
          scheduledInstants.addAll(await executeLyfiCommand(() => _deviceApi.getSchedule(boundDevice!.device)));
        }
        break;

      case LyfiMode.sun:
        if (sunInstants.isEmpty) {
          sunInstants.addAll(await executeLyfiCommand(() => _deviceApi.getSunSchedule(boundDevice!.device)));
        }
        break;

      default:
        break;
    }

    // Update schedule
    if (!super.isLocked) {
      await _toggleEditor(super.mode);
    }
  }

  @override
  void onDeviceRemoved() {
    super.onDeviceRemoved();

    for (final cvn in _channels) {
      cvn.dispose();
    }
    _channels.clear();

    _overallBrightness = 0.0;
    _fanPowerRatio = 0.0;

    if (currentEditor != null) {
      currentEditor!.dispose();
      currentEditor = null;
    }
  }

  @override
  Future<void> refreshStatus({CancellationToken? cancelToken}) async {
    assert(!_isDisposed);
    if (!super.isOnline || isSuspectedOffline || boundDevice == null) {
      return;
    }
    await super.refreshStatus(cancelToken: cancelToken);

    if (super.isSuspectedOffline) {
      return;
    }

    _fanPowerRatio = super.lyfiDeviceStatus?.fanPower == null ? null : super.lyfiDeviceStatus!.fanPower!.toDouble();

    _temporaryRemaining.value = lyfiDeviceStatus?.temporaryRemaining ?? Duration.zero;

    bool emptyChannels = _channels.isEmpty;
    if (super.lyfiDeviceStatus != null) {
      double ob = 0;
      for (int i = 0; i < lyfiDeviceStatus!.currentColor.length; i++) {
        if (emptyChannels) {
          _channels.add(ValueNotifier<int>(super.lyfiDeviceStatus!.currentColor[i]));
        } else {
          _channels[i].value = super.lyfiDeviceStatus!.currentColor[i];
        }
        ob += lyfiDeviceInfo.channels[i].brightnessRatio * _channels[i].value / lyfiBrightnessMax;
      }
      _overallBrightness = ob;
    }

    if (super.mode == LyfiMode.sun) {
      final sunSchedule = await executeLyfiCommand(() => _deviceApi.getSunSchedule(boundDevice!.device));
      if (sunSchedule.length == sunInstants.length) {
        for (int i = 0; i < sunSchedule.length; i++) {
          sunInstants[i] = sunSchedule[i];
        }
      }
    }
  }

  void switchPowerOnOff(bool onOff) async {
    try {
      if (isSuspectedOffline) {
        notifyAppError(this.gt.translate('Device is offline. Please retry after reconnection.'), allowDuplicates: true);
        return;
      }
      await _switchPowerOnOff(onOff);
    } catch (e, stackTrace) {
      logger?.e('Error in switchPowerOnOff: $e', error: e, stackTrace: stackTrace);
      notifyAppError(this.gt.translate('Failed to switch power: {0}', pArgs: [e.toString()]), allowDuplicates: true);
    }
  }

  Future<void> _switchPowerOnOff(bool onOff) async {
    await executeLyfiCommand(() => _deviceApi.setOnOff(super.boundDevice!.device, onOff));
    await refreshStatus();
  }

  bool get canSwitchTemporaryState =>
      !isBusy &&
      !isSuspectedOffline &&
      super.isOn &&
      (super.mode == LyfiMode.scheduled || super.mode == LyfiMode.sun) &&
      (super.state == LyfiState.temporary || super.state == LyfiState.normal);

  void switchTemporaryState() async {
    try {
      assert(super.state == LyfiState.normal || super.state == LyfiState.temporary);
      await _switchTemporaryState();
    } catch (e, stackTrace) {
      logger?.e('Error in switchTemporaryState: $e', error: e, stackTrace: stackTrace);
      notifyAppError(
        this.gt.translate('Failed to switch temporary state: {0}', pArgs: [e.toString()]),
        allowDuplicates: true,
      );
    }
  }

  Future<void> _switchTemporaryState() async {
    // Turn the temp mode on
    if (super.state == LyfiState.normal) {
      await executeLyfiCommand(() => _deviceApi.switchState(super.boundDevice!.device, LyfiState.temporary));
    } else {
      // Restore running mode
      await executeLyfiCommand(() => _deviceApi.switchState(super.boundDevice!.device, LyfiState.normal));
    }
    await refreshStatus();
  }

  bool get canSwitchDiscoState =>
      !isBusy &&
      !isSuspectedOffline &&
      super.isOn &&
      (super.state == LyfiState.temporary || super.state == LyfiState.normal);

  void switchDiscoState() async {
    try {
      await _switchDiscoState();
    } catch (e, stackTrace) {
      logger?.e('Error in switchDiscoState: $e', error: e, stackTrace: stackTrace);
      notifyAppError(
        this.gt.translate('Failed to switch disco state: {0}', pArgs: [e.toString()]),
        allowDuplicates: true,
      );
    }
  }

  Future<void> _switchDiscoState() async {
    // Turn the disco mode on
    if (super.state == LyfiState.normal || super.state == LyfiState.temporary) {
      await executeLyfiCommand(() => _deviceApi.switchState(super.boundDevice!.device, LyfiState.disco));
    } else {
      // Restore running mode
      await executeLyfiCommand(() => _deviceApi.switchState(super.boundDevice!.device, LyfiState.normal));
    }
    await refreshStatus();
  }

  void toggleLock(bool isLocked) async {
    try {
      await _toggleLock(isLocked);
    } catch (e, stackTrace) {
      logger?.e('Error in toggleLock: $e', error: e, stackTrace: stackTrace);
      notifyAppError(this.gt.translate('Failed to toggle lock: {0}', pArgs: [e.toString()]), allowDuplicates: true);
    }
  }

  Future<void> _toggleLock(bool newIsLocked) async {
    if (isSuspectedOffline) {
      return;
    }
    if (!super.isLocked) {
      assert(currentEditor != null);
      // Exiting the edit mode
      if (currentEditor!.isChanged) {
        await currentEditor!.save();
        if (currentEditor is ScheduleEditorViewModel) {
          scheduledInstants.clear();
          scheduledInstants.addAll(await executeLyfiCommand(() => _deviceApi.getSchedule(boundDevice!.device)));
        } else if (currentEditor is SunEditorViewModel) {
          sunInstants.clear();
          sunInstants.addAll(await executeLyfiCommand(() => _deviceApi.getSunSchedule(boundDevice!.device)));
        }
      }
    }

    if (newIsLocked) {
      // Exiting edit mode - switch to normal state
      await super.setState(LyfiState.normal);
      await refreshStatus();
      notifyListeners();
    } else {
      // Entering edit mode - wait for state to change to dimming before creating editor
      await super.setState(LyfiState.dimming);
      await refreshStatus();

      await _toggleEditor(super.mode);
      // Notify listeners so UI awaiting readiness can proceed
      notifyListeners();
    }
  }

  void switchMode(LyfiMode mode) async {
    try {
      await _switchMode(mode);
    } catch (e, stackTrace) {
      logger?.e('Error in switchMode: $e', error: e, stackTrace: stackTrace);
      notifyAppError(this.gt.translate('Failed to switch mode: %s', pArgs: [e.toString()]), allowDuplicates: true);
    }
  }

  Future<void> _switchMode(LyfiMode newMode) async {
    if (isLocked) {
      return;
    }

    if (isSuspectedOffline) {
      notifyAppError(this.gt.translate('Device is offline. Please retry after reconnection.'), allowDuplicates: true);
      return;
    }

    if (newMode == LyfiMode.sun) {
      if (borneoDeviceStatus?.timezone.isEmpty ?? true) {
        notifyAppError(
          this.gt.translate("Unable to switch to Sun Simulation mode, the device's timezone is not set."),
          allowDuplicates: true,
        );
        return;
      }
      final location = await executeLyfiCommand(() => _deviceApi.getLocation(super.boundDevice!.device));
      if (location == null) {
        notifyAppError(
          this.gt.translate("Unable to switch to Sun Simulation mode, the device's geographic location is not set."),
          allowDuplicates: true,
        );
        return;
      }
    }

    await super.setMode(newMode);
    await refreshStatus();
    await _toggleEditor(super.mode);
    notifyListeners();
  }

  Future<void> _toggleEditor(LyfiMode newMode) async {
    switch (newMode) {
      case LyfiMode.manual:
        currentEditor = ManualEditorViewModel(this);
        break;

      case LyfiMode.scheduled:
        currentEditor = ScheduleEditorViewModel(this);
        break;

      case LyfiMode.sun:
        currentEditor = SunEditorViewModel(this);
        break;
    }
    await currentEditor!.initialize();
    // Do not notify here; callers decide after refresh/creation to notify.
  }

  bool get isDimmingReady => !isLocked && super.state == LyfiState.dimming && currentEditor != null;

  /// Returns a Future that completes when the view model is ready for Dimming editing
  /// (unlocked, state==dimming, editor initialized). No timers/polling are used; it resolves
  /// on the next notifyListeners that satisfies the predicate.
  Future<void> onDimmingReady() async {
    if (isDimmingReady) return;
    final completer = Completer<void>();
    late VoidCallback listener;
    listener = () {
      if (isDimmingReady && !completer.isCompleted) {
        removeListener(listener);
        completer.complete();
      }
    };
    addListener(listener);
    return completer.future;
  }

  Future<SettingsViewModel> loadSettings(final GettextLocalizations gt) async {
    if (!super.isOnline || isSuspectedOffline || boundDevice == null) {
      throw StateError('Device is not reachable at the moment.');
    }
    final vm = SettingsViewModel(
      gt,
      deviceID: deviceID,
      deviceManager: deviceManager,
      globalEventBus: globalEventBus,
      notification: notification,
      address: deviceEntity.address,
      borneoStatus: borneoDeviceStatus!,
      borneoInfo: super.borneoDeviceInfo!,
      ledInfo: lyfiDeviceInfo,
      ledStatus: lyfiDeviceStatus!,
      powerBehavior: await executeLyfiCommand(() => _deviceApi.getPowerBehavior(boundDevice!.device)),
      location: await executeLyfiCommand(() => _deviceApi.getLocation(boundDevice!.device)),
    );
    await vm.initialize();
    return vm;
  }
}
