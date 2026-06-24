import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_app/core/services/devices/ble_provisioner.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/features/devices/models/events.dart';
import 'package:borneo_app/features/devices/providers/new_device_candidates_store.dart';
import 'package:borneo_app/features/devices/view_models/provisioning_wizard_view_model.dart';
import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel_abstractions/kernel.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:event_bus/event_bus.dart';
import 'package:esp_ble_prov_dart/esp_ble_prov_dart.dart';
import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:logger/logger.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:sembast/sembast.dart';
import 'package:lw_wot/wot.dart';

import '../mocks/gettext.dart';

class ProvisioningBleProvisioner implements IBleProvisioner {
  @override
  Future<GeneralBorneoDeviceInfo> fetchDeviceInfo({required String deviceName, CancellationToken? cancelToken}) async {
    return GeneralBorneoDeviceInfo.fromMap({
      'id': 'device-id-1',
      'compatible': 'lyfi',
      'name': 'Provisioned Device',
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

  @override
  Future<void> provisionWifi(String deviceName, String ssid, String password, {CancellationToken? cancelToken}) async {}

  @override
  Future<List<String>> scanBleDevices(String prefix, {CancellationToken? cancelToken}) async => [];

  @override
  Future<List<WiFiNetwork>> scanWifiNetworks(
    String deviceName, {
    String pop = '',
    CancellationToken? cancelToken,
  }) async => [];
}

class ProvisioningDeviceManager implements IDeviceManager {
  final DefaultEventDispatcher _events = DefaultEventDispatcher();
  final List<String> addedFingerprints = [];
  int startDiscoveryCalls = 0;
  int stopDiscoveryCalls = 0;
  bool _isDiscovering = false;

  @override
  EventDispatcher get allDeviceEvents => _events;

  @override
  bool get isInitialized => true;

  @override
  bool get isDiscoverying => _isDiscovering;

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
  IKernel get kernel => throw UnimplementedError();

  @override
  Future<DeviceEntity> addNewDevice(SupportedDeviceDescriptor discovered, {String? groupID, Transaction? tx}) async {
    addedFingerprints.add(discovered.fingerprint);
    final device = DeviceEntity(
      id: 'device-${discovered.fingerprint}',
      address: discovered.address,
      fingerprint: discovered.fingerprint,
      sceneID: 'scene-1',
      driverID: discovered.driverDescriptor.id,
      compatible: discovered.compatible,
      name: discovered.name,
      model: discovered.model,
      groupID: groupID,
    );
    _events.fire(NewDeviceEntityAddedEvent(device));
    return device;
  }

  void emitNewDeviceFound(SupportedDeviceDescriptor device) {
    _events.fire(NewDeviceFoundEvent(device));
  }

  @override
  Future<void> startDiscovery({Duration? timeout, CancellationToken? cancelToken}) async {
    startDiscoveryCalls++;
    _isDiscovering = true;
  }

  @override
  Future<void> initialize({CancellationToken? cancelToken}) async {}

  @override
  bool isBound(String deviceID) => false;

  @override
  BoundDevice getBoundDevice(String deviceID) => throw UnimplementedError();

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
  Future<DeviceEntity> getDevice(String id, {Transaction? tx}) async => throw UnimplementedError();

  @override
  Future<List<DeviceEntity>> fetchAllDevicesInScene({String? sceneID}) async => [];

  @override
  Future<void> stopDiscovery() async {
    stopDiscoveryCalls++;
    _isDiscovering = false;
  }

  @override
  WotThing getWotThing(String deviceID) => throw UnimplementedError();

  @override
  bool hasWotThing(String deviceID) => false;

  @override
  void dispose() {}
}

class SilentNotificationService implements IAppNotificationService {
  @override
  void showError(String title, {String? body}) {}

  @override
  void showInfo(String title, {String? body}) {}

  @override
  void showSuccess(String title, {String? body}) {}

  @override
  void showWarning(String title, {String? body}) {}

  @override
  void showNotificationWithAction(String title, {String? body, required Function onTapAction}) {}
}

SupportedDeviceDescriptor makeProvisionedCandidate(String fingerprint) {
  return SupportedDeviceDescriptor(
    driverDescriptor: DriverDescriptor(
      id: 'test-driver',
      name: 'Test Driver',
      heartbeatMethod: HeartbeatMethod.poll,
      discoveryMethod: const MdnsDeviceDiscoveryMethod('_test._tcp'),
      matches: (_) => null,
      factory: ({Logger? logger}) => throw UnimplementedError(),
    ),
    name: 'Provisioned Device',
    address: Uri.parse('coap://192.168.1.10:5683'),
    fingerprint: fingerprint,
    compatible: 'lyfi',
    model: 'Test Model',
    interfaceVer: 1,
    fwVer: Version.parse('1.0.0'),
    isCE: true,
  );
}

void main() {
  group('ProvisioningWizardViewModel', () {
    late ProvisioningDeviceManager deviceManager;
    late NewDeviceCandidatesStore candidatesStore;
    late ProvisioningWizardViewModel vm;

    setUp(() {
      deviceManager = ProvisioningDeviceManager();
      candidatesStore = NewDeviceCandidatesStore(deviceManager);
      vm = ProvisioningWizardViewModel(
        ProvisioningBleProvisioner(),
        deviceManager,
        candidatesStore,
        'BOPROV_TEST',
        globalEventBus: EventBus(),
        gt: FakeGettext(),
        logger: Logger(),
        notificationService: SilentNotificationService(),
        registerTimeoutSeconds: 1,
      );
      vm.selectNetwork('Test WiFi');
    });

    tearDown(() {
      vm.dispose();
      candidatesStore.dispose();
    });

    test('auto-adds immediately when target fingerprint is already in candidates store', () async {
      deviceManager.emitNewDeviceFound(makeProvisionedCandidate('fp-1'));

      await vm.startProvisioning('password');
      await Future<void>.delayed(Duration.zero);

      expect(deviceManager.startDiscoveryCalls, 1);
      expect(deviceManager.addedFingerprints, ['fp-1']);
      expect(vm.provisioningSucceeded, isTrue);
      expect(vm.step, ProvisioningWizardStep.done);
    });

    test('ignores other fingerprints and waits for matching candidate', () async {
      await vm.startProvisioning('password');
      await Future<void>.delayed(Duration.zero);

      deviceManager.emitNewDeviceFound(makeProvisionedCandidate('fp-other'));
      await Future<void>.delayed(Duration.zero);
      expect(deviceManager.addedFingerprints, isEmpty);

      deviceManager.emitNewDeviceFound(makeProvisionedCandidate('fp-1'));
      await Future<void>.delayed(Duration.zero);

      expect(deviceManager.addedFingerprints, ['fp-1']);
      expect(vm.provisioningSucceeded, isTrue);
    });

    test('restarts discovery for registration when a previous discovery session is active', () async {
      deviceManager.startDiscoveryCalls = 0;
      deviceManager.stopDiscoveryCalls = 0;
      await deviceManager.startDiscovery();

      await vm.startProvisioning('password');

      expect(deviceManager.stopDiscoveryCalls, 1);
      expect(deviceManager.startDiscoveryCalls, 2);
    });

    test('stops registration discovery on dispose', () async {
      await vm.startProvisioning('password');
      expect(deviceManager.isDiscoverying, isTrue);

      vm.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(deviceManager.stopDiscoveryCalls, 1);
      expect(deviceManager.isDiscoverying, isFalse);
    });
  });
}
