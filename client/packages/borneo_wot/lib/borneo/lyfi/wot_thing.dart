// dart format width=120

import 'dart:async';
import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel/drivers/borneo/events.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/events.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:borneo_kernel_abstractions/kernel.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:logger/logger.dart';
import 'package:lw_wot/wot.dart';
import '../../wot.dart';
import './wot_actions.dart';
import './wot_props.dart';

part 'wot_thing.props.dart';
part 'wot_thing.actions.dart';

/// LyfiThing extends WotThing following Mozilla WebThing initialization pattern
/// This class uses default values during construction and binds to actual hardware asynchronously
class LyfiThing extends BorneoThing implements WotWriteGuard, WotActionGuard {
  static const Duration kLightweightInterval = Duration(seconds: 1);
  static const Duration kLowFrequencyInterval = Duration(seconds: 30);

  final IKernel kernel;
  final Logger? logger;
  final String deviceId;
  final DeviceEventBus deviceEvents;
  IBorneoDeviceApi? _borneoApi;
  ILyfiDeviceApi? _lyfiApi;
  Device? _device;
  bool canWrite() => isActive && !super.isOffline && kernel.isBound(deviceId);

  StreamSubscription<DeviceBoundEvent>? _deviceBoundSub;
  StreamSubscription<DeviceOfflineEvent>? _deviceOfflineSub;
  StreamSubscription<DeviceRemovedEvent>? _deviceRemovedSub;
  StreamSubscription<DeviceCommunicationEvent>? _deviceCommunicationSub;
  final List<StreamSubscription> _deviceEventForwarders = [];
  final List<StreamSubscription> _driverDataEventForwarders = [];

  LyfiThing({required this.kernel, required this.deviceId, required super.title, this.logger})
    : deviceEvents = DeviceEventBus(),
      super(id: deviceId, type: ["OnOffSwitch", "LyfiThing", "Light"], description: "Lyfi LED lighting device") {
    _createPropertiesWithDefaults();
    _createActions();
    _setupKernelEventSubscriptions();
    _syncFromKernel();
  }

  @override
  bool canWriteProperty(String propertyName) => canWrite.call();

  @override
  String? getWriteGuardError(String propertyName) => 'Device is offline or unbound.';

  @override
  bool canPerformAction(String actionName) => canWrite.call();

  @override
  String? getActionGuardError(String actionName) => 'Device is offline or unbound.';

  // ---------------------------------------------------------------------------
  // Activate / Deactivate hooks (called by DeviceManagerImpl on scene switch)
  // ---------------------------------------------------------------------------

  @override
  void onActivated() {
    // Immediately kick off a full sync and restart periodic polling.
    unawaited(sync());
  }

  @override
  void onDeactivated() {
    // Stop all periodic polling; keep last-known property values intact.
    _stopPeriodicSync();
  }

  void _stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _lowFrequencySyncTimer?.cancel();
    _lowFrequencySyncTimer = null;
  }

  /// Mozilla WebThing style initialization - sync constructor with async hardware binding
  @override
  Future<void> sync({CancellationToken? cancelToken}) async {
    _syncFromKernel();
    if (isActive && !isOffline) {
      await _bindToHardware(cancelToken: cancelToken);
      await _lightweightSync();
    }

    if (isActive) {
      _startPeriodicSyncIfNeeded();
    }
  }

  /// Bind properties to actual hardware state (like Mozilla WebThing ready callback)
  Future<void> _bindToHardware({CancellationToken? cancelToken}) async {
    final borneoApi = _getBorneoApiOrNull();
    final lyfiApi = _getLyfiApiOrNull();
    final device = _getDeviceOrNull();
    if (isOffline || borneoApi == null || lyfiApi == null || device == null) return;
    // Get actual device state and update property values
    final generalStatus = await borneoApi.getGeneralDeviceStatus(device, cancelToken: cancelToken);
    final generalDeviceInfo = await borneoApi.getGeneralDeviceInfo(device, cancelToken: cancelToken);
    final lyfiStatus = await lyfiApi.getLyfiStatus(device, cancelToken: cancelToken);
    final schedule = await lyfiApi.getSchedule(device, cancelToken: cancelToken);
    final acclimation = await lyfiApi.getAcclimation(device, cancelToken: cancelToken);
    final location = await lyfiApi.getLocation(device, cancelToken: cancelToken);
    final correctionMethod = await lyfiApi.getCorrectionMethod(device, cancelToken: cancelToken);
    final timeZoneEnabled = await lyfiApi.getTimeZoneEnabled(device, cancelToken: cancelToken);
    final timeZoneOffset = await lyfiApi.getTimeZoneOffset(device, cancelToken: cancelToken);
    final keepTemp = await lyfiApi.getKeepTemp(device, cancelToken: cancelToken);
    final fanMode = await lyfiApi.getFanMode(device, cancelToken: cancelToken);
    final fanPower = await lyfiApi.getFanManualPower(device, cancelToken: cancelToken);

    // Additional API calls for new properties
    final cloudEnabled = await lyfiApi.getCloudEnabled(device, cancelToken: cancelToken);
    final temporaryDuration = await lyfiApi.getTemporaryDuration(device, cancelToken: cancelToken);
    final sunSchedule = await lyfiApi.getSunSchedule(device, cancelToken: cancelToken);

    final powerBehavior = await borneoApi.getPowerBehavior(device, cancelToken: cancelToken);
    final deviceInfo = await lyfiApi.getLyfiInfo(device, cancelToken: cancelToken);
    // final currentTemp = await lyfiApi.getCurrentTemp(device); // Use lyfiStatus.temperature
    // final deviceInfo = await lyfiApi.getDeviceInfo(device); // Skip for now

    if (lyfiStatus.mode == LyfiMode.sun) {
      try {
        final sunCurve = await lyfiApi.getSunCurve(device, cancelToken: cancelToken);
        findProperty('sunCurve')?.value.notifyOfExternalUpdate(sunCurve);
      } catch (e) {
        logger?.w("Failed to get Sun curve: $e");
      }
    }

    // Update properties with actual values (like notifyOfExternalUpdate in Mozilla WebThing)
    findProperty('on')?.value.notifyOfExternalUpdate(generalStatus.power);
    findProperty('state')?.value.notifyOfExternalUpdate(lyfiStatus.state.name);
    findProperty('mode')?.value.notifyOfExternalUpdate(lyfiStatus.mode.name);
    findProperty('color')?.value.notifyOfExternalUpdate(lyfiStatus.currentColor);
    findProperty('schedule')?.value.notifyOfExternalUpdate(schedule);
    findProperty('acclimation')?.value.notifyOfExternalUpdate(acclimation);
    findProperty('location')?.value.notifyOfExternalUpdate(location);
    findProperty('correctionMethod')?.value.notifyOfExternalUpdate(correctionMethod.name);
    findProperty('timezone')?.value.notifyOfExternalUpdate(generalStatus.timezone);
    findProperty('timezoneEnabled')?.value.notifyOfExternalUpdate(timeZoneEnabled);
    findProperty('timezoneOffset')?.value.notifyOfExternalUpdate(timeZoneOffset);
    findProperty('keepTemp')?.value.notifyOfExternalUpdate(keepTemp);
    findProperty('temperature')?.value.notifyOfExternalUpdate(lyfiStatus.temperature);
    findProperty('fanMode')?.value.notifyOfExternalUpdate(fanMode.name);
    findProperty('fanManualPower')?.value.notifyOfExternalUpdate(fanPower);

    findProperty('cloudEnabled')?.value.notifyOfExternalUpdate(cloudEnabled);
    findProperty('temporaryDuration')?.value.notifyOfExternalUpdate(temporaryDuration);
    findProperty('sunSchedule')?.value.notifyOfExternalUpdate(sunSchedule);

    // Additional moon API calls
    final moonConfig = await lyfiApi.getMoonConfig(device, cancelToken: cancelToken);
    findProperty('moonConfig')?.value.notifyOfExternalUpdate(moonConfig);

    if (moonConfig.enabled) {
      try {
        final moonSchedule = await lyfiApi.getMoonSchedule(device, cancelToken: cancelToken);
        final moonStatus = await lyfiApi.getMoonStatus(device, cancelToken: cancelToken);
        final moonCurve = await lyfiApi.getMoonCurve(device, cancelToken: cancelToken);
        findProperty('moonCurve')?.value.notifyOfExternalUpdate(moonCurve);
        findProperty('moonSchedule')?.value.notifyOfExternalUpdate(moonSchedule);
        findProperty('moonStatus')?.value.notifyOfExternalUpdate(moonStatus);
      } catch (e) {
        logger?.w("Failed to get Moon curve: $e");
      }
    }

    findProperty('currentTemp')?.value.notifyOfExternalUpdate(lyfiStatus.temperature ?? 25);
    findProperty('lyfiDeviceInfo')?.value.notifyOfExternalUpdate(deviceInfo);
    findProperty('unscheduled')?.value.notifyOfExternalUpdate(lyfiStatus.unscheduled);
    findProperty('temporaryRemaining')?.value.notifyOfExternalUpdate(lyfiStatus.temporaryRemaining);
    findProperty('fanPower')?.value.notifyOfExternalUpdate(lyfiStatus.fanPower ?? 0);
    findProperty('manualColor')?.value.notifyOfExternalUpdate(lyfiStatus.manualColor);
    findProperty('sunColor')?.value.notifyOfExternalUpdate(lyfiStatus.sunColor);
    findProperty('acclimationEnabled')?.value.notifyOfExternalUpdate(lyfiStatus.acclimationEnabled);
    findProperty('acclimationActivated')?.value.notifyOfExternalUpdate(lyfiStatus.acclimationActivated);
    findProperty('cloudActivated')?.value.notifyOfExternalUpdate(lyfiStatus.cloudActivated);

    // Update power measurement properties
    findProperty('voltage')?.value.notifyOfExternalUpdate(generalStatus.powerVoltage);
    findProperty('current')?.value.notifyOfExternalUpdate(lyfiStatus.powerCurrent);
    findProperty('power')?.value.notifyOfExternalUpdate(
      generalStatus.powerVoltage != null && lyfiStatus.powerCurrent != null
          ? generalStatus.powerVoltage! * lyfiStatus.powerCurrent!
          : null,
    );

    // Update power behavior property
    findProperty('powerBehavior')?.value.notifyOfExternalUpdate(powerBehavior);

    // Update timestamp property
    findProperty('timestamp')?.value.notifyOfExternalUpdate(generalStatus.timestamp);

    // Update status properties
    findProperty('lyfiStatus')?.value.notifyOfExternalUpdate(lyfiStatus);
    findProperty('generalDeviceInfo')?.value.notifyOfExternalUpdate(generalDeviceInfo);
    findProperty('generalStatus')?.value.notifyOfExternalUpdate(generalStatus);
  }

  /// Lightweight periodic sync - only check critical properties
  void _startPeriodicSyncIfNeeded() {
    // Only start timers when the Thing is active.
    if (!isActive) return;

    if (!(_syncTimer?.isActive ?? false)) {
      _syncTimer = Timer.periodic(kLightweightInterval, (timer) async {
        if (!isDisposed && isActive && !isOffline) {
          await _lightweightSync();
        } else {
          timer.cancel();
          if (timer == _syncTimer) {
            _syncTimer = null;
          }
        }
      });
    }

    if (!(_lowFrequencySyncTimer?.isActive ?? false)) {
      _lowFrequencySyncTimer = Timer.periodic(kLowFrequencyInterval, (timer) async {
        if (!isDisposed && isActive && !isOffline) {
          await _lowFrequencySync();
        } else {
          timer.cancel();
          if (timer == _lowFrequencySyncTimer) {
            _lowFrequencySyncTimer = null;
          }
        }
      });
    }
  }

  /// Lightweight sync - only check essential properties to minimize API calls
  Future<void> _lightweightSync() async {
    if (_isSyncing) {
      return;
    }
    _isSyncing = true;
    try {
      final borneoApi = _getBorneoApiOrNull();
      final lyfiApi = _getLyfiApiOrNull();
      final device = _getDeviceOrNull();
      if (borneoApi == null || lyfiApi == null || device == null) return;

      final generalStatus = await borneoApi.getGeneralDeviceStatus(device);

      findProperty('on')?.value.notifyOfExternalUpdate(generalStatus.power);

      // Sync mode and state
      final lyfiStatus = await lyfiApi.getLyfiStatus(device);
      findProperty('mode')?.value.notifyOfExternalUpdate(lyfiStatus.mode.name);
      findProperty('state')?.value.notifyOfExternalUpdate(lyfiStatus.state.name);
      findProperty('temperature')?.value.notifyOfExternalUpdate(lyfiStatus.temperature);
      findProperty('color')?.value.notifyOfExternalUpdate(lyfiStatus.currentColor);
      findProperty('output')?.value.notifyOfExternalUpdate(lyfiStatus.output);

      // Sync additional critical properties
      findProperty('currentTemp')?.value.notifyOfExternalUpdate(lyfiStatus.temperature ?? 0);
      findProperty('fanPower')?.value.notifyOfExternalUpdate(lyfiStatus.fanPower ?? 0);
      findProperty('unscheduled')?.value.notifyOfExternalUpdate(lyfiStatus.unscheduled);
      findProperty('temporaryRemaining')?.value.notifyOfExternalUpdate(lyfiStatus.temporaryRemaining);
      findProperty('cloudActivated')?.value.notifyOfExternalUpdate(lyfiStatus.cloudActivated);
      findProperty('sunColor')?.value.notifyOfExternalUpdate(lyfiStatus.sunColor);
      findProperty('acclimationEnabled')?.value.notifyOfExternalUpdate(lyfiStatus.acclimationEnabled);

      // Update power measurement properties
      findProperty('voltage')?.value.notifyOfExternalUpdate(generalStatus.powerVoltage);
      findProperty('current')?.value.notifyOfExternalUpdate(
        generalStatus.powerVoltage != null && lyfiStatus.powerCurrent != null ? lyfiStatus.powerCurrent! : null,
      );
      findProperty('power')?.value.notifyOfExternalUpdate(
        generalStatus.powerVoltage != null && lyfiStatus.powerCurrent != null
            ? generalStatus.powerVoltage! * lyfiStatus.powerCurrent!
            : null,
      );

      // Update status properties
      findProperty('lyfiStatus')?.value.notifyOfExternalUpdate(lyfiStatus);
      findProperty('generalStatus')?.value.notifyOfExternalUpdate(generalStatus);
      findProperty('timestamp')?.value.notifyOfExternalUpdate(generalStatus.timestamp);
      findProperty('timezone')?.value.notifyOfExternalUpdate(generalStatus.timezone);
    } catch (e, stackTrace) {
      logger?.w('Lightweight sync failed: $e', error: e, stackTrace: stackTrace);
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _lowFrequencySync() async {
    if (_isLowFreqSyncing) return;
    _isLowFreqSyncing = true;
    try {
      final lyfiApi = _getLyfiApiOrNull();
      final borneoApi = _getBorneoApiOrNull();
      final device = _getDeviceOrNull();
      if (lyfiApi == null || device == null) return;

      final lyfiStatus = await lyfiApi.getLyfiStatus(device);
      final deviceInfo = await lyfiApi.getLyfiInfo(device);
      findProperty('acclimationEnabled')?.value.notifyOfExternalUpdate(lyfiStatus.acclimationEnabled);
      findProperty('acclimationActivated')?.value.notifyOfExternalUpdate(lyfiStatus.acclimationActivated);
      findProperty('lyfiDeviceInfo')?.value.notifyOfExternalUpdate(deviceInfo);

      if (borneoApi != null) {
        final generalDeviceInfo = await borneoApi.getGeneralDeviceInfo(device);
        findProperty('generalDeviceInfo')?.value.notifyOfExternalUpdate(generalDeviceInfo);
      }

      switch (lyfiStatus.mode) {
        case LyfiMode.manual:
          {
            final manualColor = lyfiStatus.manualColor;
            findProperty('manualColor')?.value.notifyOfExternalUpdate(manualColor);
          }
          break;

        case LyfiMode.scheduled:
          {
            final schedule = await lyfiApi.getSchedule(device);
            findProperty('schedule')?.value.notifyOfExternalUpdate(schedule);
          }
          break;

        case LyfiMode.sun:
          {
            final sunSchedule = await lyfiApi.getSunSchedule(device);
            findProperty('sunSchedule')?.value.notifyOfExternalUpdate(sunSchedule);
            final sunCurve = await lyfiApi.getSunCurve(device);
            findProperty('sunCurve')?.value.notifyOfExternalUpdate(sunCurve);
            findProperty('sunColor')?.value.notifyOfExternalUpdate(lyfiStatus.sunColor);
          }
          break;
      }

      // Moon properties sync
      final moonConfig = await lyfiApi.getMoonConfig(device);
      if (moonConfig.enabled) {
        final moonSchedule = await lyfiApi.getMoonSchedule(device);
        final moonCurve = await lyfiApi.getMoonCurve(device);
        findProperty('moonSchedule')?.value.notifyOfExternalUpdate(moonSchedule);
        findProperty('moonCurve')?.value.notifyOfExternalUpdate(moonCurve);
      }
      final moonStatus = await lyfiApi.getMoonStatus(device);

      findProperty('moonConfig')?.value.notifyOfExternalUpdate(moonConfig);
      findProperty('moonStatus')?.value.notifyOfExternalUpdate(moonStatus);
    } catch (e, stackTrace) {
      logger?.w('Low-frequency sync failed: $e', error: e, stackTrace: stackTrace);
    } finally {
      _isLowFreqSyncing = false;
    }
  }

  // Track disposal and timer
  bool _disposed = false;
  bool get isDisposed => _disposed;
  Timer? _syncTimer;
  Timer? _lowFrequencySyncTimer;
  // Re-entrancy guards: prevent a new timer-triggered sync from starting
  // while the previous one is still awaiting network responses.  Overlapping
  // calls on the same device would race to write stale values back into the
  // WotThing properties, causing incorrect UI data.
  bool _isSyncing = false;
  bool _isLowFreqSyncing = false;

  BoundDevice? _tryGetBoundDevice() {
    if (!kernel.isBound(deviceId)) return null;
    try {
      return kernel.getBoundDevice(deviceId);
    } catch (_) {
      return null;
    }
  }

  void _cacheFromBound(BoundDevice bound) {
    _device = bound.device;
    _borneoApi ??= bound.api<IBorneoDeviceApi>();
    _lyfiApi ??= bound.api<ILyfiDeviceApi>();
  }

  Device? _getDeviceOrNull() {
    if (_device != null) return _device;
    final bound = _tryGetBoundDevice();
    if (bound == null) return null;
    _cacheFromBound(bound);
    return _device;
  }

  IBorneoDeviceApi? _getBorneoApiOrNull() {
    if (_borneoApi != null) return _borneoApi;
    final bound = _tryGetBoundDevice();
    if (bound == null) return null;
    _cacheFromBound(bound);
    return _borneoApi;
  }

  ILyfiDeviceApi? _getLyfiApiOrNull() {
    if (_lyfiApi != null) return _lyfiApi;
    final bound = _tryGetBoundDevice();
    if (bound == null) return null;
    _cacheFromBound(bound);
    return _lyfiApi;
  }

  Device _requireDevice() {
    final device = _getDeviceOrNull();
    if (device == null) {
      throw StateError('Device is offline or unbound.');
    }
    return device;
  }

  IBorneoDeviceApi _requireBorneoApi() {
    final api = _getBorneoApiOrNull();
    if (api == null) {
      throw StateError('Device is offline or unbound.');
    }
    return api;
  }

  ILyfiDeviceApi _requireLyfiApi() {
    final api = _getLyfiApiOrNull();
    if (api == null) {
      throw StateError('Device is offline or unbound.');
    }
    return api;
  }

  Future<void> _withBorneoApi(Future<void> Function(IBorneoDeviceApi api, Device device) action) async {
    if (isOffline) return;
    final api = _getBorneoApiOrNull();
    final device = _getDeviceOrNull();
    if (api == null || device == null) return;
    await action(api, device);
  }

  Future<void> _withLyfiApi(Future<void> Function(ILyfiDeviceApi api, Device device) action) async {
    if (isOffline) return;
    final api = _getLyfiApiOrNull();
    final device = _getDeviceOrNull();
    if (api == null || device == null) return;
    await action(api, device);
  }

  void _markOnline() {
    if (!super.isOffline) {
      return;
    }
    findProperty('online')?.value.notifyOfExternalUpdate(true);
    _setupDriverDataEventSubscriptions();
  }

  void _markOffline() {
    if (super.isOffline) {
      return;
    }
    _borneoApi = null;
    _lyfiApi = null;
    // Clear the cached device reference so that any in-flight sync that resumes
    // after this point must re-validate the binding via _tryGetBoundDevice(),
    // preventing it from using a stale/disposed CoAP connection.
    _device = null;
    findProperty('online')?.value.notifyOfExternalUpdate(false);
    _syncTimer?.cancel();
    _lowFrequencySyncTimer?.cancel();
    _syncTimer = null;
    _lowFrequencySyncTimer = null;
    // Reset re-entrancy guards so a fresh sync can start after rebind.
    _isSyncing = false;
    _isLowFreqSyncing = false;
    _clearDriverDataEventSubscriptions();
  }

  void _syncFromKernel() {
    final bound = _tryGetBoundDevice();
    if (bound == null) {
      _markOffline();
      return;
    }
    _cacheFromBound(bound);
    _markOnline();
  }

  void _forwardDeviceEvent(DeviceStateChangedEvent event) {
    if (event.device.id != deviceId) return;
    deviceEvents.fire(event);
  }

  void _setupKernelEventSubscriptions() {
    _deviceBoundSub = kernel.events.on<DeviceBoundEvent>().listen((event) {
      if (event.device.id != deviceId) return;
      final bound = _tryGetBoundDevice();
      if (bound != null) {
        _cacheFromBound(bound);
      }
      _markOnline();
      _startPeriodicSyncIfNeeded();
      unawaited(_bindToHardware());
    });

    _deviceOfflineSub = kernel.events.on<DeviceOfflineEvent>().listen((event) {
      if (event.device.id != deviceId) return;
      _markOffline();
    });

    _deviceRemovedSub = kernel.events.on<DeviceRemovedEvent>().listen((event) {
      if (event.device.id != deviceId) return;
      _markOffline();
    });

    _deviceCommunicationSub = kernel.events.on<DeviceCommunicationEvent>().listen((event) {
      if (event.device.id != deviceId) return;
      if (isOffline) {
        _syncFromKernel();
        _startPeriodicSyncIfNeeded();
        unawaited(_bindToHardware());
      }
    });
  }

  void _setupDriverDataEventSubscriptions() {
    if (_device == null) return;
    _driverDataEventForwarders.addAll([
      _device!.driverData.deviceEvents.on<DevicePowerOnOffChangedEvent>().listen(_forwardDeviceEvent),
      _device!.driverData.deviceEvents.on<LyfiStateChangedEvent>().listen(_forwardDeviceEvent),
      _device!.driverData.deviceEvents.on<LyfiModeChangedEvent>().listen(_forwardDeviceEvent),
      _device!.driverData.deviceEvents.on<LyfiAcclimationChangedEvent>().listen(_forwardDeviceEvent),
      _device!.driverData.deviceEvents.on<LyfiLocationChangedEvent>().listen(_forwardDeviceEvent),
      _device!.driverData.deviceEvents.on<LyfiCorrectionMethodChangedEvent>().listen(_forwardDeviceEvent),
      _device!.driverData.deviceEvents.on<LyfiMoonConfigChangedEvent>().listen(_forwardDeviceEvent),
      _device!.driverData.deviceEvents.on<LyfiMoonScheduleChangedEvent>().listen(_forwardDeviceEvent),
      _device!.driverData.deviceEvents.on<LyfiMoonCurveChangedEvent>().listen(_forwardDeviceEvent),
    ]);
  }

  void _clearDriverDataEventSubscriptions() {
    for (final sub in _driverDataEventForwarders) {
      sub.cancel();
    }
    _driverDataEventForwarders.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();
    _lowFrequencySyncTimer?.cancel();
    _syncTimer = null;
    _lowFrequencySyncTimer = null;

    _deviceBoundSub?.cancel();
    _deviceOfflineSub?.cancel();
    _deviceRemovedSub?.cancel();
    _deviceCommunicationSub?.cancel();
    for (final sub in _deviceEventForwarders) {
      sub.cancel();
    }
    _deviceEventForwarders.clear();
    for (final sub in _driverDataEventForwarders) {
      sub.cancel();
    }
    _driverDataEventForwarders.clear();
    deviceEvents.destroy();

    super.dispose();
  }
}
