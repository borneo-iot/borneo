part of 'wot_thing.dart';

extension LyfiThingProperties on LyfiThing {
  /// Create properties with reasonable defaults first, then bind to hardware
  /// This follows Mozilla WebThing pattern of creating Value objects with initial values
  void _createPropertiesWithDefaults() {
    _createBasicProperties();
    _createStateModeProperties();
    _createLightingProperties();
    _createTimezoneProperties();
    _createTemperatureProperties();
    _createFanProperties();
    _createCloudProperties();
    _createTemporaryProperties();
    _createSunMoonProperties();
    _createDeviceInfoProperties();
    _createOtherProperties();
  }

  void _createBasicProperties() {
    // Power property with default false, will be updated when hardware is ready
    final onProperty = ObservableWotProperty<bool, DevicePowerOnOffChangedEvent>(
      thing: this,
      deviceEvents: deviceEvents,
      name: 'on',
      value: WotValue<bool>(
        initialValue: false, // Default value, updated in _bindToHardware
        valueForwarder: (update) => _withBorneoApi((api, device) => api.setOnOff(device, update)),
      ),
      metadata: WotPropertyMetadata(
        type: 'boolean',
        title: 'On/Off',
        description: 'Power on/off state',
        readOnly: false,
      ),
      eventName: 'onChanged',
      mapper: (event) => event.onOff,
    );
    addProperty(onProperty);
  }

  void _createStateModeProperties() {
    // State property with default state
    final stateProperty = ObservableWotProperty<String, LyfiStateChangedEvent>(
      thing: this,
      deviceEvents: deviceEvents,
      name: 'state',
      value: WotValue<String>(
        initialValue: LyfiState.values.first.name, // Default state
        valueForwarder: (update) async {
          await _withLyfiApi((api, device) => api.switchState(device, LyfiState.fromString(update)));
        },
      ),
      metadata: WotPropertyMetadata(
        type: 'string',
        title: 'State',
        description: 'Lyfi operating state',
        enumValues: LyfiState.values.map((e) => e.name).toList(),
        readOnly: false,
      ),
      eventName: 'stateChanged',
      mapper: (event) => event.state.name,
    );
    addProperty(stateProperty);

    // Mode property with default mode
    final modeProperty = ObservableWotProperty<String, LyfiModeChangedEvent>(
      thing: this,
      deviceEvents: deviceEvents,
      name: 'mode',
      value: WotValue<String>(
        initialValue: LyfiMode.values.first.name, // Default mode
        valueForwarder: (update) => _withLyfiApi((api, device) => api.switchMode(device, LyfiMode.fromString(update))),
      ),
      metadata: WotPropertyMetadata(
        type: 'string',
        title: 'Mode',
        description: 'Lyfi lighting mode',
        enumValues: LyfiMode.values.map((e) => e.name).toList(),
        readOnly: false,
      ),
      eventName: 'modeChanged',
      mapper: (event) => event.mode.name,
    );
    addProperty(modeProperty);
  }

  void _createLightingProperties() {
    // Color property with default all-off color
    addProperty(
      MutableLyfiColorProperty(
        thing: this,
        name: 'color',
        valueForwarder: (update) async {
          await _withLyfiApi((api, device) async => await api.setColor(device, update));
          final state = LyfiState.fromString(getProperty<String>('state')!);
          if (state == LyfiState.dimming) {
            final mode = LyfiMode.fromString(getProperty<String>('mode')!);
            switch (mode) {
              case LyfiMode.manual:
                findProperty('manualColor')!.value.notifyOfExternalUpdate(update);
                break;

              case LyfiMode.sun:
                findProperty('sunColor')!.value.notifyOfExternalUpdate(update);
                break;
              default:
                break;
            }
          }
        },
      ),
    );

    // Schedule property
    final scheduleProperty = WotProperty<ScheduleTable>(
      thing: this,
      name: 'schedule',
      value: WotValue<ScheduleTable>(
        initialValue: [], // Default empty schedule
        valueForwarder: (_) => throw UnsupportedError('Schedule is read-only; use action to update'),
      ),
      metadata: WotPropertyMetadata(
        type: 'array',
        title: 'Schedule',
        description: 'LED lighting schedule with time instants and colors',
        readOnly: true,
      ),
    );
    addProperty(scheduleProperty);

    // Acclimation property
    final acclimationProperty = ObservableWotProperty<AcclimationSettings, LyfiAcclimationChangedEvent>(
      thing: this,
      deviceEvents: deviceEvents,
      name: 'acclimation',
      value: WotValue<AcclimationSettings>(
        initialValue: AcclimationSettings(
          enabled: false,
          startTimestamp: DateTime.now().toUtc(),
          startPercent: 0,
          days: 0,
        ),
        valueForwarder: (_) => throw UnsupportedError('Acclimation is read-only; use action to update'),
      ),
      metadata: WotPropertyMetadata(
        type: 'object',
        title: 'Acclimation',
        description: 'LED acclimation settings for gradual brightness increase',
        readOnly: true,
      ),
      eventName: 'acclimationChanged',
      mapper: (event) => event.settings,
    );
    addProperty(acclimationProperty);

    // Location property
    final locationProperty = ObservableWotProperty<GeoLocation?, LyfiLocationChangedEvent>(
      thing: this,
      deviceEvents: deviceEvents,
      name: 'location',
      value: WotValue<GeoLocation?>(
        initialValue: null, // Default no location
        valueForwarder: (update) async {
          if (update != null) {
            await _withLyfiApi((api, device) => api.setLocation(device, update));
          }
        },
      ),
      metadata: WotPropertyMetadata(
        type: 'object',
        title: 'Location',
        description: 'Geographic location for sun simulation calculations',
        readOnly: false,
      ),
      eventName: 'locationChanged',
      mapper: (event) => event.location,
    );
    addProperty(locationProperty);

    // Correction method property
    final correctionMethodProperty = ObservableWotProperty<String, LyfiCorrectionMethodChangedEvent>(
      thing: this,
      deviceEvents: deviceEvents,
      name: 'correctionMethod',
      value: WotValue<String>(
        initialValue: LedCorrectionMethod.log.name,
        valueForwarder: (update) => _withLyfiApi(
          (api, device) => api.setCorrectionMethod(device, LedCorrectionMethodExtension.fromString(update)),
        ),
      ),
      metadata: WotPropertyMetadata(
        type: 'string',
        title: 'Correction Method',
        description: 'LED brightness correction method',
        enumValues: LedCorrectionMethod.values.map((e) => e.name).toList(),
        readOnly: false,
      ),
      eventName: 'correctionMethodChanged',
      mapper: (event) => event.method.name,
    );
    addProperty(correctionMethodProperty);
  }

  void _createTimezoneProperties() {
    // Timezone property (read-only)
    final timezoneProperty = WotProperty<String>(
      thing: this,
      name: 'timezone',
      value: WotValue<String>(initialValue: '', valueForwarder: (_) => throw UnsupportedError('Timezone is read-only')),
      metadata: WotPropertyMetadata(
        type: 'string',
        title: 'Timezone',
        description: 'Device timezone name',
        readOnly: true,
      ),
    );
    addProperty(timezoneProperty);

    // Timezone enabled property
    final timezoneEnabledProperty = WotProperty<bool>(
      thing: this,
      name: 'timezoneEnabled',
      value: WotValue<bool>(
        initialValue: false, // Default false
        valueForwarder: (update) => _withLyfiApi((api, device) => api.setTimeZoneEnabled(device, update)),
      ),
      metadata: WotPropertyMetadata(
        type: 'boolean',
        title: 'Timezone Enabled',
        description: 'Whether timezone offset is enabled',
        readOnly: false,
      ),
    );
    addProperty(timezoneEnabledProperty);

    // Timezone offset property
    final timezoneOffsetProperty = WotProperty<int>(
      thing: this,
      name: 'timezoneOffset',
      value: WotValue<int>(
        initialValue: 0, // Default 0 offset
        valueForwarder: (update) => _withLyfiApi((api, device) => api.setTimeZoneOffset(device, update)),
      ),
      metadata: WotPropertyMetadata(
        type: 'integer',
        title: 'Timezone Offset',
        description: 'Timezone offset in seconds from UTC',
        readOnly: false,
      ),
    );
    addProperty(timezoneOffsetProperty);
  }

  void _createTemperatureProperties() {
    // Keep temperature property
    final keepTempProperty = WotProperty<int>(
      thing: this,
      name: 'keepTemp',
      value: WotValue<int>(
        initialValue: 75, // Default 75°C
        valueForwarder: (_) => throw UnsupportedError('Keep temperature is read-only for safety'),
      ),
      metadata: WotPropertyMetadata(
        type: 'integer',
        title: 'Keep Temperature',
        description: 'Thermal protection temperature threshold in Celsius',
        readOnly: true,
      ),
    );
    addProperty(keepTempProperty);

    // Current temperature property
    final temperatureProperty = WotProperty<int?>(
      thing: this,
      name: 'temperature',
      value: WotValue<int?>(
        initialValue: null, // Default null
        valueForwarder: (update) => throw UnsupportedError('Temperature is read-only'),
      ),
      metadata: WotPropertyMetadata(
        type: 'integer',
        title: 'Current Temperature',
        description: 'Current device temperature in Celsius',
        readOnly: true,
      ),
    );
    addProperty(temperatureProperty);

    // Current temperature property (read-only)
    final currentTempProperty = WotProperty<int>(
      thing: this,
      name: 'currentTemp',
      value: WotValue<int>(
        initialValue: 25, // Default 25°C
        valueForwarder: (_) => throw UnsupportedError('Current temperature is read-only'),
      ),
      metadata: WotPropertyMetadata(
        type: 'integer',
        title: 'Current Temperature',
        description: 'Current device temperature sensor reading in Celsius',
        readOnly: true,
      ),
    );
    addProperty(currentTempProperty);
  }

  void _createFanProperties() {
    // Fan mode property
    final fanModeProperty = WotProperty<String>(
      thing: this,
      name: 'fanMode',
      value: WotValue<String>(
        initialValue: FanMode.pid.name, // Default PID mode
        valueForwarder: (update) =>
            _withLyfiApi((api, device) => api.setFanMode(device, FanMode.values.firstWhere((e) => e.name == update))),
      ),
      metadata: WotPropertyMetadata(
        type: 'string',
        title: 'Fan Mode',
        description: 'Fan control mode (PID adaptive or manual)',
        enumValues: FanMode.values.map((e) => e.name).toList(),
        readOnly: false,
      ),
    );
    addProperty(fanModeProperty);

    // Fan manual power property
    final fanManualPowerProperty = ObservableWotProperty<int, Object>(
      thing: this,
      deviceEvents: deviceEvents,
      name: 'fanManualPower',
      value: WotValue<int>(
        initialValue: 0, // Default 0% power
        valueForwarder: (update) => _withLyfiApi((api, device) => api.setFanManualPower(device, update)),
      ),
      metadata: WotPropertyMetadata(
        type: 'integer',
        title: 'Fan Manual Power',
        description: 'Manual fan power level (0-100%)',
        minimum: 0,
        maximum: 100,
        readOnly: false,
      ),
      subscribe: false,
      eventName: '', // Not used
      mapper: (event) => 0, // Not used
    );
    addProperty(fanManualPowerProperty);

    // Fan power property (read-only)
    final fanPowerProperty = WotProperty<int>(
      thing: this,
      name: 'fanPower',
      value: WotValue<int>(
        initialValue: 0, // Default 0%
        valueForwarder: (update) async {
          throw UnsupportedError('Fan power is read-only');
        },
      ),
      metadata: WotPropertyMetadata(
        type: 'integer',
        title: 'Fan Power',
        description: 'Current fan power level (0-100%)',
        minimum: 0,
        maximum: 100,
        readOnly: true,
      ),
    );
    addProperty(fanPowerProperty);
  }

  void _createCloudProperties() {
    // Cloud enabled property
    final cloudEnabledProperty = WotProperty<bool>(
      thing: this,
      name: 'cloudEnabled',
      value: WotValue<bool>(
        initialValue: false, // Default false
        valueForwarder: (update) => _withLyfiApi((api, device) => api.setCloudEnabled(device, update)),
      ),
      metadata: WotPropertyMetadata(
        type: 'boolean',
        title: 'Cloud Enabled',
        description: 'Controls cloud connectivity for remote management',
        readOnly: false,
      ),
    );
    addProperty(cloudEnabledProperty);

    // Cloud activated property (read-only)
    final cloudActivatedProperty = WotProperty<bool>(
      thing: this,
      name: 'cloudActivated',
      value: WotValue<bool>(
        initialValue: false, // Default false
        valueForwarder: (update) async {
          throw UnsupportedError('Cloud activated is read-only');
        },
      ),
      metadata: WotPropertyMetadata(
        type: 'boolean',
        title: 'Cloud Activated',
        description: 'Whether cloud connection is active',
        readOnly: true,
      ),
    );
    addProperty(cloudActivatedProperty);
  }

  void _createTemporaryProperties() {
    // Temporary duration property
    final temporaryDurationProperty = WotProperty<Duration>(
      thing: this,
      name: 'temporaryDuration',
      value: WotValue<Duration>(
        initialValue: Duration.zero, // Default zero duration
        valueForwarder: (update) => _withLyfiApi((api, device) => api.setTemporaryDuration(device, update)),
      ),
      metadata: WotPropertyMetadata(
        type: 'duration',
        title: 'Temporary Duration',
        description: 'Duration for temporary lighting mode',
        readOnly: false,
      ),
    );
    addProperty(temporaryDurationProperty);

    // Temporary remaining property (read-only)
    final temporaryRemainingProperty = WotProperty<Duration>(
      thing: this,
      name: 'temporaryRemaining',
      value: WotValue<Duration>(
        initialValue: Duration.zero, // Default zero duration
        valueForwarder: (update) => throw UnsupportedError('Temporary remaining is read-only'),
      ),
      metadata: WotPropertyMetadata(
        type: 'duration',
        title: 'Temporary Remaining',
        description: 'Time remaining in temporary mode',
        readOnly: true,
      ),
    );
    addProperty(temporaryRemainingProperty);
  }

  void _createSunMoonProperties() {
    // Sun schedule property (read-only)
    final sunScheduleProperty = WotProperty<List<ScheduledInstant>>(
      thing: this,
      name: 'sunSchedule',
      value: WotValue<List<ScheduledInstant>>(
        initialValue: [], // Default empty
        valueForwarder: (update) => throw UnsupportedError('Sun schedule is read-only'),
      ),
      metadata: WotPropertyMetadata(
        type: 'array',
        title: 'Sun Schedule',
        description: 'Computed sun-based lighting schedule',
        readOnly: true,
      ),
    );
    addProperty(sunScheduleProperty);

    // Sun curve property (read-only)
    final sunCurveProperty = WotProperty<List<SunCurveItem>>(
      thing: this,
      name: 'sunCurve',
      value: WotValue<List<SunCurveItem>>(
        initialValue: [], // Default empty
        valueForwarder: (_) => throw UnsupportedError('Sun curve is read-only'),
      ),
      metadata: WotPropertyMetadata(
        type: 'array',
        title: 'Sun Curve',
        description: 'Sun brightness curve data points',
        readOnly: true,
      ),
    );
    addProperty(sunCurveProperty);

    // Moon config property (read-only)
    final moonConfigProperty = WotProperty<MoonConfig>(
      thing: this,
      name: 'moonConfig',
      value: WotValue<MoonConfig>(
        initialValue: MoonConfig(enabled: false, color: [0, 0, 0, 0]),
        valueForwarder: (_) => throw UnsupportedError('Moon config is read-only; use action to update'),
      ),
      metadata: WotPropertyMetadata(
        title: 'Moon Configuration',
        type: 'object',
        description: 'Configuration for moon simulation including enabled state and color',
        readOnly: true,
      ),
    );
    addProperty(moonConfigProperty);

    // Moon status property (read-only)
    final moonStatusProperty = WotProperty<MoonStatus>(
      thing: this,
      name: 'moonStatus',
      value: WotValue<MoonStatus>(initialValue: MoonStatus(phaseAngle: 0.0, illumination: 0.0)),
      metadata: WotPropertyMetadata(
        title: 'Moon Status',
        type: 'object',
        description: 'Current moon phase angle and illumination percentage',
        readOnly: true,
      ),
    );
    addProperty(moonStatusProperty);

    // Moon schedule property (read-only)
    final moonScheduleProperty = WotProperty<List<ScheduledInstant>>(
      thing: this,
      name: 'moonSchedule',
      value: WotValue<List<ScheduledInstant>>(
        initialValue: [],
        valueForwarder: (_) => throw UnsupportedError('Moon schedule is read-only'),
      ),
      metadata: WotPropertyMetadata(
        title: 'Moon Schedule',
        type: 'array',
        description: 'Schedule for moon simulation',
        readOnly: true,
      ),
    );
    addProperty(moonScheduleProperty);

    // Moon curve property (read-only)
    final moonCurveProperty = WotProperty<List<MoonCurveItem>>(
      thing: this,
      name: 'moonCurve',
      value: WotValue<List<MoonCurveItem>>(
        initialValue: [],
        valueForwarder: (_) => throw UnsupportedError('Moon curve is read-only'),
      ),
      metadata: WotPropertyMetadata(
        title: 'Moon Curve',
        type: 'array',
        description: 'Brightness curve for moon simulation',
        readOnly: true,
      ),
    );
    addProperty(moonCurveProperty);
  }

  void _createDeviceInfoProperties() {
    // Device info property (read-only)
    final lyfiDeviceInfoProperty = WotProperty<LyfiDeviceInfo>(
      thing: this,
      name: 'lyfiDeviceInfo',
      value: WotValue<LyfiDeviceInfo>(
        initialValue: LyfiDeviceInfo(
          nominalPar: null,
          nominalPower: null,
          channelCountMax: 0,
          channelCount: 0,
          channels: [],
        ), // Default empty
        valueForwarder: (_) => throw UnsupportedError('Device info is read-only'),
      ),
      metadata: WotPropertyMetadata(
        type: 'object',
        title: 'LyFi Device Info',
        description: 'LyFi Device capabilities and channel metadata',
        readOnly: true,
      ),
    );
    addProperty(lyfiDeviceInfoProperty);

    // Temporary Lyfi status property for refactoring - TODO: Remove after refactoring
    final lyfiStatusProperty = WotProperty<LyfiDeviceStatus>(
      thing: this,
      name: 'lyfiStatus',
      value: WotValue<LyfiDeviceStatus>(
        initialValue: LyfiDeviceStatus(
          state: LyfiState.normal,
          mode: LyfiMode.manual,
          unscheduled: false,
          temporaryRemaining: Duration.zero,
          currentColor: [0, 0, 0, 0],
          manualColor: [0, 0, 0, 0],
          sunColor: [0, 0, 0, 0],
          temperature: null,
          powerCurrent: null,
        ), // Default values
        valueForwarder: (update) async {
          // Allow setting for now during refactoring
        },
      ),
      metadata: WotPropertyMetadata(
        type: 'object',
        title: 'Lyfi Status',
        description: 'Temporary property for Lyfi device status during refactoring',
        readOnly: false,
      ),
    );
    addProperty(lyfiStatusProperty);

    // General device info property (read-only)
    final generalDeviceInfoProperty = WotProperty<GeneralBorneoDeviceInfo?>(
      thing: this,
      name: 'generalDeviceInfo',
      value: WotValue<GeneralBorneoDeviceInfo?>(
        initialValue: null,
        valueForwarder: (update) async {
          throw UnsupportedError('General device info is read-only');
        },
      ),
      metadata: WotPropertyMetadata(
        type: 'object',
        title: 'General Device Info',
        description: 'General Borneo device information',
        readOnly: true,
      ),
    );
    addProperty(generalDeviceInfoProperty);

    // Temporary general status property for refactoring - TODO: Remove after refactoring
    final generalStatusProperty = WotProperty<GeneralBorneoDeviceStatus>(
      thing: this,
      name: 'generalStatus',
      value: WotValue<GeneralBorneoDeviceStatus>(
        initialValue: GeneralBorneoDeviceStatus(
          timestamp: DateTime.now().toUtc(),
          bootDuration: Duration.zero,
          timezone: '',
          wifiStatus: 0,
          btStatus: 0,
          serverStatus: 0,
          error: 0,
          shutdownReason: 0,
          power: false,
        ), // Default values
        valueForwarder: (update) async {
          throw UnsupportedError('General status is read-only during refactoring');
        },
      ),
      metadata: WotPropertyMetadata(
        type: 'object',
        title: 'General Status',
        description: 'Temporary property for general Borneo device status during refactoring',
        readOnly: true,
      ),
    );
    addProperty(generalStatusProperty);
  }

  void _createOtherProperties() {
    // Unscheduled property (read-only)
    final unscheduledProperty = WotProperty<bool>(
      thing: this,
      name: 'unscheduled',
      value: WotValue<bool>(
        initialValue: false, // Default false
        valueForwarder: (update) async {
          throw UnsupportedError('Unscheduled status is read-only');
        },
      ),
      metadata: WotPropertyMetadata(
        type: 'boolean',
        title: 'Unscheduled',
        description: 'Whether device is operating outside schedule',
        readOnly: true,
      ),
    );
    addProperty(unscheduledProperty);

    // Manual color property (read-only)
    final manualColorProperty = ReadonlyLyfiColorProperty(thing: this, name: 'manualColor');
    addProperty(manualColorProperty);

    // Sun color property (read-only)
    final sunColorProperty = ReadonlyLyfiColorProperty(thing: this, name: 'sunColor');
    addProperty(sunColorProperty);

    // Acclimation enabled property (read-only)
    final acclimationEnabledProperty = WotProperty<bool>(
      thing: this,
      name: 'acclimationEnabled',
      value: WotValue<bool>(
        initialValue: false,
        valueForwarder: (update) => throw UnsupportedError('Acclimation enabled is read-only'),
      ),
      metadata: WotPropertyMetadata(
        type: 'boolean',
        title: 'Acclimation Enabled',
        description: 'Whether acclimation is enabled',
        readOnly: true,
      ),
    );
    addProperty(acclimationEnabledProperty);

    // Acclimation activated property (read-only)
    final acclimationActivatedProperty = WotProperty<bool>(
      thing: this,
      name: 'acclimationActivated',
      value: WotValue<bool>(
        initialValue: false, // Default false
        valueForwarder: (update) async {
          throw UnsupportedError('Acclimation activated is read-only');
        },
      ),
      metadata: WotPropertyMetadata(
        type: 'boolean',
        title: 'Acclimation Activated',
        description: 'Whether acclimation is currently running',
        readOnly: true,
      ),
    );
    addProperty(acclimationActivatedProperty);

    // Voltage property (read-only)
    final voltageProperty = WotProperty<double?>(
      thing: this,
      name: 'voltage',
      value: WotValue<double?>(
        initialValue: null, // Default null
        valueForwarder: (update) async {
          throw UnsupportedError('Voltage is read-only');
        },
      ),
      metadata: WotPropertyMetadata(
        type: 'number',
        title: 'Voltage',
        description: 'Current voltage in volts',
        readOnly: true,
      ),
    );
    addProperty(voltageProperty);

    // Current property (read-only)
    final currentProperty = WotProperty<double?>(
      thing: this,
      name: 'current',
      value: WotValue<double?>(
        initialValue: null, // Default null
        valueForwarder: (update) async => throw UnsupportedError('Current is read-only'),
      ),
      metadata: WotPropertyMetadata(
        type: 'number',
        title: 'Current',
        description: 'Current current in amperes',
        readOnly: true,
      ),
    );
    addProperty(currentProperty);

    // Power property (read-only)
    final powerProperty = WotProperty<double?>(
      thing: this,
      name: 'power',
      value: WotValue<double?>(
        initialValue: null, // Default null
        valueForwarder: (update) async => throw UnsupportedError('Power is read-only'),
      ),
      metadata: WotPropertyMetadata(
        type: 'number',
        title: 'Power',
        description: 'Current power consumption in watts',
        readOnly: true,
      ),
    );
    addProperty(powerProperty);

    // Power behavior property (read-only)
    final powerBehaviorProperty = WotProperty<PowerBehavior>(
      thing: this,
      name: 'powerBehavior',
      value: WotValue<PowerBehavior>(
        initialValue: PowerBehavior.lastPowerState, // Default to last power state
        valueForwarder: (_) => throw UnsupportedError('Power behavior is read-only'),
      ),
      metadata: WotPropertyMetadata(
        type: 'string',
        title: 'Power Behavior',
        description: 'Behavior when power is restored after an outage',
        enumValues: PowerBehavior.values.map((e) => e.name).toList(),
        readOnly: true,
      ),
    );
    addProperty(powerBehaviorProperty);

    // Timestamp property (read-only)
    final timestampProperty = WotProperty<DateTime>(
      thing: this,
      name: 'timestamp',
      value: WotValue<DateTime>(
        initialValue: DateTime.now().toUtc(),
        valueForwarder: (_) => throw UnsupportedError('Timestamp is read-only'),
      ),
      metadata: WotPropertyMetadata(
        type: 'string',
        title: 'Timestamp',
        description: 'Device timestamp (UTC)',
        readOnly: true,
      ),
    );
    addProperty(timestampProperty);
  }
}
