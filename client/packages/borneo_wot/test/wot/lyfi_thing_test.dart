import 'package:borneo_wot/borneo/lyfi/wot_thing.dart';
import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/api.dart';
import 'package:borneo_kernel_abstractions/models/bound_device.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('LyfiThing', () {
    late MockDevice mockDevice;
    late MockLogger mockLogger;
    late MockKernel mockKernel;

    setUp(() {
      mockDevice = MockDevice('test-device', 'http://192.168.1.100');
      mockLogger = MockLogger();
      mockKernel = MockKernel();
    });

    group('Constructor', () {
      test('should create LyfiThing with required parameters', () {
        final lyfiThing = LyfiThing(
          kernel: mockKernel,
          deviceId: mockDevice.id,
          title: 'Test Lyfi',
          logger: mockLogger,
        );

        expect(lyfiThing.id, equals('test-device'));
        expect(lyfiThing.title, equals('Test Lyfi'));
        expect(lyfiThing.type, contains('OnOffSwitch'));
        expect(lyfiThing.type, contains('Light'));
        expect(lyfiThing.isOffline, isTrue);
      });
    });

    group('Guard Methods', () {
      test('canWriteProperty should return false by default', () {
        final lyfiThing = LyfiThing(kernel: mockKernel, deviceId: mockDevice.id, title: 'Test Lyfi');

        expect(lyfiThing.canWriteProperty('on'), isFalse);
      });

      test('canWriteProperty should use canWrite function when provided', () {
        final lyfiThing = LyfiThing(kernel: mockKernel, deviceId: mockDevice.id, title: 'Test Lyfi');

        expect(lyfiThing.canWriteProperty('on'), isFalse);
      });

      test('getWriteGuardError should return appropriate error message', () {
        final lyfiThing = LyfiThing(kernel: mockKernel, deviceId: mockDevice.id, title: 'Test Lyfi');

        expect(lyfiThing.getWriteGuardError('on'), equals('Device is offline or unbound.'));
      });

      test('canPerformAction should return false by default', () {
        final lyfiThing = LyfiThing(kernel: mockKernel, deviceId: mockDevice.id, title: 'Test Lyfi');

        expect(lyfiThing.canPerformAction('test-action'), isFalse);
      });

      test('canPerformAction should use canWrite function when provided', () {
        final lyfiThing = LyfiThing(kernel: mockKernel, deviceId: mockDevice.id, title: 'Test Lyfi');

        expect(lyfiThing.canPerformAction('test-action'), isFalse);
      });

      test('getActionGuardError should return appropriate error message', () {
        final lyfiThing = LyfiThing(kernel: mockKernel, deviceId: mockDevice.id, title: 'Test Lyfi');

        expect(lyfiThing.getActionGuardError('test-action'), equals('Device is offline or unbound.'));
      });
    });

    group('initialize', () {
      test('should initialize device and create properties', () async {
        final lyfiThing = LyfiThing(
          kernel: mockKernel,
          deviceId: mockDevice.id,
          title: 'Test Lyfi',
          logger: mockLogger,
        );

        await lyfiThing.sync();

        // Verify properties are created
        expect(lyfiThing.hasProperty('on'), isTrue);
        expect(lyfiThing.hasProperty('state'), isTrue);
        expect(lyfiThing.hasProperty('mode'), isTrue);
        expect(lyfiThing.hasProperty('color'), isTrue);
        expect(lyfiThing.hasProperty('schedule'), isTrue);
      });

      test('should skip optional API reads when /.well-known/core omits those resources', () async {
        await mockDevice.setDriverData(
          TestSupportedResourceDriverData(mockDevice, {
            BorneoPaths.deviceInfo.path,
            BorneoPaths.power.path,
            BorneoPaths.powerBehavior.path,
            BorneoPaths.status.path,
            LyfiPaths.status.path,
          }),
        );
        final driver = MockLyfiDriver(
          supportedResources: {
            BorneoPaths.deviceInfo.path,
            BorneoPaths.power.path,
            BorneoPaths.powerBehavior.path,
            BorneoPaths.status.path,
            LyfiPaths.status.path,
          },
        );
        mockKernel.setBoundDevice(BoundDevice('mock-driver', mockDevice, driver));

        final lyfiThing = LyfiThing(
          kernel: mockKernel,
          deviceId: mockDevice.id,
          title: 'Test Lyfi',
          logger: mockLogger,
        );

        await lyfiThing.sync();

        expect(driver.scheduleReads, equals(0));
        expect(driver.lyfiInfoReads, equals(0));
        expect(driver.moonConfigReads, equals(0));
      });

      test('should skip optional API reads when capability cache is unavailable', () async {
        final driver = MockLyfiDriver();
        mockKernel.setBoundDevice(BoundDevice('mock-driver', mockDevice, driver));

        final lyfiThing = LyfiThing(
          kernel: mockKernel,
          deviceId: mockDevice.id,
          title: 'Test Lyfi',
          logger: mockLogger,
        );

        await lyfiThing.sync();

        expect(driver.scheduleReads, equals(0));
        expect(driver.lyfiInfoReads, equals(0));
        expect(driver.moonConfigReads, equals(0));
      });
    });
  });
}
