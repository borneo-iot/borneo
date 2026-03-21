import 'dart:async';

// imports of interfaces pulled indirectly via mocks
import 'package:borneo_kernel_abstractions/models/discovered_device.dart';
import 'package:borneo_kernel_abstractions/events.dart';
import 'package:borneo_kernel_abstractions/device_bus.dart';
import 'package:borneo_kernel_abstractions/event_dispatcher.dart';
import 'package:borneo_kernel/discovery_manager_impl.dart';
import 'package:borneo_kernel/binding_engine_impl.dart';
import 'package:test/test.dart';
import 'mocks.dart';

// helper dummy bus for testing
class DummyBus implements DeviceBus {
  @override
  String get id => 'dummy';

  final _f = StreamController<DiscoveredDevice>.broadcast();
  final _l = StreamController<DiscoveredDevice>.broadcast();

  @override
  Stream<DiscoveredDevice> get onDeviceFound => _f.stream;

  @override
  Stream<DiscoveredDevice> get onDeviceLost => _l.stream;

  bool started = false;
  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> stop() async {
    started = false;
  }

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> disconnect(String deviceId) async {}

  // helpers for tests
  void emitFound(DiscoveredDevice d) => _f.add(d);
  void emitLost(DiscoveredDevice d) => _l.add(d);
}

void main() {
  group('Interface mocks', () {
    test('DiscoveryManager mock emits devices', () async {
      final mgr = MockDiscoveryManager();
      expect(mgr.isActive, isFalse);
      mgr.start();
      expect(mgr.isActive, isTrue);

      final events = <DiscoveredDevice>[];
      final sub = mgr.onDeviceFound.listen(events.add);

      // use the concrete helper defined in mocks
      final dev = TestMdnsDiscoveredDevice(host: 'a', port: 80);
      mgr.addDevice(dev);
      await Future.delayed(Duration.zero);
      expect(events, contains(dev));
      sub.cancel();
    });

    test('BindingEngine busy flag and probe results', () async {
      final eng = MockBindingEngine();
      expect(eng.isBusy, isFalse);
      final device = TestDevice('x', 'http://x');
      eng.setProbeResult('x', false);
      final result = await eng.tryBind(device, 'foo');
      expect(result, isFalse);
    });

    test('DefaultBindingEngine binds/unbinds and exposes state', () async {
      final logger = MockLogger();
      final registry = MockDriverRegistry();
      // use the new default dispatcher rather than the deprecated global
      final events = DefaultEventDispatcher();
      final drv = MockDriver('drv');
      registry.addDriver('drv', createTestDriverDescriptor('drv', drv));

      final eng = DefaultBindingEngine(logger, registry, events);
      expect(eng.boundDevices, isEmpty);
      final device = TestDevice('a', 'http://a');

      final received = <Object>[];
      final sub = events.on().listen((e) => received.add(e));

      await eng.bind(device, 'drv');
      await Future.delayed(Duration.zero);
      expect(eng.boundDevices.map((b) => b.device.id), contains('a'));
      expect(received, contains(isA<DeviceBoundEvent>()));

      await eng.unbind('a');
      await Future.delayed(Duration.zero);
      expect(eng.boundDevices, isEmpty);
      expect(received, contains(isA<DeviceRemovedEvent>()));

      await sub.cancel();
    });

    test('DefaultBindingEngine limits concurrent probes across devices', () async {
      final logger = MockLogger();
      final registry = MockDriverRegistry();
      final events = DefaultEventDispatcher();
      final drv = MockDriver('drv')..probeDelay = Duration(milliseconds: 40);
      registry.addDriver('drv', createTestDriverDescriptor('drv', drv));

      final eng = DefaultBindingEngine(logger, registry, events, maxConcurrentProbes: 2);
      final devices = [
        TestDevice('a', 'http://a'),
        TestDevice('b', 'http://b'),
        TestDevice('c', 'http://c'),
        TestDevice('d', 'http://d'),
      ];

      await Future.wait(devices.map((device) => eng.bind(device, 'drv')));

      expect(eng.boundDevices.length, equals(4));
      expect(drv.maxObservedConcurrentProbes, lessThanOrEqualTo(2));
    });

    test('DefaultBindingEngine serializes work for the same device', () async {
      final logger = MockLogger();
      final registry = MockDriverRegistry();
      final events = DefaultEventDispatcher();
      final drv = MockDriver('drv')..probeDelay = Duration(milliseconds: 40);
      registry.addDriver('drv', createTestDriverDescriptor('drv', drv));

      final eng = DefaultBindingEngine(logger, registry, events, maxConcurrentProbes: 4);
      final device = TestDevice('a', 'http://a');

      final results = await Future.wait([eng.tryBind(device, 'drv'), eng.tryBind(device, 'drv')]);

      expect(results, everyElement(isTrue));
      expect(eng.boundDevices.length, equals(1));
      expect(drv.probedDevices.where((id) => id == 'a').length, equals(1));
    });

    test('DriverData dispose cancels queued work and rejects new submissions', () async {
      final device = TestDevice('a', 'http://a');
      final data = TestDriverData(device);
      final started = Completer<void>();
      final release = Completer<void>();

      final first = data.queue.submit(() async {
        started.complete();
        await release.future;
        return 1;
      });

      await started.future;
      data.dispose();

      expect(() => data.queue.submit(() async => 2), throwsStateError);

      release.complete();
      await expectLater(first, throwsA(isA<Exception>()));
    });

    test('HeartbeatService start/batch/suspend/resume', () async {
      final svc = MockHeartbeatService();
      expect(svc.isActive, isFalse);
      await svc.start();
      expect(svc.isActive, isTrue);
      svc.suspend();
      expect(svc.isActive, isFalse);
      svc.resume();
      expect(svc.isActive, isTrue);

      // batch signals should be plumbed through
      final recorded = <bool>[];
      final sub = svc.batchMode.listen(recorded.add);
      svc.enterBatch();
      svc.exitBatch();
      await Future.delayed(Duration.zero);
      expect(recorded, [true, false]);
      await sub.cancel();
    });

    test('DriverFactory returns provided driver', () {
      final fact = MockDriverFactory();
      final drv = MockDriver('d');
      fact.add('d', drv);
      expect(fact.create('d'), equals(drv));
    });

    test('EventDispatcher forwards and filters types', () async {
      final disp = MockEventDispatcher();
      final list = <int>[];
      disp.on<int>().listen(list.add);
      disp.fire(1);
      disp.fire('no');
      await Future.delayed(Duration.zero);
      expect(list, [1]);
    });

    test('DefaultDiscoveryManager integrates with mdns provider', () async {
      final mgr = DefaultDiscoveryManager(
        MockLogger(),
        MockDriverRegistry(),
        DefaultEventDispatcher(),
        mdnsProvider: MockMdnsProvider(),
      );
      expect(mgr.isActive, isFalse);
      await mgr.start();
      expect(mgr.isActive, isTrue);
      await mgr.stop();
    });

    test('DiscoveryManager forwards events from registered bus', () async {
      final mgr = DefaultDiscoveryManager(MockLogger(), MockDriverRegistry(), DefaultEventDispatcher());
      // simple bus that emits one found & one lost
      final bus = DummyBus();
      mgr.registerBus(bus);

      await mgr.start();
      expect(bus.started, isTrue);

      final found = <DiscoveredDevice>[];
      final lost = <DiscoveredDevice>[];
      mgr.onDeviceFound.listen(found.add);
      mgr.onDeviceLost.listen(lost.add);

      final dev = TestMdnsDiscoveredDevice(host: 'h', port: 1);
      bus.emitFound(dev);
      await Future.delayed(Duration.zero);
      expect(found, contains(dev));

      bus.emitLost(dev);
      await Future.delayed(Duration.zero);
      expect(lost, contains(dev));
    });

    test('DeviceBus stub provides streams', () async {
      final bus = MockDeviceBus();
      expect(bus.id, 'mock');
      final f = bus.onDeviceFound.listen((_) {});
      final l = bus.onDeviceLost.listen((_) {});
      await bus.start();
      await bus.connect('any');
      await bus.disconnect('any');
      await bus.stop();
      await f.cancel();
      await l.cancel();
    });
  });
}
