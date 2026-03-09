import 'dart:async';

import 'package:logger/logger.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:queue/queue.dart';

import 'package:borneo_kernel_abstractions/kernel.dart';

/// Default implementation of [BindingEngine].  This class owns all driver
/// activation/purge logic and maintains the maps of bound devices used by the
/// kernel in the original monolithic implementation.  It fires the same
/// events the kernel previously fired so that callers (for example the
/// heartbeat subsystem) continue to work unchanged.
class DefaultBindingEngine implements BindingEngine {
  final Logger _logger;
  final IDriverRegistry _driverRegistry;
  final EventDispatcher _events;

  // Configurable timeouts carried over from the kernel constructor.
  final Duration localBindTimeout;

  DefaultBindingEngine(this._logger, this._driverRegistry, this._events, {Duration? localBindTimeout})
    : localBindTimeout = localBindTimeout ?? const Duration(seconds: 5);

  final Map<String, BoundDevice> _boundDevices = {};
  final Map<String, Driver> _activatedDrivers = {};
  final Map<String, StreamSubscription> _deviceEventRouters = {};

  // serializes all bind/unbind work so we don’t need manual locks per device
  final Queue _queue = Queue();

  @override
  bool get isBusy => _queue.remainingItemCount > 0;

  @override
  Iterable<BoundDevice> get boundDevices => List.unmodifiable(_boundDevices.values);

  @override
  BoundDevice? getBoundDevice(String deviceID) => _boundDevices[deviceID];

  Driver _ensureDriverActivated(String driverID) {
    return _activatedDrivers.putIfAbsent(driverID, () {
      final desc = _driverRegistry.metaDrivers[driverID];
      if (desc == null) {
        throw ArgumentError('Unknown driverID $driverID');
      }
      final drv = desc.factory(logger: _logger);
      return drv;
    });
  }

  void _purgeUnusedDriver() {
    final toRemove = <String>[];
    for (final entry in _activatedDrivers.entries) {
      final inUse = _boundDevices.values.any((b) => b.driverID == entry.key);
      if (!inUse) {
        toRemove.add(entry.key);
      }
    }
    for (final id in toRemove) {
      final drv = _activatedDrivers.remove(id)!;
      drv.dispose();
    }
  }

  @override
  Future<bool> tryBind(Device device, String driverID, {CancellationToken? cancelToken}) {
    if (getBoundDevice(device.id) != null) {
      return Future.value(true);
    }
    return _queue.add<bool>(() async {
      try {
        await _bindUnlocked(device, driverID, cancelToken: cancelToken);
        return true;
      } on CancelledException catch (_) {
        _logger.w('Device($device) binding cancelled');
        return false;
      } on TimeoutException catch (error, stackTrace) {
        _logger.w('Probing device($device) timed out:', error: error, stackTrace: stackTrace);
        _events.fire(LoadingDriverFailedEvent(device, error: error, message: 'Device probe timed out'));
        return false;
      } on DeviceProbeError catch (error, stackTrace) {
        _logger.w('Probing device($device) failed:', error: error, stackTrace: stackTrace);
        _events.fire(LoadingDriverFailedEvent(device, error: error, message: error.toString()));
        return false;
      } catch (e, stackTrace) {
        _logger.e('Engine error: $e', error: e, stackTrace: stackTrace);
        _events.fire(LoadingDriverFailedEvent(device, error: e, message: e.toString()));
        return false;
      }
    });
  }

  @override
  Future<void> bind(Device device, String driverID, {CancellationToken? cancelToken}) {
    return _queue.add(() => _bindUnlocked(device, driverID, cancelToken: cancelToken));
  }

  @override
  Future<void> unbind(String deviceID, {CancellationToken? cancelToken}) {
    return _queue.add(() async {
      final boundDevice = _boundDevices[deviceID];
      if (boundDevice != null) {
        await boundDevice.driver.remove(boundDevice.device, cancelToken: cancelToken);
        boundDevice.dispose();

        _boundDevices.remove(deviceID);
        _deviceEventRouters[deviceID]?.cancel();
        _deviceEventRouters.remove(deviceID);

        _purgeUnusedDriver();

        _events.fire(DeviceRemovedEvent(boundDevice.device));
      }
    });
  }

  @override
  Future<void> unbindAll({CancellationToken? cancelToken}) {
    // perform all unbinds within the same queue task to avoid deadlock
    return _queue.add(() async {
      final ids = List<String>.from(_boundDevices.keys);
      for (final id in ids) {
        final boundDevice = _boundDevices[id];
        if (boundDevice != null) {
          await boundDevice.driver.remove(boundDevice.device, cancelToken: cancelToken);
          boundDevice.dispose();

          _boundDevices.remove(id);
          _deviceEventRouters[id]?.cancel();
          _deviceEventRouters.remove(id);

          _purgeUnusedDriver();

          _events.fire(DeviceRemovedEvent(boundDevice.device));
        }
      }
    });
  }

  @override
  void dispose() {
    for (final sub in _deviceEventRouters.values) {
      sub.cancel();
    }
    _deviceEventRouters.clear();

    for (final drv in _activatedDrivers.values) {
      drv.dispose();
    }
    _activatedDrivers.clear();
    _boundDevices.clear();
    _queue.dispose();
  }

  /// Internal helper that performs the binding logic without enqueuing.
  Future<void> _bindUnlocked(Device device, String driverID, {CancellationToken? cancelToken}) async {
    cancelToken?.throwIfCancelled();

    _logger.i('Binding device: `$device` to driver `$driverID`');

    var driverDesc = _driverRegistry.metaDrivers[driverID];
    if (driverDesc == null) {
      final msg = 'Failed to find the driver key `$driverID` for device(`${device.address}`)';
      _logger.e(msg);
      throw ArgumentError(msg, 'device');
    }
    final driver = _ensureDriverActivated(driverID);

    final driverInitialized = await driver.probe(device, cancelToken: cancelToken);

    if (driverInitialized) {
      final bound = BoundDevice(driverID, device, driver);

      // since we're running in the queue, no additional lock is needed
      _deviceEventRouters[device.id] = bound.device.driverData.deviceEvents.on().listen((event) {
        _events.fire(event);
      });

      _boundDevices[device.id] = bound;
      _events.fire(DeviceBoundEvent(device));
    } else {
      throw DeviceProbeError("Failed to probe $device", device);
    }
  }
}
