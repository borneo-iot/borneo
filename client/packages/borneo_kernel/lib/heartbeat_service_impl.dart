import 'dart:async';

import 'package:logger/logger.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:synchronized/synchronized.dart';
import 'package:retry/retry.dart';

import 'package:borneo_kernel_abstractions/heartbeat_service.dart';
import 'package:borneo_kernel_abstractions/models/heartbeat_method.dart';
import 'package:borneo_kernel_abstractions/models/heartbeat_state.dart';
import 'package:borneo_kernel_abstractions/models/bound_device.dart';
import 'package:borneo_kernel_abstractions/device.dart';
import 'package:borneo_kernel_abstractions/driver.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/coap_driver.dart';

/// Default implementation of [HeartbeatService].  All of the logic that used
/// to live inside `DefaultKernel` has been moved here; the kernel simply
/// forwards bind/unbind notifications and listens for failure events.
class DefaultHeartbeatService implements HeartbeatService {
  final Logger _logger;

  /// timeout used when polling a device heartbeat; usually the same as the
  /// probe timeout configured in the kernel.
  final Duration localProbeTimeout;

  /// how frequently to run the polling task
  final Duration heartbeatPollingInterval;

  /// maximum number of missed push observations before marking offline
  final int maxMissedObservations;

  /// number of consecutive poll failures required before reporting a device
  /// as offline
  final int consecutiveFailureThreshold;

  /// when starting a push observation, allow this many retries before
  /// giving up on the current timestamp
  final int heartbeatRetryMaxAttempts;

  /// multiplier applied to [heartbeatPollingInterval] to compute the
  /// observation timeout timer.
  final int observationTimeoutMultiplier;

  Timer? _timer;
  bool _isStarted = false;
  int _batchDepth = 0;

  // state maps keyed by device id
  final Map<String, BoundDevice> _devices = {};
  final Map<String, HeartbeatMethod> _methods = {};
  final Map<String, int> _consecutiveFailures = {};
  final Map<String, DateTime> _lastSeen = {};

  // observation-specific state
  final Map<String, int> _missedObservations = {};
  final Map<String, Timer> _observationTimeoutTimers = {};
  final Map<String, StreamSubscription> _observationSubscriptions = {};

  final StreamController<bool> _batchController = StreamController.broadcast();

  final Lock _hbLock = Lock();
  final Lock _observationLock = Lock();
  final CancellationToken _pollCancelToken = CancellationToken();

  final StreamController<Device> _failureController = StreamController.broadcast();
  final StreamController<void> _tickController = StreamController.broadcast();

  DefaultHeartbeatService(
    this._logger, {
    this.localProbeTimeout = const Duration(seconds: 1),
    this.heartbeatPollingInterval = const Duration(seconds: 5),
    this.maxMissedObservations = 3,
    this.consecutiveFailureThreshold = 2,
    this.heartbeatRetryMaxAttempts = 1,
    this.observationTimeoutMultiplier = 2,
  });

  @override
  Future<void> start() async {
    if (_isStarted) return;
    _isStarted = true;
    _timer ??= Timer.periodic(heartbeatPollingInterval, (_) {
      try {
        _heartbeatPollingPeriodicTask();
      } catch (e, st) {
        _logger.e(e.toString(), error: e, stackTrace: st);
      } finally {
        // notify listeners after each cycle
        _tickController.add(null);
      }
    });
  }

  @override
  Future<void> stop() async {
    if (!_isStarted) return;
    _isStarted = false;
    _timer?.cancel();
    _timer = null;
    _pollCancelToken.cancel();

    // clear observations
    for (final sub in _observationSubscriptions.values) {
      sub.cancel();
    }
    _observationSubscriptions.clear();

    for (final t in _observationTimeoutTimers.values) {
      t.cancel();
    }
    _observationTimeoutTimers.clear();

    _devices.clear();
    _methods.clear();
    _consecutiveFailures.clear();
    _missedObservations.clear();
  }

  @override
  void enterBatch() {
    if (_batchDepth == 0) {
      _batchController.add(true);
      _observationLock.synchronized(() {
        for (final timer in _observationTimeoutTimers.values) {
          timer.cancel();
        }
        _observationTimeoutTimers.clear();
      });
    }
    _batchDepth++;
  }

  @override
  void exitBatch() {
    if (_batchDepth == 0) {
      return;
    }

    _batchDepth--;
    if (_batchDepth == 0) {
      _batchController.add(false);
      _observationLock.synchronized(() {
        for (final deviceId in _observationSubscriptions.keys) {
          _missedObservations[deviceId] = 0;
          _resetObservationTimeout(deviceId);
        }
      });
    }
  }

  @override
  void suspend() {
    // deprecated: forward to batch API for compatibility
    enterBatch();
  }

  @override
  void resume() {
    // deprecated: forward to batch API for compatibility
    exitBatch();
  }

  @override
  void registerDevice(BoundDevice bound, HeartbeatMethod method) {
    final id = bound.device.id;
    _devices[id] = bound;
    _methods[id] = method;
    _consecutiveFailures.remove(id);

    if (method == HeartbeatMethod.push) {
      _startHeartbeatObservation(bound.device, bound.driver);
    }
  }

  @override
  void unregisterDevice(String deviceID) {
    _devices.remove(deviceID);
    _methods.remove(deviceID);
    _consecutiveFailures.remove(deviceID);
    _stopHeartbeatObservation(deviceID);
    _missedObservations.remove(deviceID);
    _observationTimeoutTimers[deviceID]?.cancel();
    _observationTimeoutTimers.remove(deviceID);
  }

  @override
  Stream<Device> get onFailure => _failureController.stream;

  @override
  Stream<void> get onTick => _tickController.stream;

  @override
  bool get isActive => _isStarted && !_isInBatch;

  bool get _isInBatch => _batchDepth > 0;

  @override
  void onDeviceCommunication(String deviceID) {
    // tap communication time
    _lastSeen[deviceID] = DateTime.now();
    // push‑mode devices treat any communication as a heartbeat
    _observationLock.synchronized(() {
      if (_missedObservations.containsKey(deviceID)) {
        _missedObservations[deviceID] = 0;
        _resetObservationTimeout(deviceID);
      }
    });
  }

  Future<bool> _tryDoHeartBeat(BoundDevice bd, Duration timeout) async {
    try {
      final result = await retry(
        () async {
          final success = await bd.driver
              .heartbeat(bd.device, cancelToken: _pollCancelToken)
              .timeout(timeout)
              .asCancellable(_pollCancelToken);
          if (!success) {
            throw Exception('Heartbeat failed');
          }
          return success;
        },
        maxAttempts: heartbeatRetryMaxAttempts,
        delayFactor: const Duration(milliseconds: 500),
        maxDelay: const Duration(seconds: 1),
        randomizationFactor: 0.1,
      );
      return result;
    } catch (e, stackTrace) {
      _logger.t("Failed to do heartbeat after retries", error: e, stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> _startHeartbeatObservation(Device device, Driver driver) async {
    try {
      // Check if the driver supports observation (has observation method)
      if (driver is! BorneoLyfiCoapDriver) {
        _logger.w('Driver ${driver.runtimeType} does not support push heartbeat observation');
        return;
      }

      final deviceId = device.id;

      // Clean up any existing observation
      await _stopHeartbeatObservation(deviceId);

      _logger.d('Starting heartbeat observation for device $deviceId');

      // Start observation
      final obsStream = await driver.startHeartbeatObservation(device);

      _observationSubscriptions[deviceId] = obsStream.listen(
        (timestamp) {
          _onHeartbeatReceived(deviceId, timestamp);
        },
        onError: (error) {
          final errStr = error.toString();
          final isTransient = errStr.contains('CoapRequestException') || errStr.contains('timed out');
          if (isTransient) {
            _logger.w('Heartbeat observation transient error for device $deviceId: $error');
            _onHeartbeatMissed(deviceId); // count as a single missed heartbeat
          } else {
            _logger.e('Heartbeat observation unexpected error for device $deviceId: $error');
            // For unexpected errors we still treat it as a single miss (not double)
            _onHeartbeatMissed(deviceId);
          }
        },
        onDone: () {
          _logger.w('Heartbeat observation ended for device $deviceId');
          _onHeartbeatMissed(deviceId);
        },
        cancelOnError: false,
      );

      // Reset missed observations counter (within observation lock)
      await _observationLock.synchronized(() {
        _missedObservations[deviceId] = 0;
        // Set up timeout timer
        _resetObservationTimeout(deviceId);
      });
    } catch (e, stackTrace) {
      _logger.e('Failed to start heartbeat observation for device ${device.id}', error: e, stackTrace: stackTrace);
    }
  }

  void _onHeartbeatReceived(String deviceId, dynamic timestamp) {
    _lastSeen[deviceId] = DateTime.now();
    if (_isInBatch) {
      return;
    }

    _observationLock.synchronized(() {
      // Reset missed observations counter
      _missedObservations[deviceId] = 0;

      // Reset timeout timer
      _resetObservationTimeout(deviceId);
    });
  }

  void _onHeartbeatMissed(String deviceId) {
    if (_isInBatch) {
      return;
    }

    final boundDevice = _devices[deviceId];
    if (boundDevice == null) {
      _logger.t('Ignoring missed heartbeat for unregistered device $deviceId');
      return;
    }

    _observationLock.synchronized(() {
      if (!_devices.containsKey(deviceId)) {
        return;
      }

      _missedObservations[deviceId] = (_missedObservations[deviceId] ?? 0) + 1;
      _logger.i('Heartbeat missed for device $deviceId. Total missed: ${_missedObservations[deviceId]}');

      if (_missedObservations[deviceId]! >= maxMissedObservations) {
        _logger.w('Device $deviceId marked offline after $maxMissedObservations missed observations');
        _failureController.add(boundDevice.device);
        // Call the lock-free helper directly; we already hold _observationLock
        // and _stopHeartbeatObservation() would try to re-acquire it, causing a
        // deadlock with the non-reentrant Lock from the synchronized package.
        _cancelObservationDataLocked(deviceId);
      } else {
        // Reset timeout timer for next observation
        _resetObservationTimeout(deviceId);
      }
    });
  }

  void _resetObservationTimeout(String deviceId) {
    // Note: This method is called within _observationLock.synchronized()
    _observationTimeoutTimers[deviceId]?.cancel();

    // Set timeout for a multiple of the normal heartbeat interval
    _observationTimeoutTimers[deviceId] = Timer(
      heartbeatPollingInterval * observationTimeoutMultiplier,
      () => _onHeartbeatMissed(deviceId),
    );
  }

  /// Cancels and removes all observation data for [deviceId].
  /// Must be called while already holding [_observationLock].
  void _cancelObservationDataLocked(String deviceId) {
    _observationSubscriptions[deviceId]?.cancel();
    _observationSubscriptions.remove(deviceId);

    _observationTimeoutTimers[deviceId]?.cancel();
    _observationTimeoutTimers.remove(deviceId);

    _missedObservations.remove(deviceId);
  }

  Future<void> _stopHeartbeatObservation(String deviceId) async {
    await _observationLock.synchronized(() {
      _cancelObservationDataLocked(deviceId);
    });
  }

  Future<void> _heartbeatPollingPeriodicTask() async {
    if (_isInBatch || !_isStarted) {
      _logger.t('Heartbeat polling skipped because batch mode or stopped.');
      return;
    }

    if (_hbLock.locked) {
      _logger.t('Heartbeat polling skipped due to device operation lock.');
      return;
    }

    try {
      await _hbLock.synchronized(() async {
        final futures = <Future<bool>>[];
        final devices = <BoundDevice>[];

        for (final entry in _devices.entries) {
          final deviceId = entry.key;
          if (_methods[deviceId] != HeartbeatMethod.poll) continue;
          final bd = entry.value;

          if (bd.device.driverData.isBusy) {
            _logger.t('Skip heartbeat for $deviceId because driver lock is busy.');
            continue;
          }

          final queue = bd.device.driverData.queue;
          if (!queue.isIdle) {
            _logger.t('Skip heartbeat for $deviceId because IO queue is busy.');
            continue;
          }

          futures.add(_tryDoHeartBeat(bd, localProbeTimeout).catchError((_) => false).asCancellable(_pollCancelToken));
          devices.add(bd);
        }

        final results = await Future.wait(futures).asCancellable(_pollCancelToken);
        for (int i = 0; i < results.length; i++) {
          final deviceId = devices[i].device.id;
          if (!results[i]) {
            _consecutiveFailures[deviceId] = (_consecutiveFailures[deviceId] ?? 0) + 1;
            _logger.i(
              'The device(${devices[i].device}) is not responding. Consecutive failures: ${_consecutiveFailures[deviceId]}',
            );

            if (_consecutiveFailures[deviceId]! >= consecutiveFailureThreshold) {
              _consecutiveFailures.remove(deviceId);
              _failureController.add(devices[i].device);
            }
          } else {
            // successful poll, reset failure count and record last seen
            _consecutiveFailures.remove(deviceId);
            _lastSeen[deviceId] = DateTime.now();
          }
        }
      });
    } catch (e, stackTrace) {
      _logger.w("Failed to do the heartbeat: $e", error: e, stackTrace: stackTrace);
    }
  }

  @override
  Stream<bool> get batchMode => _batchController.stream;

  @override
  HeartbeatState? getState(String deviceID) {
    if (!_devices.containsKey(deviceID)) return null;
    return HeartbeatState(
      consecutiveFailures: _consecutiveFailures[deviceID] ?? 0,
      missedObservations: _missedObservations[deviceID] ?? 0,
      lastSeen: _lastSeen[deviceID],
    );
  }
}
