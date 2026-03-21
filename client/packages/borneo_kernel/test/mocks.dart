import 'dart:async';
import 'dart:collection';

import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:borneo_kernel_abstractions/models/io.dart';
import 'package:borneo_kernel_abstractions/kernel.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:event_bus/event_bus.dart';
import 'package:logger/logger.dart' as logger_pkg;
import 'package:pub_semver/pub_semver.dart';

class MockLogger extends logger_pkg.Logger {
  final List<String> logs = [];

  MockLogger() : super();

  @override
  void log(logger_pkg.Level level, dynamic message, {Object? error, StackTrace? stackTrace, DateTime? time}) {
    // Do nothing
  }
}

class MockDriver implements Driver {
  final String id;
  @override
  final logger_pkg.Logger? logger;
  bool _isDisposed = false;
  final Map<String, bool> _probeResults = {};
  final Map<String, bool> _heartbeatResults = {};
  final List<String> _probedDevices = [];
  final List<String> _removedDevices = [];
  final List<String> _heartbeatDevices = [];
  Duration probeDelay = Duration.zero;
  int _activeProbeCount = 0;
  int _maxObservedConcurrentProbes = 0;

  MockDriver(this.id, {this.logger});

  void setProbeResult(String deviceId, bool result) {
    _probeResults[deviceId] = result;
  }

  void setHeartbeatResult(String deviceId, bool result) {
    _heartbeatResults[deviceId] = result;
  }

  List<String> get probedDevices => List.unmodifiable(_probedDevices);
  List<String> get removedDevices => List.unmodifiable(_removedDevices);
  List<String> get heartbeatDevices => List.unmodifiable(_heartbeatDevices);
  int get maxObservedConcurrentProbes => _maxObservedConcurrentProbes;

  @override
  Future<bool> probe(Device dev, {CancellationToken? cancelToken}) async {
    if (_isDisposed) throw StateError('Driver is disposed');
    _probedDevices.add(dev.id);
    _activeProbeCount++;
    if (_activeProbeCount > _maxObservedConcurrentProbes) {
      _maxObservedConcurrentProbes = _activeProbeCount;
    }
    try {
      if (probeDelay > Duration.zero) {
        await Future.delayed(probeDelay);
      }
      return _probeResults[dev.id] ?? true;
    } finally {
      _activeProbeCount--;
    }
  }

  @override
  Future<bool> remove(Device dev, {CancellationToken? cancelToken}) async {
    if (_isDisposed) throw StateError('Driver is disposed');
    _removedDevices.add(dev.id);
    return true;
  }

  @override
  Future<bool> heartbeat(Device dev, {CancellationToken? cancelToken}) async {
    if (_isDisposed) throw StateError('Driver is disposed');
    _heartbeatDevices.add(dev.id);
    return _heartbeatResults[dev.id] ?? true;
  }

  @override
  void dispose() {
    _isDisposed = true;
  }

  bool get isDisposed => _isDisposed;

  @override
  Future<T> withBusyCheck<T>(Device dev, Future<T> Function() action, {CancellationToken? cancelToken}) {
    throw UnimplementedError();
  }

  @override
  Future<T> withQueue<T>(
    Device dev,
    Future<T> Function() action, {
    CancellationToken? cancelToken,
    IOCommandPriority? priority,
  }) {
    throw UnimplementedError();
  }
}

class MockDriverRegistry implements IDriverRegistry {
  final Map<String, DriverDescriptor> _drivers = {};

  void addDriver(String id, DriverDescriptor descriptor) {
    _drivers[id] = descriptor;
  }

  @override
  UnmodifiableMapView<String, DriverDescriptor> get metaDrivers => UnmodifiableMapView(_drivers);
}

class TestDevice extends Device {
  DriverData? _driverData;

  TestDevice(String id, String address) : super(id: id, address: Uri.parse(address), fingerprint: 'test-$id');

  @override
  DriverData get driverData => _driverData ?? TestDriverData(this);

  @override
  Future<void> setDriverData(DriverData driverData, {CancellationToken? cancelToken}) async {
    _driverData = driverData;
  }
}

class TestDriverData extends DriverData {
  TestDriverData(super.device);
}

class MockMdnsDiscovery implements IMdnsDiscovery {
  final String _serviceType;
  bool _isDisposed = false;
  bool _isStopped = false;

  MockMdnsDiscovery(this._serviceType);

  @override
  String get serviceType => _serviceType;

  @override
  Future<void> stop({CancellationToken? cancelToken}) async {
    _isStopped = true;
  }

  @override
  void dispose() {
    _isDisposed = true;
  }

  bool get isDisposed => _isDisposed;
  bool get isStopped => _isStopped;
}

class MockMdnsProvider implements IMdnsProvider {
  final Map<String, MockMdnsDiscovery> _discoveries = {};
  final List<String> _startedServices = [];

  List<String> get startedServices => List.unmodifiable(_startedServices);
  Map<String, MockMdnsDiscovery> get discoveries => Map.unmodifiable(_discoveries);

  @override
  Future<IMdnsDiscovery> startDiscovery(String serviceType, EventBus eventBus, {CancellationToken? cancelToken}) async {
    _startedServices.add(serviceType);
    final discovery = MockMdnsDiscovery(serviceType);
    _discoveries[serviceType] = discovery;
    return discovery;
  }
}

class MockNetworkMonitor implements INetworkMonitor {
  final StreamController<NetworkSnapshot> _controller = StreamController.broadcast();
  NetworkSnapshot _currentSnapshot;

  MockNetworkMonitor({NetworkSnapshot? initialSnapshot})
    : _currentSnapshot = initialSnapshot ?? const NetworkSnapshot(localDiscoveryAvailable: true, fingerprint: 'wifi');

  @override
  Stream<NetworkSnapshot> get onNetworkChanged => _controller.stream;

  @override
  Future<NetworkSnapshot> getCurrentSnapshot() async => _currentSnapshot;

  void emit(NetworkSnapshot snapshot) {
    _currentSnapshot = snapshot;
    _controller.add(snapshot);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}

class TestMdnsDiscoveredDevice extends MdnsDiscoveredDevice {
  TestMdnsDiscoveredDevice({required super.host, super.port, super.name, super.txt, super.serviceType});
}

SupportedDeviceDescriptor createTestDeviceDescriptor(String id, String address, DriverDescriptor driverDescriptor) {
  final uri = address.startsWith('http') ? Uri.parse(address) : Uri.parse('http://$address');
  return SupportedDeviceDescriptor(
    driverDescriptor: driverDescriptor,
    name: 'Test Device $id',
    address: uri,
    fingerprint: 'test-$id',
    compatible: 'test',
    model: 'TestModel',
    fwVer: Version.parse('0.4.9'),
    isCE: true,
  );
}

DriverDescriptor createTestDriverDescriptor(String id, MockDriver driver) {
  late final DriverDescriptor descriptor;
  descriptor = DriverDescriptor(
    id: id,
    name: 'Test Driver $id',
    factory: ({logger_pkg.Logger? logger}) => driver,
    matches: (discovered) => createTestDeviceDescriptor(id, discovered.host, descriptor),
    heartbeatMethod: HeartbeatMethod.poll,
    discoveryMethod: const MdnsDeviceDiscoveryMethod('_test._tcp'),
  );
  return descriptor;
}

class MockDevice extends Device {
  MockDevice(String id, String address) : super(id: id, address: Uri.parse(address), fingerprint: 'test-$id');

  @override
  DriverData get driverData => TestDriverData(this);

  @override
  Future<void> setDriverData(DriverData driverData, {CancellationToken? cancelToken}) async {
    // Mock implementation
  }
}

class MockDeviceEventBus implements DeviceEventBus {
  final EventBus _eventBus = EventBus();

  @override
  void fire(event) {
    _eventBus.fire(event);
  }

  @override
  Stream<T> on<T>() {
    return _eventBus.on<T>();
  }

  @override
  void destroy() {
    _eventBus.destroy();
  }

  @override
  StreamController get streamController => _eventBus.streamController;
}

class MockBorneoDeviceApi implements IBorneoDeviceApi {
  @override
  Future<GeneralBorneoDeviceInfo> getGeneralDeviceInfo(Device device, {CancellationToken? cancelToken}) async {
    return GeneralBorneoDeviceInfo(
      id: 'mock-id',
      name: 'Mock Device',
      compatible: 'test',
      serno: '123456',
      transportChannel: TransportChannel.wifi,
      hasBT: false,
      hasWifi: true,
      hasMqtt: false,
      productMode: ProductMode.standalone,
      manufName: 'Mock Manufacturer',
      modelName: 'Mock Model',
      hwVer: Version.parse('1.0.0'),
      fwVer: Version.parse('1.0.0'),
      isCE: true,
      pid: 'bst/xiaoc3',
    );
  }

  @override
  Future<GeneralBorneoDeviceStatus> getGeneralDeviceStatus(Device device, {CancellationToken? cancelToken}) async {
    return GeneralBorneoDeviceStatus(
      power: true,
      timestamp: DateTime.now(),
      bootDuration: Duration(seconds: 30),
      timezone: 'UTC',
    );
  }

  @override
  Future<PowerBehavior> getPowerBehavior(Device device, {CancellationToken? cancelToken}) async {
    return PowerBehavior.lastPowerState;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class MockLyfiDeviceApi implements ILyfiDeviceApi {
  @override
  Future<LyfiDeviceStatus> getLyfiStatus(Device device, {CancellationToken? cancelToken}) async {
    return LyfiDeviceStatus(
      state: LyfiState.normal,
      mode: LyfiMode.manual,
      unscheduled: true,
      temporaryRemaining: Duration.zero,
      output: [0, 0, 0, 0],
      currentColor: [0, 0, 0, 0],
      manualColor: [0, 0, 0, 0],
      sunColor: [0, 0, 0, 0],
      temperature: 25,
      powerCurrent: 0.0,
    );
  }

  @override
  Future<ScheduleTable> getSchedule(Device device, {CancellationToken? cancelToken}) async {
    return [];
  }

  @override
  Future<AcclimationSettings> getAcclimation(Device device, {CancellationToken? cancelToken}) async {
    return AcclimationSettings(enabled: false, startTimestamp: DateTime.now(), startPercent: 0, days: 0);
  }

  @override
  Future<GeoLocation?> getLocation(Device device, {CancellationToken? cancelToken}) async {
    return null;
  }

  @override
  Future<LedCorrectionMethod> getCorrectionMethod(Device device, {CancellationToken? cancelToken}) async {
    return LedCorrectionMethod.linear;
  }

  @override
  Future<bool> getTimeZoneEnabled(Device device, {CancellationToken? cancelToken}) async {
    return false;
  }

  @override
  Future<int> getTimeZoneOffset(Device device, {CancellationToken? cancelToken}) async {
    return 0;
  }

  @override
  Future<bool> getCloudEnabled(Device device, {CancellationToken? cancelToken}) async {
    return false;
  }

  @override
  Future<int> getKeepTemp(Device device, {CancellationToken? cancelToken}) async {
    return 25;
  }

  @override
  Future<FanMode> getFanMode(Device device, {CancellationToken? cancelToken}) async {
    return FanMode.pid;
  }

  @override
  Future<int> getFanManualPower(Device device, {CancellationToken? cancelToken}) async {
    return 50;
  }

  @override
  Future<Duration> getTemporaryDuration(Device device, {CancellationToken? cancelToken}) async {
    return Duration(hours: 1);
  }

  @override
  Future<List<ScheduledInstant>> getSunSchedule(Device device, {CancellationToken? cancelToken}) async {
    return [];
  }

  @override
  Future<MoonConfig> getMoonConfig(Device device, {CancellationToken? cancelToken}) async {
    return MoonConfig(enabled: false, color: [0, 0, 0, 0]);
  }

  @override
  Future<MoonStatus> getMoonStatus(Device device, {CancellationToken? cancelToken}) async {
    return MoonStatus(phaseAngle: 0.0, illumination: 0.0);
  }

  @override
  Future<ScheduleTable> getMoonSchedule(Device device, {CancellationToken? cancelToken}) async {
    return [];
  }

  @override
  Future<LyfiDeviceInfo> getLyfiInfo(Device device, {CancellationToken? cancelToken}) async {
    return LyfiDeviceInfo(
      channelCountMax: 4,
      channelCount: 4,
      channels: [
        LyfiChannelInfo(name: 'Red', color: 'red', wavelength: 650, factor: 1.0),
        LyfiChannelInfo(name: 'Green', color: 'green', wavelength: 520, factor: 1.0),
        LyfiChannelInfo(name: 'Blue', color: 'blue', wavelength: 450, factor: 1.0),
        LyfiChannelInfo(name: 'White', color: 'white', wavelength: 4000, factor: 1.0),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class MockKernel implements IKernel {
  final EventDispatcher _events = DefaultEventDispatcher();
  final Map<String, BoundDevice> _boundDevices = {};

  void setBoundDevice(BoundDevice bound) {
    _boundDevices[bound.device.id] = bound;
  }

  void clearBoundDevices() {
    _boundDevices.clear();
  }

  @override
  Iterable<BoundDevice> get boundDevices => _boundDevices.values;

  @override
  bool get isInitialized => true;

  @override
  EventDispatcher get events => _events;

  @override
  Iterable<Driver> get activatedDrivers => [];

  @override
  bool get isBusy => false;

  @override
  bool get isScanning => false;

  @override
  Future<void> start() async {}

  @override
  bool isBound(String deviceID) => _boundDevices.containsKey(deviceID);

  @override
  BoundDevice getBoundDevice(String deviceID) => _boundDevices[deviceID] ?? (throw UnimplementedError());

  @override
  Future<bool> tryBind(Device device, String driverID, {CancellationToken? cancelToken}) async => true;

  @override
  Future<void> bind(Device device, String driverID, {CancellationToken? cancelToken}) async {}

  @override
  Future<void> unbind(String deviceID, {CancellationToken? cancelToken}) async {}

  @override
  Future<void> unbindAll({CancellationToken? cancelToken}) async {}

  @override
  Future<void> startDevicesScanning({Duration? timeout, CancellationToken? cancelToken}) async {}

  @override
  void suspendHeartbeat() {}

  @override
  void resumeHeartbeat() {}

  // new batch notification APIs
  bool batchEntered = false;
  bool batchExited = false;

  @override
  void enterHeartbeatBatch() {
    batchEntered = true;
  }

  @override
  void exitHeartbeatBatch() {
    batchExited = true;
  }

  @override
  HeartbeatState? getHeartbeatState(String deviceID) => null;

  @override
  Future<void> stopDevicesScanning() async {}

  @override
  void registerDevice(BoundDeviceDescriptor device) {}

  @override
  void registerDevices(Iterable<BoundDeviceDescriptor> devices) {}

  @override
  void unregisterDevice(String deviceID) {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

// ---------- mocks for new kernel interfaces ----------

class MockDiscoveryManager implements DiscoveryManager {
  final _controller = StreamController<DiscoveredDevice>.broadcast();
  final _lostController = StreamController<DiscoveredDevice>.broadcast();
  bool _active = false;
  bool disposed = false;

  @override
  Stream<DiscoveredDevice> get onDeviceFound => _controller.stream;

  @override
  Stream<DiscoveredDevice> get onDeviceLost => _lostController.stream;

  @override
  bool get isActive => _active;

  @override
  Future<void> start({Duration? timeout, CancellationToken? cancelToken}) async {
    _active = true;
    if (timeout != null) {
      Future.delayed(timeout, () => stop());
    }
  }

  @override
  Future<void> stop({CancellationToken? cancelToken}) async {
    _active = false;
  }

  @override
  void registerBus(DeviceBus bus) {}

  @override
  void unregisterBus(String busId) {}

  void addDevice(DiscoveredDevice device) {
    _controller.add(device);
  }

  void emitLost(DiscoveredDevice device) {
    _lostController.add(device);
  }

  @override
  void dispose() {
    disposed = true;
    _controller.close();
    _lostController.close();
  }
}

class MockBindingEngine implements BindingEngine {
  bool _busy = false;
  final Map<String, bool> _probes = {};
  final Map<String, BoundDevice> _bound = {};

  bool bindCalled = false;
  bool unbindCalled = false;

  @override
  bool get isBusy => _busy;

  @override
  Iterable<BoundDevice> get boundDevices => _bound.values;

  @override
  BoundDevice? getBoundDevice(String deviceID) => _bound[deviceID];

  @override
  Future<void> bind(Device device, String driverID, {CancellationToken? cancelToken}) async {
    bindCalled = true;
    final ok = await tryBind(device, driverID, cancelToken: cancelToken);
    if (!ok) throw Exception('bind failed');
    _bound[device.id] = BoundDevice(driverID, device, MockDriver('mock'));
  }

  @override
  Future<bool> tryBind(Device device, String driverID, {CancellationToken? cancelToken}) async {
    _busy = true;
    await Future.delayed(Duration(milliseconds: 10));
    _busy = false;
    return _probes[device.id] ?? true;
  }

  @override
  Future<void> unbind(String deviceID, {CancellationToken? cancelToken}) async {
    unbindCalled = true;
    _busy = true;
    await Future.delayed(Duration(milliseconds: 5));
    _busy = false;
    _bound.remove(deviceID);
  }

  @override
  Future<void> unbindAll({CancellationToken? cancelToken}) async {
    final ids = List<String>.from(_bound.keys);
    for (final id in ids) {
      await unbind(id, cancelToken: cancelToken);
    }
  }

  @override
  void dispose() {}

  void setProbeResult(String deviceID, bool result) {
    _probes[deviceID] = result;
  }
}

class MockHeartbeatService implements HeartbeatService {
  bool _active = false;
  bool _suspended = false;
  bool _inBatch = false;
  final _failController = StreamController<Device>.broadcast();
  final _tickController = StreamController<void>.broadcast();
  final _batchController = StreamController<bool>.broadcast();

  // for verification
  final List<BoundDevice> registered = [];
  final List<String> unregistered = [];
  final List<String> communicationEvents = [];

  @override
  Stream<Device> get onFailure => _failController.stream;

  @override
  Stream<void> get onTick => _tickController.stream;

  @override
  Stream<bool> get batchMode => _batchController.stream;

  @override
  bool get isActive => _active && !_suspended && !_inBatch;

  @override
  Future<void> start() async {
    _active = true;
  }

  @override
  Future<void> stop() async {
    _active = false;
    _suspended = false;
    registered.clear();
    unregistered.clear();
    communicationEvents.clear();
    _tickController.close();
  }

  @override
  void suspend() {
    _suspended = true;
  }

  @override
  void resume() {
    _suspended = false;
  }

  @override
  void enterBatch() {
    _inBatch = true;
    _batchController.add(true);
  }

  @override
  void exitBatch() {
    _inBatch = false;
    _batchController.add(false);
  }

  @override
  void registerDevice(BoundDevice bound, HeartbeatMethod method) {
    registered.add(bound);
  }

  @override
  void unregisterDevice(String deviceID) {
    unregistered.add(deviceID);
  }

  @override
  void onDeviceCommunication(String deviceID) {
    communicationEvents.add(deviceID);
  }

  @override
  HeartbeatState? getState(String deviceID) => null;
}

class MockDriverFactory implements DriverFactory {
  final Map<String, Driver> _map = {};

  @override
  Driver create(String driverID, {logger_pkg.Logger? logger}) {
    return _map[driverID]!;
  }

  void add(String id, Driver driver) {
    _map[id] = driver;
  }
}

class MockEventDispatcher implements EventDispatcher {
  final _ctrl = StreamController.broadcast();

  @override
  Stream<T> on<T>() => _ctrl.stream.where((e) => e is T).cast<T>();

  @override
  void fire(Object event) => _ctrl.add(event);

  @override
  void destroy() => _ctrl.close();
}

class MockDeviceBus implements DeviceBus {
  @override
  String get id => 'mock';

  final _found = StreamController<DiscoveredDevice>.broadcast();
  final _lost = StreamController<DiscoveredDevice>.broadcast();

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Stream<DiscoveredDevice> get onDeviceFound => _found.stream;

  @override
  Stream<DiscoveredDevice> get onDeviceLost => _lost.stream;

  @override
  Future<void> disconnect(String deviceId) async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
