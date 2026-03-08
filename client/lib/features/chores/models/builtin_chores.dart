import 'package:borneo_app/features/chores/models/actions/power_action.dart';
import 'package:borneo_app/features/chores/models/abstract_chore.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/core/models/scene_entity.dart';
import 'package:lw_wot/thing.dart';

const _feedModeTypes = {'Pump', 'Wavemaker'};
const _lightingTypes = {'Lighting', 'Light'};

bool _hasAnyType(Iterable<String> actualTypes, Set<String> expectedTypes) {
  return actualTypes.any(expectedTypes.contains);
}

bool _hasOnOffProperty(WotThing thing) {
  return thing.getProperty<bool>('on') != null;
}

bool _isFeedModeTarget(WotThing thing) {
  return _hasAnyType(thing.type, _feedModeTypes) && _hasOnOffProperty(thing);
}

bool _isWaterChangeTarget(WotThing thing) {
  return !_hasAnyType(thing.type, _lightingTypes) && _hasOnOffProperty(thing);
}

bool _isDryScapeTarget(WotThing thing) {
  return _hasOnOffProperty(thing);
}

PowerAction? _setOnStateIfNeeded(WotThing wotThing, bool nextState) {
  final onValue = wotThing.getProperty("on");
  if (onValue is! bool || onValue == nextState) {
    return null;
  }

  wotThing.setProperty("on", nextState);
  return PowerAction(deviceId: wotThing.id, prevState: onValue);
}

final class PowerOffAllChore extends AbstractBuiltinChore {
  PowerOffAllChore({required super.name})
    : super(
        iconAssetPath: 'assets/images/chores/icons/power-off.svg',
        requiredCapabilities: ["OnOffSwitch"],
        mutuallyExclusiveChoreTypes: const [FeedModeChore, WaterChangeModeChore, DryScapeModeChore],
      );

  /// Execute chore
  @override
  Future<List<Map<String, dynamic>>> execute(SceneEntity currentScene, IDeviceManager deviceManager) async {
    final steps = <PowerAction>[];
    for (final wotThing in deviceManager.wotThingsInCurrentScene) {
      if (!appliesToThing(wotThing)) {
        continue;
      }

      final onValue = wotThing.getProperty("on");
      if (onValue != null) {
        final prevState = onValue as bool;
        if (prevState) {
          wotThing.setProperty("on", false);
          steps.add(PowerAction(deviceId: wotThing.id, prevState: prevState));
        }
      }
    }
    return steps.map((e) => e.toJson()).toList();
  }
}

final class FeedModeChore extends AbstractBuiltinChore {
  FeedModeChore({required super.name})
    : super(
        iconAssetPath: 'assets/images/chores/icons/feed.svg',
        requiredCapabilities: ["OnOffSwitch"],
        mutuallyExclusiveChoreTypes: const [PowerOffAllChore, WaterChangeModeChore, DryScapeModeChore],
      );

  @override
  bool appliesToThing(WotThing thing) {
    return isThingOperable(thing) && _isFeedModeTarget(thing);
  }

  @override
  Future<List<Map<String, dynamic>>> execute(SceneEntity currentScene, IDeviceManager deviceManager) async {
    final steps = <PowerAction>[];
    for (final wotThing in deviceManager.wotThingsInCurrentScene) {
      if (!appliesToThing(wotThing)) {
        continue;
      }

      final step = _setOnStateIfNeeded(wotThing, false);
      if (step != null) {
        steps.add(step);
      }
    }

    return steps.map((e) => e.toJson()).toList();
  }
}

final class WaterChangeModeChore extends AbstractBuiltinChore {
  WaterChangeModeChore({required super.name})
    : super(
        iconAssetPath: 'assets/images/chores/icons/water-change.svg',
        requiredCapabilities: ["OnOffSwitch"],
        mutuallyExclusiveChoreTypes: const [PowerOffAllChore, FeedModeChore, DryScapeModeChore],
      );

  @override
  bool appliesToThing(WotThing thing) {
    return isThingOperable(thing) && _isWaterChangeTarget(thing);
  }

  @override
  Future<List<Map<String, dynamic>>> execute(SceneEntity currentScene, IDeviceManager deviceManager) async {
    final steps = <PowerAction>[];
    for (final wotThing in deviceManager.wotThingsInCurrentScene) {
      if (!appliesToThing(wotThing)) {
        continue;
      }

      final step = _setOnStateIfNeeded(wotThing, false);
      if (step != null) {
        steps.add(step);
      }
    }

    return steps.map((e) => e.toJson()).toList();
  }
}

final class DryScapeModeChore extends AbstractBuiltinChore {
  DryScapeModeChore({required super.name})
    : super(
        iconAssetPath: 'assets/images/chores/icons/dry-scape.svg',
        requiredCapabilities: ["OnOffSwitch"],
        mutuallyExclusiveChoreTypes: const [PowerOffAllChore, FeedModeChore, WaterChangeModeChore],
      );

  @override
  bool appliesToThing(WotThing thing) {
    return isThingOperable(thing) && _isDryScapeTarget(thing);
  }

  @override
  Future<List<Map<String, dynamic>>> execute(SceneEntity currentScene, IDeviceManager deviceManager) async {
    final steps = <PowerAction>[];
    for (final wotThing in deviceManager.wotThingsInCurrentScene) {
      if (!appliesToThing(wotThing)) {
        continue;
      }

      final isLighting = _hasAnyType(wotThing.type, _lightingTypes);
      final step = _setOnStateIfNeeded(wotThing, isLighting);
      if (step != null) {
        steps.add(step);
      }
    }

    return steps.map((e) => e.toJson()).toList();
  }
}
