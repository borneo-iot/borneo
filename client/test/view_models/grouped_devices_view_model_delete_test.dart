import 'dart:collection';

import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/features/devices/models/device_group_entity.dart';
import 'package:borneo_app/features/devices/models/events.dart';
import 'package:borneo_app/features/devices/models/device_module_metadata.dart';
import 'package:borneo_app/features/devices/view_models/grouped_devices_view_model.dart';
import 'package:borneo_app/devices/view_models/abstract_device_summary_view_model.dart';
import 'package:borneo_app/core/services/devices/device_module_registry.dart';
import 'package:borneo_app/core/services/scene_manager.dart';
import 'package:borneo_app/core/models/scene_entity.dart';
import 'package:borneo_kernel_abstractions/models/driver_descriptor.dart';
import 'package:borneo_kernel_abstractions/models/heartbeat_method.dart';
import 'package:borneo_app/core/services/group_manager.dart';
import 'package:borneo_app/core/services/clock.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/widgets.dart';
import 'package:borneo_app/features/devices/view_models/base_device_view_model.dart';
import 'package:lw_wot/wot.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';
import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:borneo_kernel_abstractions/event_dispatcher.dart';
import 'package:logger/logger.dart';

import '../mocks/gettext.dart';

class _FakeSceneManager implements ISceneManager {
  @override
  bool get isInitialized => true;

  @override
  SceneEntity get current => SceneEntity.newDefault();

  @override
  Future<SceneEntity> changeCurrent(String newSceneID) async => current;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDeviceManager implements IDeviceManager {
  final DefaultEventDispatcher events = DefaultEventDispatcher();
  final List<DeviceEntity> _devices;

  _FakeDeviceManager(this._devices);

  @override
  EventDispatcher get allDeviceEvents => events;

  @override
  Future<void> delete(String id, {tx, cancelToken}) async {
    // remove from internal list and fire deleted event
    _devices.removeWhere((d) => d.id == id);
    events.fire(DeviceEntityDeletedEvent(id));
  }

  @override
  Future<List<DeviceEntity>> fetchAllDevicesInScene({String? sceneID}) async => List.from(_devices);

  // Unused methods in this test
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeGroupManager implements IGroupManager {
  final List<DeviceGroupEntity> _groups;
  _FakeGroupManager(this._groups);
  @override
  Future<List<DeviceGroupEntity>> fetchAllGroupsInCurrentScene({tx}) async => List.from(_groups);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeModule implements DeviceModuleMetadata {
  @override
  final String id;
  @override
  final String name;
  @override
  final DriverDescriptor driverDescriptor;

  _FakeModule(this.id)
    : name = id,
      driverDescriptor = DriverDescriptor(
        id: id,
        name: id,
        heartbeatMethod: HeartbeatMethod.poll,
        discoveryMethod: const MdnsDeviceDiscoveryMethod(''),
        matches: (_) => null,
        factory: ({Logger? logger}) => throw UnimplementedError(),
      );

  @override
  Widget Function(BuildContext context) get detailsViewBuilder =>
      (_) => const SizedBox.shrink();

  @override
  BaseDeviceViewModel Function(BuildContext context, String deviceID) get detailsViewModelBuilder =>
      (_, _) => throw UnimplementedError();

  @override
  Widget Function(BuildContext context, double iconSize, bool isOnline) get deviceIconBuilder =>
      (_, _, _) => const SizedBox.shrink();

  @override
  Widget Function(BuildContext context, double iconSize) get primaryStateIconBuilder =>
      (_, _) => const SizedBox.shrink();

  @override
  List<Widget> Function(BuildContext, AbstractDeviceSummaryViewModel) get secondaryStatesBuilder =>
      (_, _) => [];

  @override
  AbstractDeviceSummaryViewModel Function(DeviceEntity, IDeviceManager, EventBus, GettextLocalizations)
  get createSummaryVM =>
      (d, m, ev, gt) => _SimpleSummaryVM(d, m, ev, gt: gt);

  @override
  Future<WotThing> Function(DeviceEntity, IDeviceManager, {Logger? logger, CancellationToken? cancelToken})
  get createWotThing =>
      (_, _, {logger, cancelToken}) async => throw UnimplementedError();

  @override
  Widget Function(BuildContext context, AbstractDeviceSummaryViewModel vm)? get summaryContentBuilder => null;
}

class _SimpleSummaryVM extends AbstractDeviceSummaryViewModel {
  _SimpleSummaryVM(super.device, super.manager, super.globalEventBus, {required super.gt});

  Future<void> onInitialize() async {}
}

class _FakeModuleRegistry implements IDeviceModuleRegistry {
  final Map<String, DeviceModuleMetadata> _map;
  _FakeModuleRegistry(this._map);
  @override
  UnmodifiableMapView<String, DeviceModuleMetadata> get metaModules => UnmodifiableMapView(_map);
}

class _TestClock implements IClock {
  @override
  DateTime now() => DateTime.now();
  @override
  DateTime utcNow() => DateTime.now().toUtc();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deleteDevice removes device locally without needing pull-to-refresh', () async {
    final device1 = DeviceEntity(
      id: 'dev-1',
      name: 'Dev 1',
      sceneID: 's1',
      groupID: 'g1',
      driverID: 'drv',
      fingerprint: 'fp1',
      address: Uri.parse('coap://127.0.0.1'),
      compatible: 'c',
      model: 'm',
    );
    final device2 = DeviceEntity(
      id: 'dev-2',
      name: 'Dev 2',
      sceneID: 's1',
      groupID: 'g1',
      driverID: 'drv',
      fingerprint: 'fp2',
      address: Uri.parse('coap://127.0.0.1'),
      compatible: 'c',
      model: 'm',
    );

    final group = DeviceGroupEntity(id: 'g1', sceneID: 's1', name: 'G1');

    final fakeDeviceManager = _FakeDeviceManager([device1, device2]);
    final fakeGroupManager = _FakeGroupManager([group]);
    final fakeRegistry = _FakeModuleRegistry({'drv': _FakeModule('drv')});

    final vm = GroupedDevicesViewModel(
      EventBus(),
      _FakeSceneManager(),
      fakeGroupManager,
      fakeDeviceManager,
      fakeRegistry,
      clock: _TestClock(),
      gt: FakeGettext(),
      logger: Logger(),
    );

    await vm.initialize();

    expect(vm.groups, isNotEmpty);
    final gvm = vm.groups.firstWhere((g) => g.id == 'g1');
    expect(gvm.devices.map((d) => d.deviceEntity.id), containsAll(['dev-1', 'dev-2']));

    await vm.deleteDevice('dev-1');

    // allow microtasks to run
    await Future<void>.delayed(Duration.zero);

    // debug output to aid diagnosing intermittent failures
    // ignore: avoid_print
    print(
      'groups after delete: ${vm.groups.map((g) => {'id': g.id, 'devices': g.devices.map((d) => d.deviceEntity.id).toList()})}',
    );

    // Re-query the group VM after the operation because reload may have
    // replaced the group instance during a full refresh.
    final gvmAfter = vm.groups.firstWhere((g) => g.id == 'g1');
    final remaining = gvmAfter.devices.map((d) => d.deviceEntity.id).toList();
    expect(remaining, equals(['dev-2']));
  });
}
