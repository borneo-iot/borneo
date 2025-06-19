import 'dart:async';
import 'dart:io';
import 'package:borneo_kernel_abstractions/events.dart';
import 'package:borneo_kernel_abstractions/idevice_api.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/widgets.dart';

import 'package:borneo_common/io/net/rssi.dart';
import 'package:borneo_kernel_abstractions/models/bound_device.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/core/services/device_manager.dart';
import 'package:borneo_app/shared/view_models/base_view_model.dart';

abstract class BaseDeviceViewModel extends BaseViewModel
    with WidgetsBindingObserver, ViewModelEventBusMixin, ViewModelInitFutureMixin {
  static const Duration timerDuration = Duration(seconds: 1);

  bool _isOnline = false;

  final CancellationToken initializationCancelToken = CancellationToken();
  final DeviceManager deviceManager;
  final String deviceID;
  late final DeviceEntity deviceEntity;

  late final StreamSubscription<DeviceBoundEvent> _onDeviceBoundEventSub;
  late final StreamSubscription<DeviceRemovedEvent> _onDeviceRemovedEventSub;

  bool isInitialized = false;
  bool _isLoaded = false;

  RssiLevel? get rssiLevel;

  bool get isLoaded => _isLoaded;

  Timer? _timer;

  Timer? get timer => _timer;
  bool get isOnline => _isOnline;

  String get name => deviceEntity.name;
  String get model => deviceEntity.model;
  bool get isTimerRunning => _timer?.isActive ?? false;
  BoundDevice? get boundDevice => deviceManager.getBoundDevice(deviceID);

  BaseDeviceViewModel({
    required this.deviceID,
    required this.deviceManager,
    required EventBus globalEventBus,
    super.logger,
  }) {
    super.globalEventBus = globalEventBus;
    WidgetsBinding.instance.addObserver(this);

    _onDeviceBoundEventSub = deviceManager.allDeviceEvents.on<DeviceBoundEvent>().listen((event) {
      if (event.device.id == deviceID) {
        _isOnline = true;
        onDeviceBound();
        if (!isTimerRunning) {
          startTimer();
        }
        notifyListeners();
      }
    });

    _onDeviceRemovedEventSub = deviceManager.allDeviceEvents.on<DeviceRemovedEvent>().listen((event) {
      if (event.device.id == deviceID) {
        _isOnline = false;
        if (isTimerRunning) {
          stopTimer();
        }
        if (taskQueue.size > 0) {
          taskQueueCancelToken.cancel();
        }
        onDeviceRemoved();
        notifyListeners();
      }
    });
  }

  Future<void> initialize() async {
    assert(!isInitialized);
    isBusy.value = true;
    try {
      deviceEntity = await deviceManager.getDevice(deviceID);
      _isLoaded = true;
      _isOnline = deviceManager.isBound(deviceID);
      await onInitialize();
      if (isOnline) {
        await refreshStatus();
      }
    } on IOException catch (ioex, stackTrace) {
      logger?.e(ioex.toString(), error: ioex, stackTrace: stackTrace);
      if (isOnline) {
        super.notifyAppError('Failed to initialize device: $ioex', stackTrace: stackTrace);
      }
    } catch (e, stackTrace) {
      logger?.e('Failed to initialize device(${deviceEntity.toString()}): $e', error: e, stackTrace: stackTrace);
      super.notifyAppError('Failed to initialize device: $e', stackTrace: stackTrace);
    } finally {
      if (isOnline) {
        startTimer();
      }
      isInitialized = true;
      isBusy.value = false;
    }
  }

  Future<void> onInitialize();

  @override
  void dispose() {
    assert(!isDisposed);
    if (isTimerRunning) {
      stopTimer();
    }
    _onDeviceBoundEventSub.cancel();
    _onDeviceRemovedEventSub.cancel();
    if (!isInitialized) {
      initializationCancelToken.cancel();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<bool> tryOperateDevice<T extends IDeviceApi>(
    Future<void> Function(T, {CancellationToken? cancelToken}) operation, {
    CancellationToken? cancelToken,
  }) async {
    if (!isOnline || isBusy.value || !isInitialized) {
      return false;
    }

    final api = boundDevice?.api<T>();
    if (api == null) {
      return false;
    }

    try {
      await operation(api, cancelToken: cancelToken);
    } on CancelledException catch (e, stackTrace) {
      logger?.i('A periodic refresh task has been cancelled.', error: e, stackTrace: stackTrace);
    } catch (e, stackTrace) {
      logger?.i("Failed to operate device: $e", error: e, stackTrace: stackTrace);
    }
    return true;
  }

  void onDeviceBound() {}

  void onDeviceRemoved() {}

  Future<void> refreshStatus({CancellationToken? cancelToken});

  Future<void> _periodicRefreshTask(CancellationToken? cancelToken) async {
    if (!hasListeners || isBusy.value || !isOnline) {
      return;
    }
    try {
      await refreshStatus(cancelToken: cancelToken);
    } on CancelledException catch (e, stackTrace) {
      logger?.i('A periodic refresh task has been cancelled.', error: e, stackTrace: stackTrace);
    } on IOException catch (ioex, stackTrace) {
      logger?.e('Failed to refresh device status: $ioex', error: ioex, stackTrace: stackTrace);
    } catch (e, stackTrace) {
      logger?.i("Failed to refresh device status: $e", error: e, stackTrace: stackTrace);
      notifyAppError(e.toString(), error: e, stackTrace: stackTrace);
    } finally {
      notifyListeners();
    }
  }

  void startTimer() {
    assert(!isDisposed);

    if (!isTimerRunning) {
      _timer = Timer.periodic(timerDuration, (_) => enqueueJob(() => _periodicRefreshTask(taskQueueCancelToken)));
    }
  }

  void stopTimer() {
    assert(!isDisposed);

    if (isTimerRunning) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> delete() async {
    assert(!isBusy.value);
    stopTimer();
    isBusy.value = true;
    try {
      await deviceManager.delete(deviceID);
    } catch (e, stackTrace) {
      logger?.e('$e', error: e, stackTrace: stackTrace);
      notifyAppError('$e', stackTrace: stackTrace);
    } finally {
      isBusy.value = false;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (isTimerRunning) {
        stopTimer();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (isOnline && !isTimerRunning) {
        startTimer();
      }
    }
  }
}
