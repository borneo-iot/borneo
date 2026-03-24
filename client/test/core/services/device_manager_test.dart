import 'dart:collection';

import 'package:borneo_app/core/models/scene_entity.dart';
import 'package:borneo_app/core/services/devices/device_manager_impl.dart';
import 'package:borneo_app/core/services/devices/device_module_registry.dart';
import 'package:borneo_app/core/services/group_manager.dart';
import 'package:borneo_app/core/services/scene_manager.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/features/devices/models/device_module_metadata.dart';
import 'package:borneo_common/exceptions.dart';
import 'package:borneo_kernel_abstractions/kernel.dart';
import 'package:event_bus/event_bus.dart';
// hide EventDispatcher because flutter_test also exports a symbol with
// the same name; we use the one from kernel_abstractions instead.
import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:logger/logger.dart';
import 'package:sembast/sembast_memory.dart';
import '../../mocks/mocks.dart';

void main() {
  group('DeviceManagerImpl Tests', () {
    late DeviceManagerImpl deviceManager;
    late Database testDb;
    late TestKernel testKernel;
    late TestEventBus testGlobalBus;
    late TestSceneManager testSceneManager;
    late TestGroupManager testGroupManager;
    late TestDeviceModuleRegistry testDeviceModuleRegistry;
    late TestLogger testLogger;

    // Test data
    late DeviceEntity testDevice;

    setUp(() async {
      // Create in-memory database for testing
      testDb = await databaseFactoryMemory.openDatabase('test.db');

      // Create test doubles
      testKernel = TestKernel();
      testGlobalBus = TestEventBus();
      testSceneManager = TestSceneManager();
      testGroupManager = TestGroupManager();
      testDeviceModuleRegistry = TestDeviceModuleRegistry();
      testLogger = TestLogger();

      // Setup test scene
      final testSceneEntity = SceneEntity(
        id: 'test-scene-id',
        name: 'Test Scene',
        isCurrent: true,
        lastAccessTime: DateTime.now(),
      );
      testSceneManager.currentScene = testSceneEntity;

      // Setup test device
      testDevice = DeviceEntity(
        id: 'test-device-id',
        name: 'Test Device',
        sceneID: 'test-scene-id',
        driverID: 'test-driver',
        fingerprint: 'test-fingerprint',
        address: Uri.parse('coap://192.168.1.100:5683'),
        compatible: 'test-compatible',
        model: 'test-model',
      );

      // Create device manager instance
      deviceManager = DeviceManagerImpl(
        testDb,
        testKernel,
        testGlobalBus,
        testSceneManager,
        testGroupManager,
        testDeviceModuleRegistry,
        gettext: FakeGettext(),
        logger: testLogger,
      );
    });

    tearDown(() async {
      deviceManager.dispose();
      await testDb.close();
    });

    group('Initialization', () {
      test('should initialize successfully', () async {
        // Act
        await deviceManager.initialize();

        // Assert
        expect(deviceManager.isInitialized, isTrue);
        expect(testKernel.startCalled, isTrue);
      });

      test('should throw assertion error if already initialized', () async {
        // Arrange
        await deviceManager.initialize();

        // Act & Assert
        expect(() => deviceManager.initialize(), throwsA(isA<AssertionError>()));
      });
    });

    group('Device Database Operations', () {
      setUp(() async {
        await deviceManager.initialize();
      });

      test('should add device to database', () async {
        // Arrange
        final store = stringMapStoreFactory.store('devices');

        // Act
        await store.record(testDevice.id).put(testDb, testDevice.toMap());
        final result = await deviceManager.getDevice(testDevice.id);

        // Assert
        expect(result.id, equals(testDevice.id));
        expect(result.name, equals(testDevice.name));
        expect(result.sceneID, equals(testDevice.sceneID));
        expect(result.isDemo, isFalse);
      });

      test('should throw KeyNotFoundException for missing device', () async {
        await expectLater(deviceManager.getDevice('missing-device-id'), throwsA(isA<KeyNotFoundException>()));
      });

      test('should update device name', () async {
        // Arrange
        final store = stringMapStoreFactory.store('devices');
        await store.record(testDevice.id).put(testDb, testDevice.toMap());

        // Act
        await deviceManager.update(testDevice.id, name: 'Updated Name');

        // Assert
        final updatedDevice = await deviceManager.getDevice(testDevice.id);
        expect(updatedDevice.name, equals('Updated Name'));
      });

      test('should update device address and refresh kernel registration', () async {
        // Arrange
        final store = stringMapStoreFactory.store('devices');
        await store.record(testDevice.id).put(testDb, testDevice.toMap());
        await deviceManager.bind(testDevice);

        final newAddress = Uri.parse('coap://192.168.1.200:5683');

        // Act
        await deviceManager.updateAddress(testDevice.id, newAddress);

        // Assert
        final updatedDevice = await deviceManager.getDevice(testDevice.id);
        expect(updatedDevice.address, equals(newAddress));
        expect(testKernel.unbindCalled, isTrue);
        expect(testKernel.lastUnboundDeviceId, equals(testDevice.id));
        expect(testKernel.unregisterDeviceCallCount, equals(1));
        expect(testKernel.lastUnregisteredDeviceId, equals(testDevice.id));
        expect(testKernel.registerDeviceCallCount, greaterThanOrEqualTo(1));
        expect(testKernel.lastRegisteredDeviceId, equals(testDevice.id));
        expect(testKernel.lastRegisteredDescriptor?.device.address, equals(newAddress));
        expect(testKernel.tryBindCalled, isTrue);
      });

      test('should update address from known device discovery update event', () async {
        // Arrange
        final store = stringMapStoreFactory.store('devices');
        await store.record(testDevice.id).put(testDb, testDevice.toMap());

        final matched = TestSupportedDeviceDescriptor(testDevice.fingerprint);
        final event = KnownDeviceDiscoveryUpdatedEvent(
          testDevice,
          SupportedDeviceDescriptor(
            driverDescriptor: matched.driverDescriptor,
            name: matched.name,
            address: Uri.parse('coap://192.168.1.210:5683'),
            fingerprint: testDevice.fingerprint,
            compatible: matched.compatible,
            model: matched.model,
            fwVer: matched.fwVer,
            isCE: matched.isCE,
            interfaceVer: matched.interfaceVer,
            vendor: matched.vendor,
            serno: matched.serno,
          ),
        );

        // Act
        testKernel.events.fire(event);
        await Future.delayed(Duration(milliseconds: 10));

        // Assert
        final updatedDevice = await deviceManager.getDevice(testDevice.id);
        expect(updatedDevice.address, equals(Uri.parse('coap://192.168.1.210:5683')));
      });

      test('should delete device from database', () async {
        // Arrange
        final store = stringMapStoreFactory.store('devices');
        await store.record(testDevice.id).put(testDb, testDevice.toMap());

        // Act
        await deviceManager.delete(testDevice.id);

        // Assert
        final record = await store.record(testDevice.id).get(testDb);
        expect(record, isNull);
      });

      test('should fetch devices in current scene only', () async {
        // Arrange
        final store = stringMapStoreFactory.store('devices');
        await store.record(testDevice.id).put(testDb, testDevice.toMap());

        final otherSceneDevice = DeviceEntity(
          id: 'other-device',
          name: 'Other Device',
          sceneID: 'other-scene',
          driverID: 'test-driver',
          fingerprint: 'other-fingerprint',
          address: Uri.parse('coap://192.168.1.102:5683'),
          compatible: 'test-compatible',
          model: 'test-model',
        );
        await store.record(otherSceneDevice.id).put(testDb, otherSceneDevice.toMap());

        // Act
        final result = await deviceManager.fetchAllDevicesInScene();

        // Assert
        expect(result.length, equals(1));
        expect(result.first.id, equals(testDevice.id));
        expect(result.first.sceneID, equals('test-scene-id'));
      });

      test('should check if device is new', () async {
        // Arrange
        final descriptor = TestSupportedDeviceDescriptor('unique-fingerprint');

        // Act
        final result = await deviceManager.isNewDevice(descriptor);

        // Assert
        expect(result, isTrue);
      });

      test('should find device by fingerprint', () async {
        // Arrange
        final store = stringMapStoreFactory.store('devices');
        await store.record(testDevice.id).put(testDb, testDevice.toMap());

        // Act
        final result = await deviceManager.singleOrDefaultByFingerprint(testDevice.fingerprint);

        // Assert
        expect(result, isNotNull);
        expect(result!.id, equals(testDevice.id));
        expect(result.fingerprint, equals(testDevice.fingerprint));
      });
    });

    group('Device Binding Operations', () {
      setUp(() async {
        await deviceManager.initialize();
      });

      test('should bind device', () async {
        // Act
        await deviceManager.bind(testDevice);

        // Assert
        expect(testKernel.bindCalled, isTrue);
        expect(testKernel.lastBoundDeviceId, equals(testDevice.id));
      });

      test('should try bind device', () async {
        // Arrange
        testKernel.tryBindResult = true;

        // Act
        final result = await deviceManager.tryBind(testDevice);

        // Assert
        expect(result, isTrue);
        expect(testKernel.tryBindCalled, isTrue);
      });

      test('should unbind device', () async {
        // Act
        await deviceManager.unbind(testDevice.id);

        // Assert
        expect(testKernel.unbindCalled, isTrue);
        expect(testKernel.lastUnboundDeviceId, equals(testDevice.id));
      });

      test('should check if device is bound', () {
        // Arrange
        testKernel.boundDeviceIds.add(testDevice.id);

        // Act
        final result = deviceManager.isBound(testDevice.id);

        // Assert
        expect(result, isTrue);
      });
    });

    group('Device Discovery', () {
      setUp(() async {
        await deviceManager.initialize();
      });

      test('should start discovery', () async {
        // Act
        await deviceManager.startDiscovery(timeout: const Duration(seconds: 30));

        // Assert
        expect(testKernel.startScanningCalled, isTrue);
        expect(deviceManager.isDiscoverying, isTrue);
      });

      test('should stop discovery', () async {
        // Arrange
        await deviceManager.startDiscovery();

        // Act
        await deviceManager.stopDiscovery();

        // Assert
        expect(testKernel.stopScanningCalled, isTrue);
        expect(deviceManager.isDiscoverying, isFalse);
      });
    });

    group('Error Handling', () {
      setUp(() async {
        await deviceManager.initialize();
      });

      test('should throw KeyNotFoundException when updating non-existent device', () async {
        // Act & Assert
        expect(() => deviceManager.update('non-existent-id', name: 'New Name'), throwsA(isA<KeyNotFoundException>()));
      });

      test('should throw KeyNotFoundException when moving to non-existent group', () async {
        // Arrange
        final store = stringMapStoreFactory.store('devices');
        await store.record(testDevice.id).put(testDb, testDevice.toMap());

        // Act & Assert
        expect(
          () => deviceManager.moveToGroup(testDevice.id, 'non-existent-group'),
          throwsA(isA<KeyNotFoundException>()),
        );
      });
    });

    group('Disposal', () {
      test('should dispose resources properly', () {
        // Act & Assert - should not throw any exceptions
        deviceManager.dispose();

        // Verify that dispose can be called multiple times safely
        deviceManager.dispose();
      });
    });

    group('Heartbeat batch signaling', () {
      test('reloadAllDevices sends enter/exit batch signals', () async {
        // Arrange: kernel starts in default state
        expect(testKernel.batchEntered, isFalse);
        expect(testKernel.batchExited, isFalse);

        // Act
        await deviceManager.reloadAllDevices();

        // Assert
        expect(testKernel.batchEntered, isTrue, reason: 'batch should be entered before heavy operations');
        expect(testKernel.batchExited, isTrue, reason: 'batch should be exited after operations complete');
      });
    });
  });
}

// the shared mocks imported transitively via mocks.dart

// remaining per-test helpers that aren't reused elsewhere

// deprecated test helper; replaced by EventDispatcher
class TestEventDispatcher extends DefaultEventDispatcher {}

class TestEventBus extends EventBus {}

class TestSceneManager implements ISceneManager {
  late SceneEntity currentScene;

  @override
  SceneEntity get current => currentScene;

  Logger? get logger => null;

  // Simplified - only implement what we need for testing
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class TestGroupManager implements IGroupManager {
  // Simplified - only implement what we need for testing
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class TestDeviceModuleRegistry implements IDeviceModuleRegistry {
  @override
  UnmodifiableMapView<String, DeviceModuleMetadata> get metaModules => UnmodifiableMapView({});
}
