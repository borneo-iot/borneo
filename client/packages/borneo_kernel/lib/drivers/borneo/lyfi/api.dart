import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:borneo_kernel_abstractions/device.dart';
import 'package:cancellation_token/cancellation_token.dart';

typedef MyIntList = List<int>;

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
