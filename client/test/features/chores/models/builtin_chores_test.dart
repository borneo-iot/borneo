import 'package:borneo_app/core/models/scene_entity.dart';
import 'package:borneo_app/features/chores/models/builtin_chores.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lw_wot/wot.dart';

import '../../../mocks/core/services/device_manager.dart';

void main() {
  group('builtin chores', () {
    test('countApplicableDevices counts only online operable devices', () {
      final onlinePump = _buildThing(id: 'pump-1', types: ['Pump'], on: true, online: true);
      final offlinePump = _buildThing(id: 'pump-2', types: ['Pump'], on: true, online: false);
      final noOnlineFlag = _buildThing(id: 'pump-3', types: ['Pump'], on: true);
      final manager = StubDeviceManager(things: [onlinePump, offlinePump, noOnlineFlag]);

      final count = FeedModeChore(name: 'Feed Mode').countApplicableDevices(manager);

      expect(count, 1);
    });

    test('FeedModeChore turns off pump and wavemaker devices with on property', () async {
      final pump = _buildThing(id: 'pump-1', types: ['Pump'], on: true, online: true);
      final wavemaker = _buildThing(id: 'wavemaker-1', types: ['Wavemaker'], on: true, online: true);
      final lighting = _buildThing(id: 'light-1', types: ['Light'], on: true, online: true);
      final thingWithoutOn = _buildThing(id: 'pump-2', types: ['Pump'], online: true);
      final manager = StubDeviceManager(things: [pump, wavemaker, lighting, thingWithoutOn]);

      final steps = await FeedModeChore(name: 'Feed Mode').execute(_scene(), manager);

      expect(pump.getProperty<bool>('on'), isFalse);
      expect(wavemaker.getProperty<bool>('on'), isFalse);
      expect(lighting.getProperty<bool>('on'), isTrue);
      expect(thingWithoutOn.hasProperty('on'), isFalse);
      expect(steps, hasLength(2));
    });

    test('WaterChangeModeChore turns off non-lighting devices only', () async {
      final pump = _buildThing(id: 'pump-1', types: ['Pump'], on: true, online: true);
      final wavemaker = _buildThing(id: 'wavemaker-1', types: ['Wavemaker'], on: true, online: true);
      final lighting = _buildThing(id: 'light-1', types: ['Light'], on: true, online: true);
      final lightingAlias = _buildThing(id: 'light-2', types: ['Lighting'], on: true, online: true);
      final manager = StubDeviceManager(things: [pump, wavemaker, lighting, lightingAlias]);

      final steps = await WaterChangeModeChore(name: 'Water Change Mode').execute(_scene(), manager);

      expect(pump.getProperty<bool>('on'), isFalse);
      expect(wavemaker.getProperty<bool>('on'), isFalse);
      expect(lighting.getProperty<bool>('on'), isTrue);
      expect(lightingAlias.getProperty<bool>('on'), isTrue);
      expect(steps, hasLength(2));
    });

    test('DryScapeModeChore turns on lighting and turns off other devices', () async {
      final pump = _buildThing(id: 'pump-1', types: ['Pump'], on: true, online: true);
      final wavemaker = _buildThing(id: 'wavemaker-1', types: ['Wavemaker'], on: true, online: true);
      final lightingOff = _buildThing(id: 'light-1', types: ['Light'], on: false, online: true);
      final lightingOn = _buildThing(id: 'light-2', types: ['Lighting'], on: true, online: true);
      final manager = StubDeviceManager(things: [pump, wavemaker, lightingOff, lightingOn]);

      final steps = await DryScapeModeChore(name: 'Dry Scape Mode').execute(_scene(), manager);

      expect(pump.getProperty<bool>('on'), isFalse);
      expect(wavemaker.getProperty<bool>('on'), isFalse);
      expect(lightingOff.getProperty<bool>('on'), isTrue);
      expect(lightingOn.getProperty<bool>('on'), isTrue);
      expect(steps, hasLength(3));
    });

    test('DryScapeModeChore skips offline devices during execution', () async {
      final offlinePump = _buildThing(id: 'pump-1', types: ['Pump'], on: true, online: false);
      final offlineLight = _buildThing(id: 'light-1', types: ['Light'], on: false, online: false);
      final onlineLight = _buildThing(id: 'light-2', types: ['Light'], on: false, online: true);
      final manager = StubDeviceManager(things: [offlinePump, offlineLight, onlineLight]);

      final steps = await DryScapeModeChore(name: 'Dry Scape Mode').execute(_scene(), manager);

      expect(offlinePump.getProperty<bool>('on'), isTrue);
      expect(offlineLight.getProperty<bool>('on'), isFalse);
      expect(onlineLight.getProperty<bool>('on'), isTrue);
      expect(steps, hasLength(1));
    });
  });
}

SceneEntity _scene() {
  return SceneEntity(id: 'scene-1', name: 'Scene', isCurrent: true, lastAccessTime: DateTime(2026, 3, 9));
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
