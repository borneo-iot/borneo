import 'dart:async';

import 'package:logger/logger.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:meta/meta.dart';

import 'package:borneo_common/exceptions.dart';
import 'package:borneo_kernel_abstractions/kernel.dart';
import 'discovery_manager_impl.dart';
import 'binding_engine_impl.dart';
import 'heartbeat_service_impl.dart';

export 'binding_engine_impl.dart';

final class DefaultKernel implements IKernel {
  static const Duration kStartupDiscoveryDuration = Duration(seconds: 15);
  static const Duration kDiscoveryLossGracePeriod = Duration(seconds: 8);
  static const Duration kNetworkRestartDebounce = Duration(seconds: 2);

  // Configurable heartbeat / probe parameters. Defaults chosen to detect
  // disconnects faster while remaining conservative for flaky networks.
  final Duration localProbeTimeout;
  final Duration localBindTimeout;
  final int maxConcurrentProbes;
  final Duration heartbeatPollingInterval;
  final int maxMissedObservations;
  final int consecutiveFailureThreshold;
  final int heartbeatRetryMaxAttempts;
  final int observationTimeoutMultiplier;
  final Duration discoveryLossGracePeriod;
  final Duration networkRestartDebounce;

  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isScanning = false;
  bool _scanRequested = false;

  late final HeartbeatService _heartbeatService;

  final Logger _logger;
  final IDriverRegistry _driverRegistry;
  final IMdnsProvider? mdnsProvider;
  final INetworkMonitor? networkMonitor;
  late final DiscoveryManager _discoveryManager;
  late final BindingEngine _bindingEngine;

  // devices the caller has told us about.  the map is mutated by
  // registerDevice()/unregisterDevice() at any time, including while the
  // heartbeat tick is iterating; callers must not rely on holding an iterator
  // across an await.  the _onHeartbeatTick implementation takes a snapshot
  // of the values before iterating to avoid ConcurrentModificationError.
  final Map<String, BoundDeviceDescriptor> _registeredDevices = {};
  // use the new interface for dispatching events; currently we create
  // a DefaultEventDispatcher but expose it as EventDispatcher so callers
  // are insulated from the concrete type.  This avoids leaking the
  // legacy GlobalDevicesEventBus throughout the codebase.
  final EventDispatcher _events = DefaultEventDispatcher();
  final CancellationToken _masterCancelToken = CancellationToken();
  late final StreamSubscription<DeviceOfflineEvent> _deviceOfflineSub;
  late final StreamSubscription<FoundDeviceEvent> _foundDeviceEventSub;
  late final StreamSubscription<DiscoveredDevice> _lostDeviceSub;
  late final StreamSubscription<DeviceCommunicationEvent> _deviceCommunicationSub;
  late final StreamSubscription<DeviceBoundEvent> _deviceBoundSub;
  late final StreamSubscription<DeviceRemovedEvent> _deviceRemovedSub;
  StreamSubscription<NetworkSnapshot>? _networkMonitorSub;

  // backoff state for retrying unbound devices
  final Map<String, int> _backoffCount = {};
  final Map<String, DateTime> _nextBindAttempt = {};
  final Map<String, Timer> _pendingDiscoveryLossTimers = {};
  Timer? _networkRestartTimer;
  NetworkSnapshot? _lastNetworkSnapshot;
  Duration? _pendingScanTimeout;
  DateTime? _scanRequestedAt;
  static const Duration _maxBackoff = Duration(minutes: 1);

  // Default values
  static const int _defaultMaxMissedObservations = 3;
  static const int _defaultConsecutiveFailureThreshold = 2;
  static const int _defaultHeartbeatRetryMaxAttempts = 1;
  static const int _defaultObservationTimeoutMultiplier = 2;
  static const int _defaultMaxConcurrentProbes = 4;

  @override
  bool get isInitialized => _isInitialized;

  @override
  EventDispatcher get events => _events;

  @override
  Iterable<Driver> get activatedDrivers => _bindingEngine.boundDevices.map((b) => b.driver);

  @override
  Iterable<BoundDevice> get boundDevices => _bindingEngine.boundDevices;

  @override
  bool get isBusy => _bindingEngine.isBusy;

  @override
  bool get isScanning => _isScanning || _discoveryManager.isActive;

  DefaultKernel(
    this._logger,
    this._driverRegistry, {
    this.mdnsProvider,
    this.networkMonitor,
    DiscoveryManager? discoveryManager,
    BindingEngine? bindingEngine,
    HeartbeatService? heartbeatService,
    // allow overriding heartbeat/probe parameters for faster detection
    Duration? localProbeTimeout,
    Duration? localBindTimeout,
    int? maxConcurrentProbes,
    Duration? heartbeatPollingInterval,
    int? maxMissedObservations,
    int? consecutiveFailureThreshold,
    int? heartbeatRetryMaxAttempts,
    int? observationTimeoutMultiplier,
    Duration? discoveryLossGracePeriod,
    Duration? networkRestartDebounce,
  }) : localProbeTimeout = localProbeTimeout ?? const Duration(seconds: 1),
       localBindTimeout = localBindTimeout ?? const Duration(seconds: 5),
       maxConcurrentProbes = maxConcurrentProbes ?? _defaultMaxConcurrentProbes,
       heartbeatPollingInterval = heartbeatPollingInterval ?? const Duration(seconds: 5),
       maxMissedObservations = maxMissedObservations ?? _defaultMaxMissedObservations,
       consecutiveFailureThreshold = consecutiveFailureThreshold ?? _defaultConsecutiveFailureThreshold,
       heartbeatRetryMaxAttempts = heartbeatRetryMaxAttempts ?? _defaultHeartbeatRetryMaxAttempts,
       observationTimeoutMultiplier = observationTimeoutMultiplier ?? _defaultObservationTimeoutMultiplier,
       discoveryLossGracePeriod = discoveryLossGracePeriod ?? kDiscoveryLossGracePeriod,
       networkRestartDebounce = networkRestartDebounce ?? kNetworkRestartDebounce {
    // initialize late discovery manager after events are available
    _discoveryManager =
        discoveryManager ?? DefaultDiscoveryManager(_logger, _driverRegistry, _events, mdnsProvider: mdnsProvider);

    // binding engine initialization
    _bindingEngine =
        bindingEngine ??
        DefaultBindingEngine(
          _logger,
          _driverRegistry,
          _events,
          localBindTimeout: localBindTimeout,
          maxConcurrentProbes: this.maxConcurrentProbes,
        );

    _logger.i('Loading the kernel...');

    // construct heartbeat service (allow injection for tests)
    _heartbeatService =
        heartbeatService ??
        DefaultHeartbeatService(
          _logger,
          localProbeTimeout: this.localProbeTimeout,
          heartbeatPollingInterval: this.heartbeatPollingInterval,
          maxMissedObservations: this.maxMissedObservations,
          consecutiveFailureThreshold: this.consecutiveFailureThreshold,
          heartbeatRetryMaxAttempts: this.heartbeatRetryMaxAttempts,
          observationTimeoutMultiplier: this.observationTimeoutMultiplier,
        );

    _heartbeatService.onFailure.listen(_onHeartbeatFailure);

    _deviceOfflineSub = _events.on<DeviceOfflineEvent>().listen(_handleDeviceOfflineEvent);

    _deviceCommunicationSub = _events.on<DeviceCommunicationEvent>().listen(_handleDeviceCommunication);

    _foundDeviceEventSub = _events.on<FoundDeviceEvent>().listen(_onDeviceFound);

    // hook engine events so kernel can start/stop heartbeat
    _deviceBoundSub = _events.on<DeviceBoundEvent>().listen(_handleDeviceBoundEvent);
    _deviceRemovedSub = _events.on<DeviceRemovedEvent>().listen(_handleDeviceRemovedEvent);

    // subscribe to heartbeat ticks so we can probe unbound devices
    // backoff counters for unbound devices (stored as fields)

    _heartbeatService.onTick.listen((_) => _onHeartbeatTick());

    // forward discovery manager lost events to kernel event bus
    _lostDeviceSub = _discoveryManager.onDeviceLost.listen(_onDeviceLost);

    if (networkMonitor != null) {
      _networkMonitorSub = networkMonitor!.onNetworkChanged.listen(_onNetworkChanged);
    }
  }

  // --------- private event handlers extracted from constructor ----------

  void _onHeartbeatFailure(Device device) {
    _events.fire(DeviceOfflineEvent(device));
  }

  Future<void> _handleDeviceOfflineEvent(DeviceOfflineEvent event) async {
    _cancelPendingDiscoveryLoss(event.device.fingerprint);
    try {
      await unbind(event.device.id);
    } catch (e, stackTrace) {
      _logger.e('Failed to unbind offline device ${event.device.id}: $e', error: e, stackTrace: stackTrace);
    }
  }

  void _handleDeviceCommunication(DeviceCommunicationEvent event) {
    _heartbeatService.onDeviceCommunication(event.device.id);
  }

  void _handleDeviceBoundEvent(DeviceBoundEvent e) {
    final bound = _bindingEngine.getBoundDevice(e.device.id);
    if (bound == null) return;
    final drvDesc = _driverRegistry.metaDrivers[bound.driverID];
    final method = drvDesc?.heartbeatMethod ?? HeartbeatMethod.poll;
    _heartbeatService.registerDevice(bound, method);
  }

  void _handleDeviceRemovedEvent(DeviceRemovedEvent e) {
    _cancelPendingDiscoveryLoss(e.device.fingerprint);
    _heartbeatService.unregisterDevice(e.device.id);
  }

  // guard against overlapping tick executions. a second timer firing while
  // the first is still awaiting may also modify the registered map and would
  // be wasteful.
  bool _heartbeatTickRunning = false;

  Future<void> _onHeartbeatTick() async {
    if (!_isInitialized || _isDisposed) return;
    if (isBusy) return; // let binding engine deal with concurrency
    if (_heartbeatTickRunning) return;
    _heartbeatTickRunning = true;
    try {
      final now = DateTime.now();
      const baseInterval = Duration(seconds: 1);

      // take a snapshot because tryBind/other async work may async-await, and
      // callers can register/unregister devices concurrently. iterating over the
      // live map would throw ConcurrentModificationError if its length changes.
      final toProbe = _registeredDevices.values.where((d) => !isBound(d.device.id)).toList();

      // try to bind any registered but currently unbound devices
      for (final descriptor in toProbe) {
        final id = descriptor.device.id;
        final next = _nextBindAttempt[id] ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (now.isBefore(next)) continue;

        bool success = false;
        try {
          success = await tryBind(descriptor.device, descriptor.driverID);
        } catch (_) {
          success = false;
        }

        if (success) {
          _backoffCount.remove(id);
          _nextBindAttempt.remove(id);
        } else {
          final count = (_backoffCount[id] ?? 0) + 1;
          _backoffCount[id] = count;
          // interval = min(base * 2^(count-1), maxBackoff)
          // protect against integer overflow or resulting duration overflowing
          // the valid DateTime range. 1 << (count-1) may overflow when count is
          // huge, so clamp the shift amount.
          const int maxShift = 62; // safe even on 64-bit
          final int shift = (count - 1).clamp(0, maxShift);
          final Duration candidate = baseInterval * (1 << shift);
          final Duration wait = candidate < _maxBackoff ? candidate : _maxBackoff;
          try {
            _nextBindAttempt[id] = now.add(wait);
          } on RangeError catch (_) {
            // if adding still produces an invalid DateTime, fall back to maxBackoff
            _nextBindAttempt[id] = now.add(_maxBackoff);
          }
        }
      }
    } finally {
      _heartbeatTickRunning = false;
    }
  }

  // ---------------------------------------------------------------------

  @override
  Future<void> start({CancellationToken? cancelToken}) async {
    _logger.i('Starting the device management kernel...');

    await _heartbeatService.start();
    _isInitialized = true;
    _logger.i('Kernel has been started.');
  }

  @override
  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;

      if (isScanning) {
        _isScanning = false;
        // let discovery manager cleanup if necessary
        _discoveryManager.stop();
      }

      _masterCancelToken.cancel();
      _heartbeatService.stop();

      _deviceOfflineSub.cancel();
      _foundDeviceEventSub.cancel();
      _lostDeviceSub.cancel();
      _deviceCommunicationSub.cancel();
      _deviceBoundSub.cancel();
      _deviceRemovedSub.cancel();
      _networkMonitorSub?.cancel();
      _networkRestartTimer?.cancel();
      _cancelAllPendingDiscoveryLosses();

      _discoveryManager.dispose();

      // binding engine manages its own subscriptions and drivers
      _bindingEngine.dispose();

      _events.destroy();
    }
  }

  @override
  BoundDevice getBoundDevice(String deviceID) {
    _ensureStarted();
    if (deviceID.isEmpty) {
      throw ArgumentError('`deviceID` cannnot be empty.', 'deviceID');
    }
    if (!_registeredDevices.containsKey(deviceID)) {
      throw ArgumentError('Cannot found deviceID `$deviceID`', 'deviceID');
    }
    final bound = _bindingEngine.getBoundDevice(deviceID);
    if (bound == null) {
      final dev = _registeredDevices[deviceID];
      throw DeviceNotBoundError('Cannot found the bound ${dev!.device}', dev.device);
    }
    return bound;
  }

  @override
  bool isBound(String deviceID) {
    _ensureStarted();
    if (deviceID.isEmpty) {
      throw ArgumentError('`deviceID` cannnot be empty.', 'deviceID');
    }
    return _bindingEngine.getBoundDevice(deviceID) != null;
  }

  SupportedDeviceDescriptor? _matchesDriver(DiscoveredDevice discovered) {
    _ensureStarted();
    for (var meta in _driverRegistry.metaDrivers.values) {
      final matched = meta.matches(discovered);
      if (matched != null) {
        return matched;
      }
    }
    return null;
  }

  @override
  Future<bool> tryBind(Device device, String driverID, {CancellationToken? cancelToken}) async {
    if (isBound(device.id)) {
      return true;
    }
    _ensureStarted();
    assert(_registeredDevices.containsKey(device.id));
    return _bindingEngine.tryBind(device, driverID, cancelToken: cancelToken);
  }

  @override
  Future<void> bind(Device device, String driverID, {CancellationToken? cancelToken}) async {
    cancelToken?.throwIfCancelled();
    _ensureStarted();
    assert(_registeredDevices.containsKey(device.id));

    await _bindingEngine.bind(device, driverID, cancelToken: cancelToken);
  }

  @override
  Future<void> unbind(String deviceID, {CancellationToken? cancelToken}) async {
    _ensureStarted();
    assert(_registeredDevices.containsKey(deviceID));
    await _bindingEngine.unbind(deviceID, cancelToken: cancelToken);
  }

  @override
  Future<void> unbindAll({CancellationToken? cancelToken}) async {
    _ensureStarted();
    await _bindingEngine.unbindAll(cancelToken: cancelToken);
  }

  // heartbeat timer logic moved into HeartbeatService

  // polling helper moved into HeartbeatService

  // observation logic moved into HeartbeatService

  // moved to HeartbeatService

  // communication handling moved to HeartbeatService

  // observation failure handled by HeartbeatService

  // helper moved to HeartbeatService

  // helper moved to HeartbeatService

  // full heartbeat polling and observation logic moved into service

  /// Exposed for testing so we can drive the heartbeat service without
  /// relying on a real timer.  The implementation simply forwards to the
  /// private `_onHeartbeatTick` method.
  @visibleForTesting
  Future<void> runHeartbeatTick() => _onHeartbeatTick();

  void _ensureStarted() {
    if (_isInitialized == false) {
      throw InvalidOperationException(message: 'The kernel has not been initialized!');
    }
    assert(!_isDisposed);
  }

  @override
  void suspendHeartbeat() {
    // deprecated wrapper
    _heartbeatService.suspend();
  }

  @override
  void resumeHeartbeat() {
    // deprecated wrapper
    _heartbeatService.resume();
  }

  @override
  void enterHeartbeatBatch() {
    _heartbeatService.enterBatch();
  }

  @override
  void exitHeartbeatBatch() {
    _heartbeatService.exitBatch();
  }

  @override
  HeartbeatState? getHeartbeatState(String deviceID) {
    return _heartbeatService.getState(deviceID);
  }

  void _onDeviceFound(FoundDeviceEvent event) {
    _ensureStarted();
    _logger.d(
      'Found mDNS service: , name=`${event.discovered.name}`, host=`${event.discovered.host}`, port=`${event.discovered.port}`',
    );
    final matched = _matchesDriver(event.discovered);
    if (matched != null) {
      _cancelPendingDiscoveryLoss(matched.fingerprint);
      final knownDevice = _findRegisteredDeviceByFingerprint(matched.fingerprint);
      if (knownDevice != null) {
        if (knownDevice.address != matched.address) {
          _logger.i('Known device address changed: `${knownDevice.address}` -> `${matched.address}`');
          _events.fire(KnownDeviceDiscoveryUpdatedEvent(knownDevice, matched));
        }
        return;
      }

      if (_bindingEngine.boundDevices.every((x) => x.device.fingerprint != matched.fingerprint)) {
        _logger.i('Unbound device found: `${matched.address}`');
        _events.fire(UnboundDeviceDiscoveredEvent(matched));
      }
    }
  }

  void _onDeviceLost(DiscoveredDevice discovered) {
    _ensureStarted();
    final matched = _matchesDriver(discovered);
    if (matched == null) {
      return;
    }

    _scheduleDiscoveryLossConfirmation(matched.fingerprint);
  }

  void _scheduleDiscoveryLossConfirmation(String fingerprint) {
    _cancelPendingDiscoveryLoss(fingerprint);
    _pendingDiscoveryLossTimers[fingerprint] = Timer(discoveryLossGracePeriod, () {
      _pendingDiscoveryLossTimers.remove(fingerprint);
      if (_isDisposed || !_isInitialized) {
        return;
      }

      final knownDevice = _findRegisteredDeviceByFingerprint(fingerprint);
      if (knownDevice == null) {
        _events.fire(UnboundDeviceLostEvent(fingerprint));
        return;
      }

      final bound = _bindingEngine.getBoundDevice(knownDevice.id);
      if (bound != null) {
        _logger.w('Bound device loss confirmed after grace period: `${knownDevice.id}`');
        _events.fire(DeviceOfflineEvent(bound.device));
        return;
      }

      _events.fire(UnboundDeviceLostEvent(fingerprint));
    });
  }

  Device? _findRegisteredDeviceByFingerprint(String fingerprint) {
    for (final descriptor in _registeredDevices.values) {
      if (descriptor.device.fingerprint == fingerprint) {
        return descriptor.device;
      }
    }
    return null;
  }

  @override
  Future<void> startDevicesScanning({Duration? timeout, CancellationToken? cancelToken}) async {
    if (_scanRequested) {
      return;
    }
    _scanRequested = true;
    _pendingScanTimeout = timeout;
    _scanRequestedAt = DateTime.now();

    final snapshot = await _currentNetworkSnapshot();
    _lastNetworkSnapshot = snapshot;
    if (_canRunDiscoveryOn(snapshot)) {
      await _startActiveDiscovery(timeout: _remainingScanTimeout(), cancelToken: cancelToken);
    }
  }

  @override
  Future<void> stopDevicesScanning({CancellationToken? cancelToken}) async {
    _scanRequested = false;
    _pendingScanTimeout = null;
    _scanRequestedAt = null;
    _networkRestartTimer?.cancel();
    if (!_isScanning && !_discoveryManager.isActive) {
      return;
    }
    await _stopActiveDiscovery();
  }

  Future<void> _startActiveDiscovery({Duration? timeout, CancellationToken? cancelToken}) async {
    if (_isScanning || _discoveryManager.isActive) {
      return;
    }
    _isScanning = true;
    await _discoveryManager.start(timeout: timeout);
    _events.fire(DeviceDiscoveringStartedEvent());

    if (timeout != null) {
      Future.delayed(timeout, stopDevicesScanning).asCancellable(cancelToken);
    }
  }

  Future<void> _stopActiveDiscovery() async {
    if (!_isScanning && !_discoveryManager.isActive) {
      return;
    }
    try {
      await _discoveryManager.stop();
      _isScanning = false;
      if (!_isDisposed) {
        _events.fire(DeviceDiscoveringStoppedEvent());
      }
      _logger.i('Devices scanning stopped.');
    } catch (e) {
      _isScanning = false;
      _logger.e('Error stopping device scanning: $e');
      rethrow;
    }
  }

  Future<NetworkSnapshot> _currentNetworkSnapshot() async {
    if (networkMonitor == null) {
      return const NetworkSnapshot(localDiscoveryAvailable: true, fingerprint: 'unmanaged');
    }
    try {
      return await networkMonitor!.getCurrentSnapshot();
    } catch (e, stackTrace) {
      _logger.w('Failed to read network state for discovery.', error: e, stackTrace: stackTrace);
      return NetworkSnapshot.unavailable;
    }
  }

  bool _canRunDiscoveryOn(NetworkSnapshot snapshot) {
    if (networkMonitor == null) {
      return true;
    }
    return snapshot.localDiscoveryAvailable;
  }

  Duration? _remainingScanTimeout() {
    final timeout = _pendingScanTimeout;
    final requestedAt = _scanRequestedAt;
    if (timeout == null || requestedAt == null) {
      return null;
    }
    final elapsed = DateTime.now().difference(requestedAt);
    final remaining = timeout - elapsed;
    if (remaining <= Duration.zero) {
      return Duration.zero;
    }
    return remaining;
  }

  void _onNetworkChanged(NetworkSnapshot snapshot) {
    final previous = _lastNetworkSnapshot;
    _lastNetworkSnapshot = snapshot;

    if (!_scanRequested || _isDisposed || !_isInitialized) {
      return;
    }
    if (previous == snapshot) {
      return;
    }

    _networkRestartTimer?.cancel();

    if (!_canRunDiscoveryOn(snapshot)) {
      unawaited(_stopActiveDiscovery());
      return;
    }

    _networkRestartTimer = Timer(networkRestartDebounce, () {
      unawaited(_restartDiscoveryForNetworkChange());
    });
  }

  Future<void> _restartDiscoveryForNetworkChange() async {
    if (!_scanRequested || _isDisposed || !_isInitialized) {
      return;
    }

    final snapshot = await _currentNetworkSnapshot();
    _lastNetworkSnapshot = snapshot;
    if (!_canRunDiscoveryOn(snapshot)) {
      await _stopActiveDiscovery();
      return;
    }

    final remainingTimeout = _remainingScanTimeout();
    if (remainingTimeout != null && remainingTimeout <= Duration.zero) {
      await stopDevicesScanning();
      return;
    }

    if (_isScanning || _discoveryManager.isActive) {
      await _stopActiveDiscovery();
    }

    await _startActiveDiscovery(timeout: remainingTimeout);
  }

  @override
  void registerDevice(BoundDeviceDescriptor device) {
    _registeredDevices[device.device.id] = device;
  }

  @override
  void registerDevices(Iterable<BoundDeviceDescriptor> devices) {
    for (final d in devices) {
      _registeredDevices[d.device.id] = d;
    }
  }

  @override
  void unregisterDevice(String deviceID) {
    final removed = _registeredDevices.remove(deviceID);
    if (removed != null) {
      _cancelPendingDiscoveryLoss(removed.device.fingerprint);
    }
  }

  @override
  void unregisterAllDevices() {
    for (final descriptor in _registeredDevices.values) {
      _cancelPendingDiscoveryLoss(descriptor.device.fingerprint);
    }
    _registeredDevices.clear();
  }

  void _cancelPendingDiscoveryLoss(String fingerprint) {
    _pendingDiscoveryLossTimers.remove(fingerprint)?.cancel();
  }

  void _cancelAllPendingDiscoveryLosses() {
    for (final timer in _pendingDiscoveryLossTimers.values) {
      timer.cancel();
    }
    _pendingDiscoveryLossTimers.clear();
  }
}
