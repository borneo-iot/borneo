import 'package:borneo_kernel_abstractions/kernel.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:logger/logger.dart';
import 'package:pub_semver/pub_semver.dart';

// NOTE: previous imports for device_entity, device_module_metadata,
// borneo_common, and lw_wot were unused and removed to clean warnings.

/// Test double implementations extracted from ``device_manager_test.dart``.

class TestKernel implements IKernel {
  bool _isScanning = false;
  bool _isInitialized = false;
  final List<String> boundDeviceIds = [];
  final List<BoundDevice> _boundDevices = [];
  final EventDispatcher _events = DefaultEventDispatcher();

  // tracks whether heartbeat batch signals were invoked
  bool heartbeatSuspended = false; // kept for compatibility
  bool heartbeatResumed = false; // kept for compatibility
  bool batchEntered = false;
  bool batchExited = false;

  // Test tracking
  bool startCalled = false;
  bool bindCalled = false;
  bool tryBindCalled = false;
  bool unbindCalled = false;
  bool startScanningCalled = false;
  bool stopScanningCalled = false;
  int registerDeviceCallCount = 0;
  int unregisterDeviceCallCount = 0;

  String? lastBoundDeviceId;
  String? lastUnboundDeviceId;
  String? lastRegisteredDeviceId;
  String? lastUnregisteredDeviceId;
  BoundDeviceDescriptor? lastRegisteredDescriptor;
  bool tryBindResult = true;

  @override
  bool get isScanning => _isScanning;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Iterable<Driver> get activatedDrivers => [];

  @override
  Iterable<BoundDevice> get boundDevices => _boundDevices;

  @override
  EventDispatcher get events => _events;

  @override
  Future<void> start() async {
    startCalled = true;
    _isInitialized = true;
  }

  @override
  void suspendHeartbeat() {
    heartbeatSuspended = true;
  }

  @override
  void resumeHeartbeat() {
    heartbeatResumed = true;
  }

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
  bool isBound(String deviceID) => boundDeviceIds.contains(deviceID);

  @override
  BoundDevice getBoundDevice(String deviceID) {
    return _boundDevices.firstWhere((bound) => bound.device.id == deviceID);
  }

  @override
  Future<bool> tryBind(dynamic device, String driverID, {CancellationToken? cancelToken}) async {
    tryBindCalled = true;
    lastBoundDeviceId = device.id;
    if (tryBindResult) {
      boundDeviceIds.add(device.id);
      final testDriver = TestDriver();
      _boundDevices.removeWhere((bound) => bound.device.id == device.id);
      _boundDevices.add(BoundDevice(driverID, device as Device, testDriver));
    }
    return tryBindResult;
  }

  @override
  Future<void> bind(dynamic device, String driverID, {CancellationToken? cancelToken}) async {
    bindCalled = true;
    lastBoundDeviceId = device.id;
    boundDeviceIds.add(device.id);
    final testDriver = TestDriver();
    _boundDevices.removeWhere((bound) => bound.device.id == device.id);
    _boundDevices.add(BoundDevice(driverID, device as Device, testDriver));
  }

  @override
  Future<void> unbind(String deviceID, {CancellationToken? cancelToken}) async {
    unbindCalled = true;
    lastUnboundDeviceId = deviceID;
    boundDeviceIds.remove(deviceID);
    _boundDevices.removeWhere((d) => d.device.id == deviceID);
  }

  @override
  Future<void> unbindAll({CancellationToken? cancelToken}) async {
    boundDeviceIds.clear();
    _boundDevices.clear();
  }

  @override
  void registerDevice(dynamic descriptor) {
    registerDeviceCallCount++;
    final typed = descriptor as BoundDeviceDescriptor;
    lastRegisteredDescriptor = typed;
    lastRegisteredDeviceId = typed.device.id;
  }

  @override
  void registerDevices(Iterable<dynamic> descriptors) {
    for (final descriptor in descriptors) {
      registerDevice(descriptor);
    }
  }

  @override
  void unregisterDevice(String deviceID) {
    unregisterDeviceCallCount++;
    lastUnregisteredDeviceId = deviceID;
  }

  @override
  void unregisterAllDevices() {}

  @override
  Future<void> startDevicesScanning({Duration? timeout, CancellationToken? cancelToken}) async {
    startScanningCalled = true;
    _isScanning = true;
  }

  @override
  Future<void> stopDevicesScanning() async {
    stopScanningCalled = true;
    _isScanning = false;
  }

  @override
  void dispose() {}

  @override
  bool get isBusy => false;
}

class TestBoundDevice {
  final Device device;

  TestBoundDevice(this.device);
}

class TestDevice extends Device {
  late DriverData _driverData;

  TestDevice(String id) : super(id: id, fingerprint: 'test-fingerprint', address: Uri.parse('coap://localhost:5683')) {
    _driverData = TestDriverData(this);
  }

  @override
  DriverData get driverData => _driverData;

  @override
  Future<void> setDriverData(DriverData data, {CancellationToken? cancelToken}) async {
    _driverData = data;
  }
}

class TestDriverData extends DriverData {
  TestDriverData(super.device);

  @override
  void dispose() {}
}

class TestDriver implements Driver {
  // The Driver interface has evolved; these members are provided for
  // compatibility with older tests. They may not be part of the current
  // interface, so we omit `@override` to avoid analyzer warnings.

  bool get isConnected => false;

  Future<void> connect() async {}

  Future<void> disconnect() async {}

  Stream<dynamic> get notifications => const Stream.empty();

  bool get isBusy => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Simple descriptor implementation used by device manager tests.
// Simple descriptor implementation used by device manager tests.
// extends rather than implements to avoid pulling in every getter.
class TestSupportedDeviceDescriptor extends SupportedDeviceDescriptor {
  TestSupportedDeviceDescriptor(String fingerprint)
    : super(
        driverDescriptor: DriverDescriptor(
          id: 'test',
          name: 'test',
          heartbeatMethod: HeartbeatMethod.poll,
          discoveryMethod: const MdnsDeviceDiscoveryMethod('_test._tcp'),
          matches: (_) => null,
          factory: ({Logger? logger}) => TestDriver(),
        ),
        name: 'test',
        address: Uri.parse('coap://localhost'),
        fingerprint: fingerprint,
        compatible: 'compatible',
        model: 'model',
        interfaceVer: 1,
        fwVer: Version(0, 0, 1),
        isCE: false,
      );
}
