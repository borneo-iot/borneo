part of 'wot_thing.dart';

extension LyfiThingActions on LyfiThing {
  void _createActions() {
    {
      // Switch state action
      addAvailableAction(
        'switchState',
        WotActionMetadata(
          title: 'Switch State',
          description: 'Switch the device to a different operating state',
          input: {'state': 'string'},
        ),
        (thing, input) {
          return LyfiSwitchStateAction(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            thing: thing,
            lyfiApi: _requireLyfiApi(),
            device: _requireDevice(),
            logger: logger,
            input: input,
          );
        },
      );

      // Switch mode action
      addAvailableAction(
        'switchMode',
        WotActionMetadata(
          title: 'Switch Mode',
          description: 'Switch the device to a different lighting mode',
          input: {'mode': 'string', 'color': 'array'},
        ),
        (thing, input) {
          return LyfiSwitchModeAction(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            thing: thing,
            lyfiApi: _requireLyfiApi(),
            device: _requireDevice(),
            input: input,
            logger: logger,
          );
        },
      );

      // Set color action
      addAvailableAction(
        'setColor',
        WotActionMetadata(
          title: 'Set Color',
          description: 'Set the LED channel brightness values',
          input: {'color': 'array'},
        ),
        (thing, input) {
          final color = input['color'] as List<int>;
          return LyfiSetColorAction(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            thing: thing,
            color: color,
            lyfiApi: _requireLyfiApi(),
            device: _requireDevice(),
            logger: logger,
          );
        },
      );

      // Set schedule action
      addAvailableAction(
        'setSchedule',
        WotActionMetadata(
          title: 'Set Schedule',
          description: 'Set the lighting schedule with time instants and colors',
          input: {'schedule': 'array'},
        ),
        (thing, input) {
          final schedule = input as List<ScheduledInstant>;
          return LyfiSetScheduleAction(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            thing: thing,
            schedule: schedule,
            lyfiApi: _requireLyfiApi(),
            device: _requireDevice(),
            logger: logger,
          );
        },
      );

      // Set acclimation action
      addAvailableAction(
        'setAcclimation',
        WotActionMetadata(
          title: 'Set Acclimation',
          description: 'Configure acclimation settings for gradual brightness increase',
          input: {'enabled': 'boolean', 'startTimestamp': 'number', 'startPercent': 'number', 'days': 'number'},
        ),
        (thing, input) {
          final settings = {
            'enabled': input['enabled'] as bool,
            'startTimestamp': input['startTimestamp'],
            'startPercent': input['startPercent'] as int,
            'days': input['days'] as int,
          };
          return LyfiSetAcclimationAction(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            thing: thing,
            input: settings,
            lyfiApi: _requireLyfiApi(),
            device: _requireDevice(),
            logger: logger,
          );
        },
      );

      // Set location action
      addAvailableAction(
        'setLocation',
        WotActionMetadata(
          title: 'Set Location',
          description: 'Set the geographic location for sun simulation',
          input: {'lat': 'number', 'lng': 'number'},
        ),
        (thing, input) {
          final location = GeoLocation(lat: input['lat'] as double, lng: input['lng'] as double);
          return LyfiSetLocationAction(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            thing: thing,
            location: location,
            lyfiApi: _requireLyfiApi(),
            device: _requireDevice(),
            logger: logger,
          );
        },
      );

      // Set correction method action
      addAvailableAction(
        'setCorrectionMethod',
        WotActionMetadata(
          title: 'Set Correction Method',
          description: 'Set the LED brightness correction method',
          input: {'method': 'string'},
        ),
        (thing, input) {
          final methodName = input['method'] as String;
          final method = LedCorrectionMethod.values.firstWhere((e) => e.name == methodName);
          return LyfiSetCorrectionMethodAction(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            thing: thing,
            method: method,
            lyfiApi: _requireLyfiApi(),
            device: _requireDevice(),
            logger: logger,
          );
        },
      );

      // Set power behavior action
      addAvailableAction(
        'setPowerBehavior',
        WotActionMetadata(
          title: 'Set Power Behavior',
          description: 'Set the behavior when power is restored after an outage',
          input: {'behavior': 'string'},
        ),
        (thing, input) {
          final behaviorName = input['behavior'] as String;
          final behavior = PowerBehavior.values.firstWhere((e) => e.name == behaviorName);
          return LyfiSetPowerBehaviorAction(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            thing: thing,
            behavior: behavior,
            borneoApi: _requireBorneoApi(),
            device: _requireDevice(),
            logger: logger,
          );
        },
      );

      // Set moon config action
      addAvailableAction(
        'setMoonConfig',
        WotActionMetadata(
          title: 'Set Moon Configuration',
          description: 'Set the moon simulation configuration including enabled state and color',
          input: {'enabled': 'boolean', 'color': 'array'},
        ),
        (thing, input) {
          final config = MoonConfig(enabled: input.enabled as bool, color: List<int>.from(input.color as List<int>));
          return LyfiSetMoonConfigAction(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            thing: thing,
            config: config,
            lyfiApi: _requireLyfiApi(),
            device: _requireDevice(),
            logger: logger,
          );
        },
      );
    }
  }
}
