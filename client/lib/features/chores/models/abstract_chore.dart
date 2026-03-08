import 'package:borneo_app/features/chores/models/actions/led_switch_temporary_mode_action.dart';
import 'package:borneo_app/features/chores/models/actions/power_action.dart';
import 'package:borneo_app/features/chores/models/actions/chore_action.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/core/models/scene_entity.dart';
import 'package:lw_wot/thing.dart';

import '../../../shared/models/base_entity.dart';

abstract class AbstractChore with BaseEntity {
  final String id;
  final String name;
  final String iconAssetPath;

  final List<String> requiredCapabilities;
  final List<Type>? _mutuallyExclusiveChoreTypes;
  List<Type> get mutuallyExclusiveChoreTypes => _mutuallyExclusiveChoreTypes ?? const <Type>[];

  const AbstractChore({
    required this.id,
    required this.name,
    required this.iconAssetPath,
    required this.requiredCapabilities,
    List<Type>? mutuallyExclusiveChoreTypes,
  }) : _mutuallyExclusiveChoreTypes = mutuallyExclusiveChoreTypes;

  bool checkAvailable(SceneEntity scene, IDeviceManager deviceManager) {
    final things = deviceManager.wotThingsInCurrentScene;
    final isAvailable = things.any(matchAllCapabilities);
    return isAvailable;
  }

  ChoreAction createAction(Map<String, dynamic> e) => switch (e['type']) {
    PowerAction.type => PowerAction.fromJson(e),
    LedSwitchTemporaryModeAction.type => LedSwitchTemporaryModeAction.fromJson(e),
    _ => throw UnimplementedError('Unknown chore action type: `${e['type']}`'),
  };

  Future<List<Map<String, dynamic>>> execute(SceneEntity currentScene, IDeviceManager deviceManager);

  bool isThingOperable(WotThing thing) {
    return thing.getProperty<bool>('online') ?? false;
  }

  bool appliesToThing(WotThing thing) {
    return isThingOperable(thing) && matchAllCapabilities(thing);
  }

  int countApplicableDevices(IDeviceManager deviceManager) {
    return deviceManager.wotThingsInCurrentScene.where(appliesToThing).length;
  }

  bool isMutuallyExclusiveWith(AbstractChore other) {
    if (identical(this, other) || runtimeType == other.runtimeType) {
      return false;
    }

    return mutuallyExclusiveChoreTypes.contains(other.runtimeType) ||
        other.mutuallyExclusiveChoreTypes.contains(runtimeType);
  }

  bool matchAllCapabilities(WotThing thing) {
    return requiredCapabilities.every((capability) => _hasCapability(thing, capability));
  }

  bool _hasCapability(WotThing thing, String capability) {
    final types = thing.type;
    if (types.contains(capability)) return true;

    // Check for capability-specific properties that indicate the capability
    switch (capability) {
      case "OnOffSwitch":
        return thing.hasProperty("on");
      case "LyfiThing":
        return thing.hasProperty("state") && thing.hasProperty("mode");
      default:
        return false;
    }
  }
}

abstract class AbstractBuiltinChore extends AbstractChore {
  AbstractBuiltinChore({
    required super.name,
    required super.iconAssetPath,
    required super.requiredCapabilities,
    super.mutuallyExclusiveChoreTypes = const <Type>[],
  }) : super(id: BaseEntity.generateID());
}
