import 'dart:async';
import 'dart:io';
import 'package:borneo_common/exceptions.dart';
import 'package:borneo_kernel_abstractions/events.dart';
import 'package:borneo_kernel_abstractions/device_api.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/widgets.dart';
import 'package:lw_wot/wot.dart';

import 'package:borneo_common/io/net/rssi.dart';
import 'package:borneo_kernel_abstractions/models/bound_device.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/features/devices/models/events.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/shared/view_models/base_view_model.dart';

abstract class BaseDeviceViewModel extends BaseViewModel
    with WidgetsBindingObserver, ViewModelEventBusMixin, ViewModelInitFutureMixin {
  bool _isSuspectedOffline = false;

  final CancellationToken masterCancellation = CancellationToken();
  final IDeviceManager deviceManager;
  late DeviceEntity deviceEntity;

  late final StreamSubscription<DeviceBoundEvent> _onDeviceBoundEventSub;
  late final StreamSubscription<DeviceRemovedEvent> _onDeviceRemovedEventSub;
  late final StreamSubscription<DeviceEntityUpdatedEvent> _onDeviceEntityUpdatedEventSub;
  late final StreamSubscription<DeviceEntityDeletedEvent> _onDeviceEntityDeletedEventSub;

  bool isInitialized = false;
  bool _isLoaded = false;
  bool _isAvailable = true;

  String get deviceID => wotThing.id;

  RssiLevel? get rssiLevel;

  bool get isLoaded => _isLoaded;
  bool get isAvailable => _isAvailable;

  bool get isDemo => deviceEntity.isDemo;

  bool get isOnline => wotThing.getProperty<bool>('online') ?? false;
  bool get isSuspectedOffline => _isSuspectedOffline;
  bool _isReconnecting = false;
  Timer? _reconnectTimer;
  DateTime? _reconnectDeadline;
  Duration? _reconnectCountdown;

  bool get isReconnecting => _isReconnecting;
  int? get reconnectCountdownSeconds => _reconnectCountdown?.inSeconds;

  String get name => deviceEntity.name;
  String get model => deviceEntity.model;

  BoundDevice? get boundDevice {
    if (!_isAvailable || isDisposed || !deviceManager.isBound(deviceID)) {
      return null;
    }

    try {
      return deviceManager.getBoundDevice(deviceID);
    } catch (_) {
      return null;
    }
  }

  WotThing wotThing;

  BaseDeviceViewModel({
    required this.deviceManager,
    required EventBus globalEventBus,
    required this.wotThing,
    required super.gt,
    super.logger,
  }) {
    super.globalEventBus = globalEventBus;
    WidgetsBinding.instance.addObserver(this);

    _onDeviceBoundEventSub = deviceManager.allDeviceEvents.on<DeviceBoundEvent>().listen((event) {
      if (_isAvailable && event.device.id == deviceID) {
        // Inline side effects instead of relying on markOnline()'s `changed`
        // return value: LyfiThing subscribes to the same event bus and updates
        // WotThing.online synchronously *before* this callback runs, so
        // markOnline() would see isOnline==true and return changed==false,
        // silently skipping both onDeviceConnectionRecovered and notifyListeners.
        _isSuspectedOffline = false;
        _stopReconnectCountdown(notify: false);
        onDeviceConnectionRecovered();
        onDeviceBound();
        if (!isDisposed) notifyListeners();
      }
    });

    _onDeviceRemovedEventSub = deviceManager.allDeviceEvents.on<DeviceRemovedEvent>().listen((event) {
      if (_isAvailable && event.device.id == deviceID) {
        // Same race as above: WotThing.online is already false by the time
        // this callback runs, so markOffline() returns changed==false and
        // never calls notifyListeners(), freezing the UI.
        _isSuspectedOffline = false;
        _stopReconnectCountdown(notify: false);
        onDeviceRemoved();
        if (!isDisposed) notifyListeners();
      }
    });

    _onDeviceEntityUpdatedEventSub = deviceManager.allDeviceEvents.on<DeviceEntityUpdatedEvent>().listen((event) {
      if (_isAvailable && event.updated.id == deviceID) {
        deviceEntity = event.updated;
        notifyListeners();
      }
    });

    _onDeviceEntityDeletedEventSub = deviceManager.allDeviceEvents.on<DeviceEntityDeletedEvent>().listen((event) {
      if (event.id == deviceID) {
        markUnavailable();
      }
    });
  }

  Future<void> initialize() async {
    assert(!isInitialized);
    try {
      deviceEntity = await deviceManager.getDevice(deviceID);
      if (!_isAvailable || isDisposed) {
        return;
      }
      _isLoaded = true;
      _isSuspectedOffline = false;
      await onInitialize();
    } on KeyNotFoundException {
      markUnavailable(notify: false);
      rethrow;
    } on IOException catch (ioex, stackTrace) {
      logger?.e(ioex.toString(), error: ioex, stackTrace: stackTrace);
      if (isOnline) {
        super.notifyAppError(
          gt.translate('Failed to initialize device: {msg}', nArgs: {'msg': ioex.toString()}),
          error: ioex,
          stackTrace: stackTrace,
        );
      }
    } catch (e, stackTrace) {
      super.notifyAppError(
        gt.translate('Failed to initialize device: {msg}', nArgs: {'msg': e.toString()}),
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      isInitialized = true;
    }
  }

  Future<void> onInitialize();

  @override
  void dispose() {
    assert(!isDisposed);

    _onDeviceBoundEventSub.cancel();
    _onDeviceRemovedEventSub.cancel();
    _onDeviceEntityUpdatedEventSub.cancel();
    _onDeviceEntityDeletedEventSub.cancel();
    _reconnectTimer?.cancel();
    if (masterCancellation.hasCancellables) {
      masterCancellation.cancel();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<bool> tryOperateDevice<T extends IDeviceApi>(
    Future<void> Function(T, {CancellationToken? cancelToken}) operation, {
    CancellationToken? cancelToken,
  }) async {
    if (!_isAvailable || !isOnline || isBusy || !isInitialized) {
      return false;
    }

    final api = boundDevice?.api<T>();
    if (api == null) {
      return false;
    }

    try {
      await operation(api, cancelToken: cancelToken);
      if (!_isAvailable || isDisposed) {
        return false;
      }
    } on CancelledException catch (e, stackTrace) {
      logger?.i('A periodic refresh task has been cancelled.', error: e, stackTrace: stackTrace);
    } catch (e, stackTrace) {
      logger?.i("Failed to operate device: $e", error: e, stackTrace: stackTrace);
    }
    return true;
  }

  void onDeviceBound() {}

  void onDeviceRemoved() {}

  void onDeviceDeleted() {}

  @protected
  void onDeviceSuspectedOffline() {}

  @protected
  void onDeviceConnectionRecovered() {}

  @protected
  bool markUnavailable({bool notify = true}) {
    if (!_isAvailable) {
      return false;
    }

    _isAvailable = false;
    _isLoaded = false;
    _isSuspectedOffline = false;
    _isReconnecting = false;
    _stopReconnectCountdown(notify: false);
    onDeviceDeleted();
    if (notify && !isDisposed) {
      notifyListeners();
    }
    return true;
  }

  @protected
  bool markOnline({bool notify = true}) {
    if (!_isAvailable) {
      return false;
    }
    final bool wasOffline = !isOnline;
    final bool wasSuspected = _isSuspectedOffline;
    _isSuspectedOffline = false;
    _stopReconnectCountdown(notify: false);
    if ((wasOffline || wasSuspected) && !isDisposed) {
      onDeviceConnectionRecovered();
      if (notify) {
        notifyListeners();
      }
      return true;
    }
    return false;
  }

  @protected
  bool markOffline({bool notify = true}) {
    if (!_isAvailable) {
      return false;
    }
    final bool changed = isOnline || _isSuspectedOffline;
    if (!changed) {
      return false;
    }
    _isSuspectedOffline = false;
    _stopReconnectCountdown(notify: false);

    if (!isDisposed && notify) {
      notifyListeners();
    }
    return true;
  }

  @protected
  void markSuspectedOffline({bool notify = true}) {
    if (!_isAvailable || _isSuspectedOffline || isDisposed) {
      return;
    }
    _isSuspectedOffline = true;
    _stopReconnectCountdown(notify: false);
    onDeviceSuspectedOffline();
    if (notify) {
      notifyListeners();
    }
  }

  @protected
  void clearSuspectedOffline({bool notify = true}) {
    if (!_isAvailable || !_isSuspectedOffline || isDisposed) {
      return;
    }
    _isSuspectedOffline = false;
    onDeviceConnectionRecovered();
    if (notify) {
      notifyListeners();
    }
  }

  @protected
  Future<T> runDeviceCommand<T>(
    Future<T> Function() action, {
    Duration? timeout,
    bool resetSuspectedOnSuccess = true,
  }) async {
    if (!_isAvailable) {
      throw StateError('Device is no longer available.');
    }

    try {
      final future = action();
      final result = timeout != null ? await future.timeout(timeout) : await future;
      if (!_isAvailable || isDisposed) {
        throw StateError('Device is no longer available.');
      }
      if (resetSuspectedOnSuccess && _isSuspectedOffline) {
        clearSuspectedOffline();
      }
      return result;
    } on TimeoutException catch (e, stackTrace) {
      _handleConnectivityFailure(e, stackTrace);
      rethrow;
    } on SocketException catch (e, stackTrace) {
      _handleConnectivityFailure(e, stackTrace);
      rethrow;
    } on IOException catch (e, stackTrace) {
      _handleConnectivityFailure(e, stackTrace);
      rethrow;
    }
  }

  void _handleConnectivityFailure(Object error, StackTrace stackTrace) {
    if (!_isAvailable) {
      return;
    }
    logger?.w('Device command failed: $error', error: error, stackTrace: stackTrace);
    markSuspectedOffline();
  }

  void _startReconnectCountdown(Duration timeout) {
    if (!_isAvailable) {
      return;
    }
    _reconnectDeadline = DateTime.now().add(timeout);
    _reconnectCountdown = timeout;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateReconnectCountdown();
    });
    if (!isDisposed) {
      notifyListeners();
    }
  }

  void _updateReconnectCountdown() {
    if (!_isAvailable || _reconnectDeadline == null) {
      return;
    }
    final remaining = _reconnectDeadline!.difference(DateTime.now());
    if (remaining.isNegative) {
      _reconnectCountdown = Duration.zero;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    } else {
      _reconnectCountdown = Duration(seconds: remaining.inSeconds + 1);
    }
    if (!isDisposed) {
      notifyListeners();
    }
  }

  void _stopReconnectCountdown({bool notify = true}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectDeadline = null;
    if (_reconnectCountdown != null) {
      _reconnectCountdown = null;
      if (notify && !isDisposed) {
        notifyListeners();
      }
    }
  }

  Future<void> reconnect({Duration? timeout}) async {
    if (!_isAvailable || isDisposed || _isReconnecting) {
      return;
    }

    final Duration effectiveTimeout = timeout ?? const Duration(seconds: 8);
    _isReconnecting = true;
    _startReconnectCountdown(effectiveTimeout);
    if (!isDisposed) {
      notifyListeners();
    }

    try {
      final bound = await deviceManager.tryBind(deviceEntity).timeout(effectiveTimeout, onTimeout: () => false);
      if (!isDisposed && _isAvailable) {
        if (bound) {
          markOnline(notify: false);
        }
      }
    } on TimeoutException catch (e, stackTrace) {
      logger?.w('Reconnect timed out', error: e, stackTrace: stackTrace);
    } on IOException catch (ioex, stackTrace) {
      logger?.e('Reconnect failed: $ioex', error: ioex, stackTrace: stackTrace);
    } catch (e, stackTrace) {
      logger?.e('Reconnect failed: $e', error: e, stackTrace: stackTrace);
    } finally {
      if (!isDisposed && _isAvailable) {
        _isReconnecting = false;
        _stopReconnectCountdown();
        notifyListeners();
      }
    }
  }

  Future<void> delete({bool shouldUpdate = false}) async {
    assert(!isBusy);

    isBusy = true;
    try {
      await deviceManager.delete(deviceID, cancelToken: masterCancellation);
    } catch (e, stackTrace) {
      notifyAppError(gt.translate('Failed to delete device'), error: e, stackTrace: stackTrace);
    } finally {
      isBusy = false;
      if (shouldUpdate && _isAvailable && !isDisposed) {
        notifyListeners();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}
