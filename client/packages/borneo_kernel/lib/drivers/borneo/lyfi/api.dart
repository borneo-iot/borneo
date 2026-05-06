import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:borneo_kernel_abstractions/device.dart';
import 'package:cancellation_token/cancellation_token.dart';

typedef MyIntList = List<int>;

class LyfiPaths {
  static final Uri info = Uri(path: '/borneo/lyfi/v1/info');
  static final Uri status = Uri(path: '/borneo/lyfi/v1/status');
  static final Uri state = Uri(path: '/borneo/lyfi/v1/state');
  static final Uri color = Uri(path: '/borneo/lyfi/v1/color');
  static final Uri output = Uri(path: '/borneo/lyfi/v1/output');
  static final Uri schedule = Uri(path: '/borneo/lyfi/v1/schedule');
  static final Uri mode = Uri(path: '/borneo/lyfi/v1/mode');
  static final Uri correctionMethod = Uri(path: '/borneo/lyfi/v1/correction-method');
  static final Uri geoLocation = Uri(path: '/borneo/lyfi/v1/geo-location');
  static final Uri tzEnabled = Uri(path: '/borneo/lyfi/v1/tz/enabled');
  static final Uri tzOffset = Uri(path: '/borneo/lyfi/v1/tz/offset');
  static final Uri acclimation = Uri(path: '/borneo/lyfi/v1/acclimation');
  static final Uri cloudEnabled = Uri(path: '/borneo/lyfi/v1/cloud/enabled');
  static final Uri temporaryDuration = Uri(path: '/borneo/lyfi/v1/temporary-duration');
  static final Uri channel = Uri(path: '/borneo/lyfi/v1/channel');

  static final Uri sunSchedule = Uri(path: '/borneo/lyfi/v1/sun/schedule');
  static final Uri sunCurve = Uri(path: '/borneo/lyfi/v1/sun/curve');

  static final Uri moonConfig = Uri(path: '/borneo/lyfi/v1/moon');
  static final Uri moonSchedule = Uri(path: '/borneo/lyfi/v1/moon/schedule');
  static final Uri moonCurve = Uri(path: '/borneo/lyfi/v1/moon/curve');
  static final Uri moonStatus = Uri(path: '/borneo/lyfi/v1/moon/status');

  static final Uri currentTemp = Uri(path: '/borneo/lyfi/v1/thermal/temp/current');
  static final Uri keepTemp = Uri(path: '/borneo/lyfi/v1/thermal/temp/keep');
  static final Uri fanMode = Uri(path: '/borneo/lyfi/v1/thermal/fan/mode');
  static final Uri fanManual = Uri(path: '/borneo/lyfi/v1/thermal/fan/manual');
}

abstract class ILyfiDeviceApi extends IBorneoDeviceApi {
  Future<LyfiDeviceInfo> getLyfiInfo(Device dev, {CancellationToken? cancelToken});
  Future<LyfiDeviceStatus> getLyfiStatus(Device dev, {CancellationToken? cancelToken});

  Future<LyfiState> getState(Device dev, {CancellationToken? cancelToken});
  Future<void> switchState(Device dev, LyfiState state, {CancellationToken? cancelToken});

  Future<LyfiMode> getMode(Device dev, {CancellationToken? cancelToken});
  Future<void> switchMode(Device dev, LyfiMode mode, {CancellationToken? cancelToken});

  Future<ScheduleTable> getSchedule(Device dev, {CancellationToken? cancelToken});
  Future<void> setSchedule(Device dev, Iterable<ScheduledInstant> schedule, {CancellationToken? cancelToken});

  Future<List<int>> getOutput(Device dev, {CancellationToken? cancelToken});

  Future<List<int>> getColor(Device dev, {CancellationToken? cancelToken});
  Future<void> setColor(Device dev, List<int> color, {CancellationToken? cancelToken});

  Future<int> getKeepTemp(Device dev, {CancellationToken? cancelToken});

  Future<LedCorrectionMethod> getCorrectionMethod(Device dev, {CancellationToken? cancelToken});
  Future<void> setCorrectionMethod(Device dev, LedCorrectionMethod mode, {CancellationToken? cancelToken});

  Future<Duration> getTemporaryDuration(Device dev, {CancellationToken? cancelToken});
  Future<void> setTemporaryDuration(Device dev, Duration duration, {CancellationToken? cancelToken});

  Future<GeoLocation?> getLocation(Device dev, {CancellationToken? cancelToken});
  Future<void> setLocation(Device dev, GeoLocation location, {CancellationToken? cancelToken});

  Future<bool> getTimeZoneEnabled(Device dev, {CancellationToken? cancelToken});
  Future<void> setTimeZoneEnabled(Device dev, bool enabled, {CancellationToken? cancelToken});

  Future<int> getTimeZoneOffset(Device dev, {CancellationToken? cancelToken});
  Future<void> setTimeZoneOffset(Device dev, int offset, {CancellationToken? cancelToken});

  Future<bool> getCloudEnabled(Device dev, {CancellationToken? cancelToken});
  Future<void> setCloudEnabled(Device dev, bool enabled, {CancellationToken? cancelToken});

  Future<AcclimationSettings> getAcclimation(Device dev, {CancellationToken? cancelToken});
  Future<void> setAcclimation(Device dev, AcclimationSettings acc, {CancellationToken? cancelToken});
  Future<void> terminateAcclimation(Device dev, {CancellationToken? cancelToken});

  Future<ScheduleTable> getSunSchedule(Device dev, {CancellationToken? cancelToken});
  Future<List<SunCurveItem>> getSunCurve(Device dev, {CancellationToken? cancelToken});

  Future<MoonConfig> getMoonConfig(Device dev, {CancellationToken? cancelToken});
  Future<void> setMoonConfig(Device dev, MoonConfig config, {CancellationToken? cancelToken});
  Future<MoonStatus> getMoonStatus(Device dev, {CancellationToken? cancelToken});

  Future<ScheduleTable> getMoonSchedule(Device dev, {CancellationToken? cancelToken});
  Future<List<MoonCurveItem>> getMoonCurve(Device dev, {CancellationToken? cancelToken});

  /// Gets the current fan mode.
  Future<FanMode> getFanMode(Device dev, {CancellationToken? cancelToken});

  /// Sets the fan mode.
  Future<void> setFanMode(Device dev, FanMode mode, {CancellationToken? cancelToken});

  /// Gets the manual fan power level (0-100).
  Future<int> getFanManualPower(Device dev, {CancellationToken? cancelToken});

  /// Sets the manual fan power level (0-100).
  Future<void> setFanManualPower(Device dev, int power, {CancellationToken? cancelToken});
}
