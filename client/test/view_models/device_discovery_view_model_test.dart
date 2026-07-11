import 'dart:collection';

// hide EventDispatcher from flutter_test to avoid collision with our
// abstraction type which is exported transitively by kernel.dart.
import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:flutter/services.dart';
import 'package:event_bus/event_bus.dart';
import 'package:logger/logger.dart';
import 'package:sembast/sembast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pub_semver/pub_semver.dart';

import 'package:borneo_app/features/devices/models/events.dart';
import 'package:borneo_app/features/devices/providers/new_device_candidates_store.dart';
import 'package:borneo_app/features/devices/view_models/device_discovery_view_model.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/core/services/devices/ble_provisioner.dart';
import 'package:borneo_app/core/services/devices/device_module_registry.dart';
import 'package:borneo_app/core/services/platform_service.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/features/devices/models/device_module_metadata.dart';
import 'package:lw_wot/wot.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:esp_ble_prov_dart/esp_ble_prov_dart.dart';
import 'package:borneo_kernel_abstractions/kernel.dart';
import '../mocks/mocks.dart';

// Minimal implementations / fakes for the interfaces used by the view model.

// A tiny fake that lets tests pretend they are running on a particular
// platform without depending on the real `dart:io` APIs.
class FakePlatformService implements PlatformService {
  @override
  bool isWeb;

  @override
  bool isAndroid;

  @override
  bool isIOS;

  @override
  bool isWindows;

  @override
  bool isMacOS;

  @override
  bool isLinux;

  FakePlatformService({
    this.isWeb = false,
    this.isAndroid = false,
    this.isIOS = false,
    this.isWindows = false,
    this.isMacOS = false,
    this.isLinux = false,
  });

  @override
  bool get isMobile => isAndroid || isIOS;

  @override
  bool get isDesktop => isWindows || isMacOS || isLinux;
}

class FakeDeviceManager implements IDeviceManager {
  final DefaultEventDispatcher _events = DefaultEventDispatcher();

  @override
  bool get isDiscoverying => false;

  @override
  EventDispatcher get allDeviceEvents => _events;

  @override
  Iterable<BoundDevice> get boundDevices => const [];

  @override
  Iterable<WotThing> get allWotThings => const [];

  @override
  Iterable<WotThing> get wotThingsInCurrentScene => const [];

  @override
  Iterable<String> get deviceIDsWithWotThings => const [];

  @override
  int get wotThingCount => 0;

  @override
  Future<void> initialize({CancellationToken? cancelToken}) async {}

  @override
  bool isBound(String deviceID) => false;

  @override
  BoundDevice getBoundDevice(String deviceID) {
    throw UnimplementedError();
  }

  @override
  Iterable<BoundDevice> getBoundDevicesInCurrentScene() => const [];

  @override
  Future<void> reloadAllDevices({CancellationToken? cancelToken}) async {}

  @override
  Future<bool> tryBind(DeviceEntity device) async => false;

  @override
  Future<void> bind(DeviceEntity device) async {}

  @override
  Future<void> unbind(String deviceID) async {}

  @override
  Future<void> delete(String id, {Transaction? tx, CancellationToken? cancelToken}) async {}

  @override
  Future<void> update(String id, {Transaction? tx, String? name, String? groupID}) async {}

  @override
  Future<void> updateAddress(String id, Uri address, {CancellationToken? cancelToken}) async {}

  @override
  Future<void> moveToGroup(String id, String newGroupID) async {}

  @override
  Future<bool> isNewDevice(SupportedDeviceDescriptor matched, {Transaction? tx}) async => false;

  @override
  Future<DeviceEntity?> singleOrDefaultByFingerprint(String fingerprint, {Transaction? tx}) async => null;

  @override
  Future<DeviceEntity> addNewDevice(SupportedDeviceDescriptor discovered, {String? groupID, Transaction? tx}) async {
    throw UnimplementedError();
  }

  @override
  Future<DeviceEntity> getDevice(String id, {Transaction? tx}) async {
    throw UnimplementedError();
  }

  @override
  Future<List<DeviceEntity>> fetchAllDevicesInScene({String? sceneID}) async => [];

  @override
  Future<void> startDiscovery({Duration? timeout, CancellationToken? cancelToken}) async {}

  @override
  Future<void> stopDiscovery() async {}

  @override
  WotThing getWotThing(String deviceID) {
    throw UnimplementedError();
  }

  @override
  bool hasWotThing(String deviceID) => false;

  // IDisposable implementation
  @override
  bool get isInitialized => true;

  @override
  IKernel get kernel => throw UnimplementedError();

  @override
  void dispose() {}

  void emitNewDeviceFound(SupportedDeviceDescriptor device) {
    _events.fire(NewDeviceFoundEvent(device));
  }
}

class FakeBleProvisioner implements IBleProvisioner {
  bool scanCalled = false;
  bool fetchCalled = false;
  Future<List<String>> Function(String prefix, {CancellationToken? cancelToken})? scanImpl;
  Future<GeneralBorneoDeviceInfo> Function({required String deviceName, CancellationToken? cancelToken})? fetchImpl;

  @override
  Future<List<String>> scanBleDevices(String prefix, {CancellationToken? cancelToken}) async {
    scanCalled = true;
    if (scanImpl != null) {
      return await scanImpl!(prefix, cancelToken: cancelToken);
    }
    return [];
  }

  @override
  Future<void> closeDeviceSession(String deviceName) async {}

  @override
  Future<List<WiFiNetwork>> scanWifiNetworks(
    String deviceName, {
    String pop = '',
    CancellationToken? cancelToken,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> provisionWifi(
    String deviceName,
    String ssid,
    String password, {
    WiFiNetwork? network,
    CancellationToken? cancelToken,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<GeneralBorneoDeviceInfo> fetchDeviceInfo({required String deviceName, CancellationToken? cancelToken}) async {
    fetchCalled = true;
    if (fetchImpl != null) {
      return await fetchImpl!(deviceName: deviceName, cancelToken: cancelToken);
    }
    throw UnimplementedError();
  }
}

class FakeDeviceModuleRegistry extends IDeviceModuleRegistry {
  @override
  UnmodifiableMapView<String, DeviceModuleMetadata> get metaModules => UnmodifiableMapView({});
}

GeneralBorneoDeviceInfo makeDeviceInfo({String name = 'Resolved Device'}) {
  return GeneralBorneoDeviceInfo.fromMap({
    'id': 'device-id-1',
    'compatible': 'lyfi',
    'name': name,
    'serno': 'fp-1',
    'pid': 'pid-1',
    'productMode': 0,
    'transport': 0,
    'hasBT': true,
    'hasWifi': true,
    'hasMqtt': false,
    'vendor': 'BST',
    'model': 'Test Model',
    'hwVer': '1.0.0',
    'fwVer': '1.0.0',
    'isCE': true,
  });
}

SupportedDeviceDescriptor makeSupportedDevice({String fingerprint = 'fp-1', String name = 'Candidate'}) {
  return SupportedDeviceDescriptor(
    driverDescriptor: DriverDescriptor(
      id: 'test-driver',
      name: 'Test Driver',
      heartbeatMethod: HeartbeatMethod.poll,
      discoveryMethod: const MdnsDeviceDiscoveryMethod('_test._tcp'),
      matches: (_) => null,
      factory: ({Logger? logger}) => throw UnimplementedError(),
    ),
    name: name,
    address: Uri.parse('coap://192.168.1.10:5683'),
    fingerprint: fingerprint,
    compatible: 'lyfi',
    model: 'test-model',
    interfaceVer: 1,
    fwVer: Version.parse('1.0.0'),
    isCE: true,
  );
}

void main() {
  group('DeviceDiscoveryViewModel permissions', () {
    late DeviceDiscoveryViewModel vm;
    late FakeBleProvisioner bleProv;
    late FakeDeviceManager deviceManager;
    late NewDeviceCandidatesStore candidatesStore;

    // helper to construct a VM configured for mobile/desktop and an optional
    // permission stub.
    DeviceDiscoveryViewModel makeVm({
      required bool mobile,
      bool windows = false,
      Future<bool> Function()? permissions,
      FakeBleProvisioner? ble,
    }) {
      bleProv = ble ?? FakeBleProvisioner();
      deviceManager = FakeDeviceManager();
      candidatesStore = NewDeviceCandidatesStore(deviceManager);
      return DeviceDiscoveryViewModel(
        Logger(),
        deviceManager,
        candidatesStore,
        bleProv,
        FakeDeviceModuleRegistry(),
        FakePlatformService(isAndroid: mobile, isIOS: false, isWindows: windows, isLinux: !mobile && !windows),
        globalEventBus: EventBus(),
        gt: FakeGettext(),
        logger: Logger(),
        requestBlePermissions: permissions ?? () async => false,
      );
    }

    test('blePermissionList returns Android permissions on Android', () {
      vm = makeVm(mobile: true);
      final perms = vm.blePermissionList();
      expect(perms, containsAll([Permission.locationWhenInUse, Permission.bluetoothScan, Permission.bluetoothConnect]));
      expect(perms.length, 3);
    });

    test('blePermissionList returns iOS permissions on iOS', () {
      // manual iOS platform service, bypassing makeVm helper
      bleProv = FakeBleProvisioner();
      deviceManager = FakeDeviceManager();
      candidatesStore = NewDeviceCandidatesStore(deviceManager);
      vm = DeviceDiscoveryViewModel(
        Logger(),
        deviceManager,
        candidatesStore,
        bleProv,
        FakeDeviceModuleRegistry(),
        FakePlatformService(isIOS: true),
        globalEventBus: EventBus(),
        gt: FakeGettext(),
        logger: Logger(),
        requestBlePermissions: () async => true,
      );
      final perms = vm.blePermissionList();
      expect(perms, containsAll([Permission.bluetooth, Permission.locationWhenInUse]));
      expect(perms.length, 2);
    });

    test('startDiscovery does not call BLE scan when permissions denied', () async {
      vm = makeVm(mobile: true, permissions: () async => false);
      expect(bleProv.scanCalled, isFalse);
      await vm.startDiscovery();
      expect(bleProv.scanCalled, isFalse);
      expect(vm.scanError.value, 'Bluetooth permissions are required to discover devices.');
    });

    test('startDiscovery calls BLE scan when permissions granted', () async {
      vm = makeVm(mobile: true, permissions: () async => true);
      await vm.startDiscovery();
      // scanning happens asynchronously; give it a chance
      await Future.delayed(Duration.zero);
      expect(bleProv.scanCalled, isTrue);
    });

    test('startDiscovery handles platform exception permission denial', () async {
      final errorProv = FakeBleProvisioner();
      errorProv.scanImpl = (String prefix, {CancellationToken? cancelToken}) async {
        throw PlatformException(code: 'PERMISSION_DENIED', message: 'nope');
      };
      vm = makeVm(mobile: true, permissions: () async => true, ble: errorProv);
      await vm.startDiscovery();
      await Future.delayed(Duration.zero);
      expect(vm.scanError.value, 'Bluetooth permissions are required to discover devices.');
    });

    test('desktop platforms run BLE scan without mobile permissions', () async {
      vm = makeVm(mobile: false, windows: false);
      expect(vm.blePermissionList(), isEmpty);

      await vm.startDiscovery();
      await Future.delayed(Duration.zero);

      expect(bleProv.scanCalled, isTrue);
    });

    test('startDiscovery shows BLE device even when device info fetch fails', () async {
      final ble = FakeBleProvisioner()
        ..scanImpl = (String prefix, {CancellationToken? cancelToken}) async => ['BOPROV_63541C'];

      vm = makeVm(mobile: true, permissions: () async => true, ble: ble);
      await vm.startDiscovery();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ble.fetchCalled, isTrue);
      expect(vm.discoverableDevices.value.map((device) => device.id), contains('BOPROV_63541C'));
      expect(vm.discoverableDevices.value.single.name, 'BOPROV_63541C');
      expect(vm.scanError.value, isNull);
    });

    test('startDiscovery updates BLE device display name when device info fetch succeeds', () async {
      final ble = FakeBleProvisioner()
        ..scanImpl = (String prefix, {CancellationToken? cancelToken}) async {
          return ['BOPROV_63541C'];
        }
        ..fetchImpl = ({required String deviceName, CancellationToken? cancelToken}) async =>
            makeDeviceInfo(name: 'Borneo Controller');

      vm = makeVm(mobile: true, permissions: () async => true, ble: ble);
      await vm.startDiscovery();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(vm.discoverableDevices.value.single.id, 'BOPROV_63541C');
      expect(vm.discoverableDevices.value.single.name, 'Borneo Controller');
    });

    test('startDiscovery keeps global new-device candidates visible', () async {
      vm = makeVm(mobile: false, windows: false, permissions: () async => true);
      deviceManager.emitNewDeviceFound(makeSupportedDevice());

      await vm.startDiscovery();

      expect(vm.discoverableDevices.value.map((device) => device.id), contains('fp-1'));
    });
  });
}
