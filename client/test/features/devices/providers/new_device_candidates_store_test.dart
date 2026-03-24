import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/features/devices/models/events.dart';
import 'package:borneo_app/features/devices/providers/new_device_candidates_store.dart';
import 'package:borneo_kernel_abstractions/kernel.dart';
import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:logger/logger.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../../mocks/core/services/device_manager.dart';

class CandidatesStoreDeviceManager extends StubDeviceManager {
  final DefaultEventDispatcher _dispatcher = DefaultEventDispatcher();

  @override
  EventDispatcher get allDeviceEvents => _dispatcher;

  void emitNewDeviceFound(SupportedDeviceDescriptor device) {
    _dispatcher.fire(NewDeviceFoundEvent(device));
  }

  void emitNewDeviceAdded(DeviceEntity device) {
    _dispatcher.fire(NewDeviceEntityAddedEvent(device));
  }
}

SupportedDeviceDescriptor makeCandidate({String fingerprint = 'fp-1', String host = '192.168.1.10'}) {
  return SupportedDeviceDescriptor(
    driverDescriptor: DriverDescriptor(
      id: 'test-driver',
      name: 'Test Driver',
      heartbeatMethod: HeartbeatMethod.poll,
      discoveryMethod: const MdnsDeviceDiscoveryMethod('_test._tcp'),
      matches: (_) => null,
      factory: ({Logger? logger}) => throw UnimplementedError(),
    ),
    name: 'Candidate Device',
    address: Uri.parse('coap://$host:5683'),
    fingerprint: fingerprint,
    compatible: 'lyfi',
    model: 'test-model',
    interfaceVer: 1,
    fwVer: Version.parse('1.0.0'),
    isCE: true,
  );
}

DeviceEntity makeDeviceEntity({String fingerprint = 'fp-1'}) {
  return DeviceEntity(
    id: 'device-$fingerprint',
    address: Uri.parse('coap://192.168.1.10:5683'),
    fingerprint: fingerprint,
    sceneID: 'scene-1',
    driverID: 'test-driver',
    compatible: 'lyfi',
    name: 'Saved Device',
    model: 'test-model',
  );
}

void main() {
  group('NewDeviceCandidatesStore', () {
    late CandidatesStoreDeviceManager deviceManager;
    late NewDeviceCandidatesStore store;

    setUp(() {
      deviceManager = CandidatesStoreDeviceManager();
      store = NewDeviceCandidatesStore(deviceManager);
    });

    tearDown(() {
      store.dispose();
    });

    test('deduplicates candidates by fingerprint', () async {
      deviceManager.emitNewDeviceFound(makeCandidate());
      deviceManager.emitNewDeviceFound(makeCandidate(host: '192.168.1.20'));
      await Future<void>.delayed(Duration.zero);

      expect(store.count, 1);
      expect(store.byFingerprint('fp-1')?.address.host, '192.168.1.20');
    });

    test('removes candidate after device is added', () async {
      deviceManager.emitNewDeviceFound(makeCandidate());
      await Future<void>.delayed(Duration.zero);

      deviceManager.emitNewDeviceAdded(makeDeviceEntity());
      await Future<void>.delayed(Duration.zero);

      expect(store.count, 0);
      expect(store.byFingerprint('fp-1'), isNull);
    });
  });
}
