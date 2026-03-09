import 'package:borneo_app/core/models/scene_entity.dart';
import 'package:borneo_app/core/services/chore_manager_impl.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/features/chores/models/builtin_chores.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lw_wot/wot.dart';
import 'package:borneo_kernel_abstractions/kernel.dart';
import 'package:sembast/sembast_memory.dart';

import '../../mocks/mocks.dart';

void main() {
  group('ChoreManagerImpl mutual exclusion', () {
    late Database db;
    late StubSceneManager sceneManager;
    late _TestDeviceManager deviceManager;
    late EventBus eventBus;
    late ChoreManagerImpl manager;

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase('chore-manager-test.db');
      sceneManager = StubSceneManager([
        SceneEntity(id: 'scene-1', name: 'Scene', isCurrent: true, lastAccessTime: DateTime(2026, 3, 9)),
      ]);
      deviceManager = _TestDeviceManager(
        bound: [
          _buildBoundDevice(id: 'pump-1', sceneId: 'scene-1'),
          _buildBoundDevice(id: 'light-1', sceneId: 'scene-1'),
        ],
        things: [
          _buildThing(id: 'pump-1', types: ['Pump'], on: true, online: true),
          _buildThing(id: 'light-1', types: ['Light'], on: true, online: true),
        ],
      );
      eventBus = EventBus();
      manager = ChoreManagerImpl(
        eventBus,
        db,
        sceneManager,
        deviceManager,
        clock: TestClock(),
        gettext: FakeGettext(),
        logger: TestLogger(),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('executing a mutually exclusive builtin chore undoes the previous active chore first', () async {
      final powerOffAll = manager.allChores.whereType<PowerOffAllChore>().single;
      final feedMode = manager.allChores.whereType<FeedModeChore>().single;
      final pump = deviceManager.wotThingsInCurrentScene.firstWhere((thing) => thing.id == 'pump-1');
      final light = deviceManager.wotThingsInCurrentScene.firstWhere((thing) => thing.id == 'light-1');

      await manager.executeChore(powerOffAll.id);

      expect(await manager.hasHistoryForChore(powerOffAll.id), isTrue);
      expect(pump.getProperty<bool>('on'), isFalse);
      expect(light.getProperty<bool>('on'), isFalse);

      await manager.executeChore(feedMode.id);

      expect(await manager.hasHistoryForChore(powerOffAll.id), isFalse);
      expect(await manager.hasHistoryForChore(feedMode.id), isTrue);
      expect(pump.getProperty<bool>('on'), isFalse);
      expect(light.getProperty<bool>('on'), isTrue);
    });
  });
}

WotThing _buildThing({required String id, required List<String> types, bool? on, bool? online}) {
  final thing = WotThing(id: id, title: id, type: types, description: 'test thing');
  if (on != null) {
    thing.addProperty(
      WotProperty<bool>(
        thing: thing,
        name: 'on',
        value: WotValue<bool>(initialValue: on),
        metadata: WotPropertyMetadata(type: 'boolean'),
      ),
    );
  }
  if (online != null) {
    thing.addProperty(
      WotProperty<bool>(
        thing: thing,
        name: 'online',
        value: WotValue<bool>(initialValue: online),
        metadata: WotPropertyMetadata(type: 'boolean', readOnly: true),
      ),
    );
  }
  return thing;
}

BoundDevice _buildBoundDevice({required String id, required String sceneId}) {
  final device = DeviceEntity(
    id: id,
    address: Uri.parse('coap://$id.local'),
    fingerprint: 'fp-$id',
    sceneID: sceneId,
    driverID: 'test-driver',
    compatible: 'test-device',
    name: id,
    model: 'test-model',
  );
  return BoundDevice('test-driver', device, TestDriver());
}

final class _TestDeviceManager extends StubDeviceManager {
  _TestDeviceManager({required super.bound, required super.things});

  @override
  bool hasWotThing(String deviceID) => things.any((thing) => thing.id == deviceID);

  @override
  WotThing getWotThing(String deviceID) {
    return things.firstWhere((thing) => thing.id == deviceID);
  }
}
