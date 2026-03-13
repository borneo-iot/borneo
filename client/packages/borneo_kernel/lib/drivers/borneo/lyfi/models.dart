import 'package:borneo_common/exceptions.dart';
import 'package:borneo_common/utils/float.dart';
import 'package:cbor/cbor.dart';

enum LedUsage { general, freshwater, marine, terra, cinema, home }

typedef ScheduleTable = List<ScheduledInstant>;

final class LyfiChannelInfo {
  final String name;
  final String color;
  final int wavelength;
  final int wavelength2;
  final double factor;

  const LyfiChannelInfo({
    required this.name,
    required this.color,
    required this.wavelength,
    this.wavelength2 = 0,
    required this.factor,
  });

  factory LyfiChannelInfo.fromMap(dynamic map) {
    return LyfiChannelInfo(
      name: map['n'] ?? 'N/A',
      color: map['c'] ?? '#FF00FF',
      wavelength: map['w'] ?? 0,
      wavelength2: map['w2'] ?? 0,
      factor: (map['f'] ?? 0.0) / 100.0,
    );
  }
}

final class LyfiDeviceInfo {
  final LedUsage usage;
  final double? nominalPfd;
  final double? nominalPower;
  final int channelCountMax;
  final int channelCount;
  final List<LyfiChannelInfo> channels;

  const LyfiDeviceInfo({
    required this.channelCountMax,
    this.nominalPfd,
    this.nominalPower,
    required this.channelCount,
    required this.channels,
    this.usage = LedUsage.general,
  });

  factory LyfiDeviceInfo.fromMap(Map map) {
    return LyfiDeviceInfo(
      usage: LedUsage.values[(map['usage'] ?? 0)],
      nominalPfd: map['nominalPfd']?.toDouble(),
      nominalPower: map['nominalPower']?.toDouble(),
      channelCountMax: map['channelCountMax'],
      channelCount: map['channelCount'],
      channels: List<LyfiChannelInfo>.from(map['channels'].map((x) => LyfiChannelInfo.fromMap(x))),
    );
  }
}

enum LyfiState {
  normal,
  dimming,
  temporary,
  preview,
  disco;

  bool get isLocked => !(this == preview || this == dimming);

  factory LyfiState.fromString(String item) => switch (item) {
    "normal" => LyfiState.normal,
    "dimming" => LyfiState.dimming,
    "temporary" => LyfiState.temporary,
    "preview" => LyfiState.preview,
    "disco" => LyfiState.disco,
    _ => throw InvalidDataException(),
  };
}

enum LyfiMode {
  manual,
  scheduled,
  sun;

  bool get isSchedulerEnabled => this == scheduled;

  factory LyfiMode.fromString(String item) => switch (item) {
    "manual" => LyfiMode.manual,
    "scheduled" => LyfiMode.scheduled,
    "sun" => LyfiMode.sun,
    _ => throw InvalidDataException(),
  };
}

enum LedCorrectionMethod { log, linear, exp, gamma, cie1931 }

extension LedCorrectionMethodExtension on LedCorrectionMethod {
  static LedCorrectionMethod fromString(String item) => switch (item) {
    "log" => LedCorrectionMethod.log,
    "linear" => LedCorrectionMethod.linear,
    "exp" => LedCorrectionMethod.exp,
    "gamma" => LedCorrectionMethod.gamma,
    "cie1931" => LedCorrectionMethod.cie1931,
    _ => throw InvalidDataException(),
  };
}

final class GeoLocation {
  final double lat;
  final double lng;

  const GeoLocation({required this.lat, required this.lng});

  @override
  String toString() => "(${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})";

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! GeoLocation) {
      return false;
    }
    const double tolerance = 0.00001;
    return (lat - other.lat).abs() < tolerance && (lng - other.lng).abs() < tolerance;
  }

  @override
  int get hashCode => Object.hash(lat, lng);

  factory GeoLocation.fromMap(dynamic map) {
    return GeoLocation(lat: map['lat'], lng: map['lng']);
  }

  CborMap toCbor() {
    final cborLat = CborFloat(convertToFloat32(lat));
    cborLat.floatPrecision();
    final cborLng = CborFloat(convertToFloat32(lng));
    cborLng.floatPrecision();

    return CborMap({CborString("lat"): cborLat, CborString("lng"): cborLng});
  }
}

final class AcclimationSettings {
  final bool enabled;
  final DateTime startTimestamp;
  final int startPercent;
  final int days;

  const AcclimationSettings({
    required this.enabled,
    required this.startTimestamp,
    required this.startPercent,
    required this.days,
  });

  factory AcclimationSettings.fromMap(dynamic map) {
    return AcclimationSettings(
      enabled: map["enabled"],
      startTimestamp: DateTime.fromMillisecondsSinceEpoch(map['startTimestamp'] * 1000, isUtc: true),
      days: map["days"],
      startPercent: map["startPercent"],
    );
  }

  CborMap toCbor() {
    return CborMap({
      CborString("enabled"): CborBool(enabled),
      CborString("startTimestamp"): CborValue((startTimestamp.millisecondsSinceEpoch / 1000.0).round()),
      CborString("startPercent"): CborSmallInt(startPercent),
      CborString("days"): CborSmallInt(days),
    });
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcclimationSettings &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          startTimestamp == other.startTimestamp &&
          startPercent == other.startPercent &&
          days == other.days;

  @override
  int get hashCode => enabled.hashCode ^ startTimestamp.hashCode ^ startPercent.hashCode ^ days.hashCode;
}

final class LyfiDeviceStatus {
  final LyfiState state;
  final LyfiMode mode;
  final bool unscheduled;
  final Duration temporaryRemaining;
  final int? fanPower;
  final List<int> currentColor;
  final List<int> manualColor;
  final List<int> sunColor;
  final bool acclimationEnabled;
  final bool acclimationActivated;
  final bool cloudEnabled;
  final bool cloudActivated;
  final int? temperature;
  final double? powerCurrent;

  double get brightness => currentColor.fold(0, (p, v) => p + v).toDouble() * 100.0 / (currentColor.length * 100.0);

  const LyfiDeviceStatus({
    required this.state,
    required this.mode,
    required this.unscheduled,
    required this.temporaryRemaining,
    this.fanPower,
    required this.currentColor,
    required this.manualColor,
    required this.sunColor,
    required this.temperature,
    required this.powerCurrent,
    this.acclimationEnabled = false,
    this.acclimationActivated = false,
    this.cloudEnabled = false,
    this.cloudActivated = false,
  });

  factory LyfiDeviceStatus.fromMap(Map map) {
    return LyfiDeviceStatus(
      state: LyfiState.values[map['state']],
      mode: LyfiMode.values[map['mode']],
      unscheduled: map['unscheduled'],
      temporaryRemaining: Duration(seconds: map['tempRemain']),
      fanPower: map['fanPower'] == null ? null : (map['fanPower'] as int),
      currentColor: List<int>.from(map['currentColor']),
      manualColor: List<int>.from(map['manualColor']),
      sunColor: List<int>.from(map['sunColor']),
      temperature: map['temperature'],
      powerCurrent: map['powerCurrent'] != null ? map['powerCurrent'] / 1000.0 : null,
      acclimationEnabled: map['acclimationEnabled'] ?? false,
      acclimationActivated: map['acclimationActivated'] ?? false,
      cloudEnabled: map['cloudEnabled'] ?? false,
      cloudActivated: map['cloudActivated'] ?? false,
    );
  }
}

final class ScheduledInstant {
  final Duration instant;
  final List<int> color;
  const ScheduledInstant({required this.instant, required this.color});

  factory ScheduledInstant.fromMap(dynamic map) {
    final secs = map['instant'] as int;
    return ScheduledInstant(
      instant: Duration(seconds: secs),
      color: List<int>.from(map['color'], growable: false),
    );
  }

  List<dynamic> toPayload() {
    return [instant.inSeconds, color];
  }

  bool get isZero => !color.any((x) => x != 0);
}

final class MoonConfig {
  final bool enabled;
  final List<int> color;
  const MoonConfig({required this.enabled, required this.color});

  factory MoonConfig.fromMap(dynamic map) {
    return MoonConfig(enabled: map['enabled'], color: List<int>.from(map['color'], growable: false));
  }

  Map<String, dynamic> toPayload() {
    return {'enabled': enabled, 'color': color};
  }
}

final class MoonStatus {
  final double phaseAngle;
  final double illumination;
  const MoonStatus({required this.phaseAngle, required this.illumination});

  factory MoonStatus.fromMap(dynamic map) {
    return MoonStatus(phaseAngle: map['phaseAngle'], illumination: map['illumination']);
  }

  Map<String, dynamic> toPayload() {
    return {'phaseAngle': phaseAngle, 'illumination': illumination};
  }
}

final class SunCurveItem {
  final Duration instant;
  final double brightness;
  const SunCurveItem({required this.instant, required this.brightness});

  factory SunCurveItem.fromMap(Map map) {
    final secs = map['time'] as double;
    return SunCurveItem(
      instant: Duration(seconds: (secs * 3600.0).round()),
      brightness: map['brightness'],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! SunCurveItem) {
      return false;
    }
    const double tolerance = 0.00001;
    return instant == other.instant && (brightness - other.brightness).abs() < tolerance;
  }

  @override
  int get hashCode => Object.hash(instant, brightness);
}

final class MoonCurveItem {
  final Duration instant;
  final double brightness;
  const MoonCurveItem({required this.instant, required this.brightness});

  factory MoonCurveItem.fromMap(Map map) {
    final hours = map['time'] as double;
    return MoonCurveItem(
      instant: Duration(seconds: (hours * 3600.0).round()),
      brightness: map['brightness'],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! MoonCurveItem) {
      return false;
    }
    const double tolerance = 0.00001;
    return instant == other.instant && (brightness - other.brightness).abs() < tolerance;
  }

  @override
  int get hashCode => Object.hash(instant, brightness);
}

/// Represents the fan mode for the device
enum FanMode {
  /// PID adaptive algorithm mode
  pid,

  /// Manual fan power setting mode (0-100% integer value)
  manual;

  @override
  String toString() {
    return switch (this) {
      FanMode.manual => "manual",
      FanMode.pid => "pid",
    };
  }

  factory FanMode.fromString(String item) => switch (item) {
    "manual" => FanMode.manual,
    "pid" => FanMode.pid,
    _ => throw InvalidDataException(),
  };
}
