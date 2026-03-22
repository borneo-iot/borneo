import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/features/devices/models/events.dart';
import 'package:borneo_app/features/devices/view_models/base_device_view_model.dart';
import 'package:borneo_common/io/net/rssi.dart';
import 'package:borneo_kernel_abstractions/kernel.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';
import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:lw_wot/wot.dart';
import 'package:sembast/sembast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BaseDeviceViewModel', () {
    late _FakeDeviceManager deviceManager;
    late DeviceEntity device;
    late _TestDeviceViewModel viewModel;

    setUp(() async {
      device = DeviceEntity(
        id: 'device-1',
        name: 'Device 1',
        sceneID: 'scene-1',
        driverID: 'driver-1',
        fingerprint: 'fp-1',
        address: Uri.parse('coap://127.0.0.1:5683'),
        compatible: 'test-compatible',
        model: 'test-model',
      );
      deviceManager = _FakeDeviceManager(device);
      viewModel = _TestDeviceViewModel(
        deviceManager: deviceManager,
        globalEventBus: EventBus(),
        wotThing: WotThing(id: device.id, title: device.name, type: ['test-device'], description: ''),
        gt: _DummyGettextLocalizations(),
      );
      await viewModel.initialize();
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('becomes unavailable and ignores later entity updates after deletion', () async {
      expect(viewModel.isAvailable, isTrue);
      expect(viewModel.name, equals('Device 1'));

      deviceManager.events.fire(DeviceEntityDeletedEvent(device.id));
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.isAvailable, isFalse);

      final updatedDevice = DeviceEntity(
        id: device.id,
        name: 'Renamed Device',
        sceneID: device.sceneID,
        driverID: device.driverID,
        fingerprint: device.fingerprint,
        address: device.address,
        compatible: device.compatible,
        model: device.model,
      );
      deviceManager.events.fire(DeviceEntityUpdatedEvent(device, updatedDevice));
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.name, equals('Device 1'));
    });
  });
}

class _TestDeviceViewModel extends BaseDeviceViewModel {
  _TestDeviceViewModel({
    required super.deviceManager,
    required super.globalEventBus,
    required super.wotThing,
    required super.gt,
  });

  @override
  Future<void> onInitialize() async {}

  @override
  RssiLevel? get rssiLevel => RssiLevel.medium;
}

class _FakeDeviceManager implements IDeviceManager {
  final EventDispatcher events = DefaultEventDispatcher();
  final DeviceEntity device;

  _FakeDeviceManager(this.device);

  @override
  EventDispatcher get allDeviceEvents => events;

  @override
  Iterable<WotThing> get allWotThings => const [];

  @override
  Iterable<BoundDevice> get boundDevices => const [];

  @override
  Iterable<String> get deviceIDsWithWotThings => const [];

  @override
  bool get isDiscoverying => false;

  @override
  bool get isInitialized => true;

  @override
  IKernel get kernel => throw UnimplementedError();

  @override
  int get wotThingCount => 0;

  @override
  Iterable<WotThing> get wotThingsInCurrentScene => const [];

  @override
  Future<DeviceEntity> addNewDevice(SupportedDeviceDescriptor discovered, {String? groupID, Transaction? tx}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> bind(DeviceEntity device) async {}

  @override
  void dispose() {}

  @override
  Future<void> delete(String id, {Transaction? tx, CancellationToken? cancelToken}) async {}

  @override
  Future<List<DeviceEntity>> fetchAllDevicesInScene({String? sceneID}) async => [device];

  @override
  Future<DeviceEntity> getDevice(String id, {Transaction? tx}) async => device;

  @override
  BoundDevice getBoundDevice(String deviceID) => throw StateError('not bound');

  @override
  Iterable<BoundDevice> getBoundDevicesInCurrentScene() => const [];

  @override
  WotThing getWotThing(String deviceID) => throw UnimplementedError();

  @override
  bool hasWotThing(String deviceID) => false;

  @override
  Future<void> initialize({CancellationToken? cancelToken}) async {}

  @override
  Future<bool> isNewDevice(SupportedDeviceDescriptor matched, {Transaction? tx}) async => false;

  @override
  bool isBound(String deviceID) => false;

  @override
  Future<void> moveToGroup(String id, String newGroupID) async {}

  @override
  Future<void> reloadAllDevices({CancellationToken? cancelToken}) async {}

  @override
  Future<DeviceEntity?> singleOrDefaultByFingerprint(String fingerprint, {Transaction? tx}) async => null;

  @override
  Future<void> startDiscovery({Duration? timeout, CancellationToken? cancelToken}) async {}

  @override
  Future<void> stopDiscovery() async {}

  @override
  Future<bool> tryBind(DeviceEntity device) async => false;

  @override
  Future<void> unbind(String deviceID) async {}

  @override
  Future<void> update(String id, {Transaction? tx, String? name, String? groupID}) async {}

  @override
  Future<void> updateAddress(String id, Uri address, {CancellationToken? cancelToken}) async {}
}

class _DummyGettextLocalizations implements GettextLocalizations {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
