import 'package:borneo_common/version_ext.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/base_lyfi_driver.dart';
import 'package:borneo_kernel/drivers/borneo/coap_client.dart';
import 'package:borneo_kernel/drivers/borneo/coap_config.dart';
import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/coap_driver_data.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:borneo_kernel/drivers/borneo/probe_coap_config.dart';
import 'package:borneo_common/io/net/host_resolution.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:coap/coap.dart';
import 'package:cbor/cbor.dart' as cbor2;

import 'package:borneo_common/io/net/coap_client.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/metadata.dart';
import 'package:borneo_kernel_abstractions/errors.dart';
import 'package:borneo_kernel_abstractions/models/discovered_device.dart';
import 'package:borneo_kernel_abstractions/models/io.dart';
import 'package:borneo_kernel_abstractions/models/supported_device_descriptor.dart';
import 'package:borneo_kernel_abstractions/device.dart';
import 'package:borneo_kernel_abstractions/driver.dart';
import 'package:logger/logger.dart';
import 'package:pub_semver/pub_semver.dart';

class LyfiPaths {
  static final Uri info = Uri(path: '/borneo/lyfi/info');
  static final Uri status = Uri(path: '/borneo/lyfi/status');
  static final Uri state = Uri(path: '/borneo/lyfi/state');
  static final Uri color = Uri(path: '/borneo/lyfi/color');
  static final Uri output = Uri(path: '/borneo/lyfi/output');
  static final Uri schedule = Uri(path: '/borneo/lyfi/schedule');
  static final Uri mode = Uri(path: '/borneo/lyfi/mode');
  static final Uri correctionMethod = Uri(path: '/borneo/lyfi/correction-method');
  static final Uri geoLocation = Uri(path: '/borneo/lyfi/geo-location');
  static final Uri tzEnabled = Uri(path: '/borneo/lyfi/tz/enabled');
  static final Uri tzOffset = Uri(path: '/borneo/lyfi/tz/offset');
  static final Uri acclimation = Uri(path: '/borneo/lyfi/acclimation');
  static final Uri cloudEnabled = Uri(path: '/borneo/lyfi/cloud/enabled');
  static final Uri temporaryDuration = Uri(path: '/borneo/lyfi/temporary-duration');
  static final Uri channel = Uri(path: '/borneo/lyfi/channel');

  static final Uri sunSchedule = Uri(path: '/borneo/lyfi/sun/schedule');
  static final Uri sunCurve = Uri(path: '/borneo/lyfi/sun/curve');

  static final Uri moonConfig = Uri(path: '/borneo/lyfi/moon');
  static final Uri moonSchedule = Uri(path: '/borneo/lyfi/moon/schedule');
  static final Uri moonCurve = Uri(path: '/borneo/lyfi/moon/curve');
  static final Uri moonStatus = Uri(path: '/borneo/lyfi/moon/status');

  static final Uri currentTemp = Uri(path: '/borneo/lyfi/thermal/temp/current');
  static final Uri keepTemp = Uri(path: '/borneo/lyfi/thermal/temp/keep');
  static final Uri fanMode = Uri(path: '/borneo/lyfi/thermal/fan/mode');
  static final Uri fanManual = Uri(path: '/borneo/lyfi/thermal/fan/manual');
}

class BorneoLyfiCoapDriver extends BaseLyfiDriver with BorneoDeviceCoapApi implements Driver, ILyfiDeviceApi {
  static const String lyfiCompatibleString = 'bst,borneo-lyfi';
  final Logger? logger;

  BorneoLyfiCoapDriver({this.logger});

  @override
  Future<bool> probe(Device dev, {CancellationToken? cancelToken}) async {
    final resolvedAddress = await resolveUriHostToPreferredAddress(dev.address);
    if (resolvedAddress != dev.address) {
      logger?.i('Resolved device address `${dev.address}` -> `$resolvedAddress`');
    }

    final probeCoapClient = BorneoCoapClient(
      resolvedAddress,
      config: BorneoProbeCoapConfig.coapConfig,
      device: dev,
      offlineDetectionEnabled: false,
    );
    bool succeed = false;
    try {
      // Verify compatible string
      final compatible = await _getCompatible(probeCoapClient, cancelToken: cancelToken);
      if (compatible != lyfiCompatibleString) {
        throw UncompatibleDeviceError("Uncompatible device: `$compatible`", dev);
      }

      final coapClient = BorneoCoapClient(
        resolvedAddress,
        config: BorneoCoapConfig.coapConfig,
        device: dev,
        offlineDetectionEnabled: true,
      );
      // Verify firmware version
      final fwver = await _getFirmwareVersion(coapClient, cancelToken: cancelToken);
      if (!kLyfiFWVersionConstraint.allows(fwver)) {
        throw UnsupportedVersionError(
          'Unsupported firmware version',
          dev,
          currentVersion: fwver,
          versionRange: kLyfiFWVersionConstraint,
        );
      }

      final driverData = LyfiCoapDriverData(dev, coapClient, probeCoapClient);
      coapClient.deviceEvents = driverData.deviceEvents;
      driverData.load();
      dev.setDriverData(driverData);
      succeed = true;
    } on CoapRequestTimeoutException catch (e, stackTrace) {
      logger?.w("Failed to probe device($dev): $e", error: e, stackTrace: stackTrace);
      succeed = false;
    } finally {
      if (!succeed) {
        probeCoapClient.close();
      }
    }
    return succeed;
  }

  @override
  Future<bool> remove(Device dev, {CancellationToken? cancelToken}) async {
    final dd = dev.driverData as LyfiCoapDriverData;
    dd.dispose();
    return true;
  }

  @override
  Future<bool> heartbeat(Device dev, {CancellationToken? cancelToken}) async {
    if (dev.driverData.isBusy) {
      return true;
    }
    return withQueue(
      dev,
      () async {
        try {
          final dd = dev.driverData as LyfiCoapDriverData;
          return await dd.probeCoap.ping().asCancellable(cancelToken);
        } catch (e) {
          return false;
        }
      },
      cancelToken: cancelToken,
      priority: IOCommandPriority.low,
    );
  }

  @override
  void dispose() {}

  Future<Stream<dynamic>> startHeartbeatObservation(Device dev) async {
    final dd = dev.driverData as LyfiCoapDriverData;
    final client = dd.coap;
    final request = CoapRequest.get(BorneoPaths.heartbeat);
    // Use a low retransmit count for heartbeat observation so failures surface faster
    final obs = await client.observe(request, maxRetransmit: 1);

    return obs
        .map((msg) {
          try {
            return cbor2.cborDecode(msg.payload);
          } catch (e) {
            logger?.w('Failed to decode heartbeat payload: $e');
            return null;
          }
        })
        .where((data) => data != null);
  }

  Future<String> _getCompatible(CoapClient coap, {CancellationToken? cancelToken}) async {
    final compatible = await coap.getCbor<String>(BorneoPaths.compatible, cancelToken: cancelToken);
    return compatible;
  }

  Future<Version> _getFirmwareVersion(CoapClient coap, {CancellationToken? cancelToken}) async {
    final fwver = await coap.getCbor<String>(BorneoPaths.firmwareVersion, cancelToken: cancelToken);
    return Version.parse(fwver);
  }

  static SupportedDeviceDescriptor? matches(DiscoveredDevice discovered) {
    if (discovered is MdnsDiscoveredDevice) {
      final compatible = discovered.txt?['compatible'];
      if (compatible == null || compatible.isEmpty || !compatible.contains(',')) {
        return null;
      }
      final fwVerText = discovered.txt?['fwver'];
      if (fwVerText == null || fwVerText.isEmpty) {
        return null;
      }
      final fwVer = VersionTryParsing.tryParse(fwVerText);
      if (fwVer == null) {
        return null;
      }
      if (compatible == lyfiCompatibleString) {
        final matched = SupportedDeviceDescriptor(
          driverDescriptor: borneoLyfiDriverDescriptor,
          address: Uri(scheme: 'coap', host: discovered.host, port: discovered.port),
          name: discovered.txt?['name'] ?? '',
          compatible: compatible,
          model: discovered.txt?['model'] ?? '',
          fingerprint: discovered.txt?['serno'] ?? '',
          manuf: discovered.txt?['manuf'] ?? '',
          fwVer: fwVer,
          isCE: discovered.txt?['ce'] == 'true' ? true : false,
        );
        return matched;
      }
    }
    return null;
  }

  @override
  Future<GeneralBorneoDeviceInfo> getGeneralDeviceInfo(Device dev, {CancellationToken? cancelToken}) async {
    final dd = dev.driverData as LyfiCoapDriverData;
    final payload = await dd.coap.getCbor<Map>(BorneoPaths.deviceInfo, cancelToken: cancelToken);
    return GeneralBorneoDeviceInfo.fromMap(payload);
  }

  @override
  Future<int> getKeepTemp(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    return await dd.coap.getCbor<int>(LyfiPaths.keepTemp, cancelToken: cancelToken);
  }, cancelToken: cancelToken);

  @override
  Future<LyfiDeviceInfo> getLyfiInfo(Device dev, {CancellationToken? cancelToken}) async {
    final dd = dev.driverData as LyfiCoapDriverData;
    final payload = await dd.coap.getCbor<Map>(LyfiPaths.info, cancelToken: cancelToken);
    return LyfiDeviceInfo.fromMap(payload);
  }

  @override
  Future<LyfiDeviceStatus> getLyfiStatus(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    final payload = await dd.coap.getCbor<Map>(LyfiPaths.status, cancelToken: cancelToken);
    return LyfiDeviceStatus.fromMap(payload);
  }, cancelToken: cancelToken);

  @override
  Future<List<int>> getOutput(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    final result = await dd.coap.getCbor<List<Object?>>(LyfiPaths.output, cancelToken: cancelToken);
    return List<int>.from(result, growable: false);
  }, cancelToken: cancelToken);

  @override
  Future<List<int>> getColor(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    final result = await dd.coap.getCbor<List<Object?>>(LyfiPaths.color, cancelToken: cancelToken);
    return List<int>.from(result, growable: false);
  }, cancelToken: cancelToken);

  @override
  Future<void> setColor(Device dev, List<int> color, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    await dd.coap.putCbor(LyfiPaths.color, color, cancelToken: cancelToken);
  }, cancelToken: cancelToken);

  @override
  Future<LyfiState> getState(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    final value = await dd.coap.getCbor<int>(LyfiPaths.state, cancelToken: cancelToken);
    return LyfiState.values[value];
  }, cancelToken: cancelToken);

  @override
  Future<void> switchState(Device dev, LyfiState state, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    await dd.coap.putCbor(LyfiPaths.state, state.index, cancelToken: cancelToken);
  }, cancelToken: cancelToken);

  @override
  Future<LyfiMode> getMode(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    final value = await dd.coap.getCbor<int>(LyfiPaths.mode, cancelToken: cancelToken);
    return LyfiMode.values[value];
  }, cancelToken: cancelToken);

  @override
  Future<void> switchMode(Device dev, LyfiMode mode, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    return await dd.coap.putCbor(LyfiPaths.mode, mode.index, cancelToken: cancelToken);
  }, cancelToken: cancelToken);

  @override
  Future<ScheduleTable> getSchedule(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    final items = await dd.coap.getCbor<List<dynamic>>(LyfiPaths.schedule, cancelToken: cancelToken);
    return items.map((x) => ScheduledInstant.fromMap(x!)).toList();
  }, cancelToken: cancelToken);

  @override
  Future<void> setSchedule(Device dev, Iterable<ScheduledInstant> schedule, {CancellationToken? cancelToken}) =>
      withQueue(dev, () async {
        final dd = dev.driverData as LyfiCoapDriverData;
        final payload = schedule.map((x) => x.toPayload());
        return await dd.coap.putCbor(LyfiPaths.schedule, payload, cancelToken: cancelToken);
      }, cancelToken: cancelToken);

  @override
  Future<LedCorrectionMethod> getCorrectionMethod(Device dev, {CancellationToken? cancelToken}) =>
      withQueue(dev, () async {
        final dd = dev.driverData as LyfiCoapDriverData;
        final value = await dd.coap.getCbor<int>(LyfiPaths.correctionMethod, cancelToken: cancelToken);
        return LedCorrectionMethod.values[value];
      }, cancelToken: cancelToken);

  @override
  Future<void> setCorrectionMethod(
    Device dev,
    LedCorrectionMethod correctionMethod, {
    CancellationToken? cancelToken,
  }) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    return await dd.coap.putCbor(LyfiPaths.correctionMethod, correctionMethod.index, cancelToken: cancelToken);
  }, cancelToken: cancelToken);

  @override
  Future<Duration> getTemporaryDuration(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    final minutes = await dd.coap.getCbor<int>(LyfiPaths.temporaryDuration, cancelToken: cancelToken);
    return Duration(minutes: minutes);
  }, cancelToken: cancelToken);

  @override
  Future<void> setTemporaryDuration(Device dev, Duration duration, {CancellationToken? cancelToken}) =>
      withQueue(dev, () async {
        final dd = dev.driverData as LyfiCoapDriverData;
        final minutes = duration.inMinutes;
        return await dd.coap.putCbor(LyfiPaths.temporaryDuration, minutes, cancelToken: cancelToken);
      }, cancelToken: cancelToken);

  @override
  Future<GeoLocation?> getLocation(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    final result = await dd.coap.getCbor<dynamic>(LyfiPaths.geoLocation, cancelToken: cancelToken);
    if (result != null) {
      return GeoLocation.fromMap(result);
    } else {
      return null;
    }
  }, cancelToken: cancelToken);

  @override
  Future<void> setLocation(Device dev, GeoLocation location, {CancellationToken? cancelToken}) =>
      withQueue(dev, () async {
        final dd = dev.driverData as LyfiCoapDriverData;
        return await dd.coap.putCbor(LyfiPaths.geoLocation, location, cancelToken: cancelToken);
      }, cancelToken: cancelToken);

  @override
  Future<bool> getTimeZoneEnabled(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    return await dd.coap.getCbor<bool>(LyfiPaths.tzEnabled, cancelToken: cancelToken);
  }, cancelToken: cancelToken);

  @override
  Future<void> setTimeZoneEnabled(Device dev, bool enabled, {CancellationToken? cancelToken}) =>
      withQueue(dev, () async {
        final dd = dev.driverData as LyfiCoapDriverData;
        await dd.coap.putCbor(LyfiPaths.tzEnabled, enabled, cancelToken: cancelToken);
      }, cancelToken: cancelToken);

  @override
  Future<int> getTimeZoneOffset(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    return await dd.coap.getCbor<int>(LyfiPaths.tzOffset, cancelToken: cancelToken);
  }, cancelToken: cancelToken);

  @override
  Future<void> setTimeZoneOffset(Device dev, int offset, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    await dd.coap.putCbor(LyfiPaths.tzOffset, offset, cancelToken: cancelToken);
  }, cancelToken: cancelToken);

  @override
  Future<bool> getCloudEnabled(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    return await dd.coap.getCbor<bool>(LyfiPaths.cloudEnabled, cancelToken: cancelToken);
  }, cancelToken: cancelToken);

  @override
  Future<void> setCloudEnabled(Device dev, bool enabled, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    await dd.coap.putCbor(LyfiPaths.cloudEnabled, enabled, cancelToken: cancelToken);
  }, cancelToken: cancelToken);

  @override
  Future<AcclimationSettings> getAcclimation(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    final map = await dd.coap.getCbor<dynamic>(LyfiPaths.acclimation, cancelToken: cancelToken);
    return AcclimationSettings.fromMap(map);
  }, cancelToken: cancelToken);

  @override
  Future<void> setAcclimation(Device dev, AcclimationSettings acc, {CancellationToken? cancelToken}) =>
      withQueue(dev, () async {
        final dd = dev.driverData as LyfiCoapDriverData;
        return await dd.coap.postCbor(LyfiPaths.acclimation, acc, cancelToken: cancelToken);
      }, cancelToken: cancelToken);

  @override
  Future<void> terminateAcclimation(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    await dd.coap.delete(LyfiPaths.acclimation);
  }, cancelToken: cancelToken);

  @override
  Future<ScheduleTable> getSunSchedule(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    final items = await dd.coap.getCbor<List<dynamic>>(LyfiPaths.sunSchedule, cancelToken: cancelToken);
    return items.map((x) => ScheduledInstant.fromMap(x!)).toList();
  }, cancelToken: cancelToken);

  @override
  Future<List<SunCurveItem>> getSunCurve(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.data<LyfiCoapDriverData>();
    final items = await dd.coap.getCbor<List<dynamic>>(LyfiPaths.sunCurve, cancelToken: cancelToken);
    return items.map((x) => SunCurveItem.fromMap(x!)).toList();
  }, cancelToken: cancelToken);

  @override
  Future<MoonConfig> getMoonConfig(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.data<LyfiCoapDriverData>();
    final map = await dd.coap.getCbor<Map>(LyfiPaths.moonConfig, cancelToken: cancelToken);
    return MoonConfig.fromMap(map);
  }, cancelToken: cancelToken);

  @override
  Future<MoonStatus> getMoonStatus(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.data<LyfiCoapDriverData>();
    final map = await dd.coap.getCbor<Map>(LyfiPaths.moonStatus, cancelToken: cancelToken);
    return MoonStatus.fromMap(map);
  }, cancelToken: cancelToken);

  @override
  Future<void> setMoonConfig(Device dev, MoonConfig config, {CancellationToken? cancelToken}) =>
      withQueue(dev, () async {
        final dd = dev.data<LyfiCoapDriverData>();
        await dd.coap.putCbor(LyfiPaths.moonConfig, config.toPayload(), cancelToken: cancelToken);
      }, cancelToken: cancelToken);

  @override
  Future<ScheduleTable> getMoonSchedule(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.data<LyfiCoapDriverData>();
    final items = await dd.coap.getCbor<List<dynamic>>(LyfiPaths.moonSchedule, cancelToken: cancelToken);
    return items.map((x) => ScheduledInstant.fromMap(x!)).toList();
  }, cancelToken: cancelToken);

  @override
  Future<List<MoonCurveItem>> getMoonCurve(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.data<LyfiCoapDriverData>();
    final items = await dd.coap.getCbor<List<dynamic>>(LyfiPaths.moonCurve, cancelToken: cancelToken);
    return items.map((x) => MoonCurveItem.fromMap(x!)).toList();
  }, cancelToken: cancelToken);

  @override
  Future<FanMode> getFanMode(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    final modeStr = await dd.coap.getCbor<String>(LyfiPaths.fanMode, cancelToken: cancelToken);
    return FanMode.fromString(modeStr);
  }, cancelToken: cancelToken);

  @override
  Future<void> setFanMode(Device dev, FanMode mode, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    final modeStr = mode.toString();
    return await dd.coap.putCbor(LyfiPaths.fanMode, modeStr, cancelToken: cancelToken);
  }, cancelToken: cancelToken);

  @override
  Future<int> getFanManualPower(Device dev, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    return await dd.coap.getCbor<int>(LyfiPaths.fanManual, cancelToken: cancelToken);
  }, cancelToken: cancelToken);

  @override
  Future<void> setFanManualPower(Device dev, int power, {CancellationToken? cancelToken}) => withQueue(dev, () async {
    final dd = dev.driverData as LyfiCoapDriverData;
    await dd.coap.putCbor(LyfiPaths.fanManual, power, cancelToken: cancelToken);
  }, cancelToken: cancelToken);
}
