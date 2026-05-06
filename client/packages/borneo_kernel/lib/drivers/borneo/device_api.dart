import 'dart:typed_data';

import 'package:borneo_kernel/drivers/borneo/coap_client.dart';
import 'package:borneo_kernel/drivers/borneo/coap_driver_data.dart';
import 'package:borneo_kernel_abstractions/device_api.dart';
import 'package:borneo_kernel_abstractions/driver.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'dart:convert';

import 'package:borneo_common/io/net/coap_client.dart';
import 'package:borneo_kernel_abstractions/errors.dart';
import 'package:coap/coap.dart';
import 'package:cbor/simple.dart' as simple_cbor;

import 'package:borneo_kernel_abstractions/device.dart';

const String kBorneoDeviceMdnsServiceType = '_borneo._udp';
const int kDeviceNameMaxInBytes = 63;

class BorneoPaths {
  static final Uri wellKnownCore = Uri(path: '/.well-known/core');
  static final Uri heartbeat = Uri(path: '/borneo/v1/heartbeat');
  static final Uri deviceInfo = Uri(path: '/borneo/v1/info');
  static final Uri power = Uri(path: '/borneo/v1/power');
  static final Uri reboot = Uri(path: '/borneo/v1/reboot');
  static final Uri powerBehavior = Uri(path: '/borneo/v1/power/behavior');
  static final Uri status = Uri(path: '/borneo/v1/status');
  static final Uri systemMode = Uri(path: '/borneo/v1/mode');
  static final Uri timezone = Uri(path: '/borneo/v1/settings/timezone');
  static final Uri name = Uri(path: '/borneo/v1/settings/name');
  static final Uri factoryReset = Uri(path: '/borneo/v1/factory/reset');
  static final Uri firmwareVersion = Uri(path: '/borneo/v1/fwver');
  static final Uri compatible = Uri(path: '/borneo/v1/compatible');
  static final Uri rtcLocal = Uri(path: '/borneo/v1/rtc/local');
  static final Uri rtcTimestamp = Uri(path: '/borneo/v1/rtc/ts');
  static final Uri networkReset = Uri(path: '/borneo/v1/network/reset');

  static final Uri coapOtaStatus = Uri(path: '/borneo/v1/ota/coap/status');
  static final Uri coapOtaDownload = Uri(path: '/borneo/v1/ota/coap/download');

  static final Uri nvsU8 = Uri(path: '/borneo/v1/factory/nvs/u8');
  static final Uri nvsU16 = Uri(path: '/borneo/v1/factory/nvs/u16');
  static final Uri nvsU32 = Uri(path: '/borneo/v1/factory/nvs/u32');
  static final Uri nvsI8 = Uri(path: '/borneo/v1/factory/nvs/i8');
  static final Uri nvsI16 = Uri(path: '/borneo/v1/factory/nvs/i16');
  static final Uri nvsI32 = Uri(path: '/borneo/v1/factory/nvs/i32');
  static final Uri nvsString = Uri(path: '/borneo/v1/factory/nvs/str');
  static final Uri nvsBlob = Uri(path: '/borneo/v1/factory/nvs/blob');
  static final Uri nvsExists = Uri(path: '/borneo/v1/factory/nvs/exists');
}

Set<String> parseSupportedResourcePaths(String payload) {
  final paths = <String>{};
  for (final match in RegExp(r'<([^>]+)>').allMatches(payload)) {
    final href = match.group(1);
    if (href == null || href.isEmpty) {
      continue;
    }

    try {
      final uri = Uri.parse(href);
      final normalizedPath = uri.path.isEmpty ? href : uri.path;
      if (normalizedPath.isNotEmpty) {
        paths.add(normalizedPath);
      }
    } catch (_) {
      paths.add(href);
    }
  }
  return paths;
}

Future<Set<String>> fetchSupportedResourcePaths(BorneoCoapClient client, {CancellationToken? cancelToken}) async {
  final request = CoapRequest.get(BorneoPaths.wellKnownCore, confirmable: true);
  final response = await client.send(request).asCancellable(cancelToken);
  if (!response.isSuccess) {
    throw StateError('Failed to get `${response.location}`');
  }

  return parseSupportedResourcePaths(utf8.decode(response.payload));
}

enum TransportChannel {
  wifi,
  eth,
  ble;

  static TransportChannel fromInt(int value) => TransportChannel.values[value];
}

enum SystemMode {
  init,
  normal,
  safe;

  static SystemMode fromInt(int value) => switch (value) {
    0 => SystemMode.init,
    1 => SystemMode.normal,
    2 => SystemMode.safe,
    _ => throw ArgumentError('Invalid value for SystemMode: $value'),
  };
}

enum ProductMode {
  standalone,
  full,
  oem;

  static ProductMode fromInt(int value) {
    return switch (value) {
      0 => ProductMode.standalone,
      1 => ProductMode.full,
      2 => ProductMode.oem,
      _ => throw ArgumentError('Invalid value for ProductMode: $value'),
    };
  }
}

/// Defines the power behavior of a device.
///
/// This enum specifies how a device should handle its power state in different scenarios,
/// such as after a power cycle or system reset.
enum PowerBehavior {
  /// Preserves the last known power state of the device.
  ///
  /// If the device was powered on before a power cycle, it will attempt to restore to
  /// the powered-on state, and similarly for the powered-off state.
  lastPowerState,

  /// Automatically powers on the device after a power cycle or reset.
  ///
  /// This behavior ensures the device is always powered on when possible.
  autoPowerOn,

  /// Maintains the device in a powered-off state after a power cycle or reset.
  ///
  /// This behavior ensures the device remains off until explicitly powered on.
  maintainPowerOff;

  /// Converts an integer to a [PowerBehavior] value.
  ///
  /// The integer corresponds to the ordinal value of the enum:
  /// - 0: [lastPowerState]
  /// - 1: [autoPowerOn]
  /// - 2: [maintainPowerOff]
  ///
  /// Throws an [ArgumentError] if the provided [value] is not a valid ordinal.
  static PowerBehavior fromInt(int value) => switch (value) {
    0 => PowerBehavior.lastPowerState,
    1 => PowerBehavior.autoPowerOn,
    2 => PowerBehavior.maintainPowerOff,
    _ => throw ArgumentError('Invalid value for PowerBehavior: $value'),
  };

  /// Converts this [PowerBehavior] to its corresponding integer value.
  ///
  /// The integer corresponds to the ordinal value of the enum:
  /// - [lastPowerState]: 0
  /// - [autoPowerOn]: 1
  /// - [maintainPowerOff]: 2
  int toInt() => switch (this) {
    PowerBehavior.lastPowerState => 0,
    PowerBehavior.autoPowerOn => 1,
    PowerBehavior.maintainPowerOff => 2,
  };
}

class GeneralBorneoDeviceInfo {
  final String id;
  final String name;
  final String compatible;
  final String serno;
  final String pid;
  final ProductMode productMode;
  final TransportChannel transportChannel;
  final bool hasBT;
  final bool hasWifi;
  final bool hasMqtt;
  final String vendorName;
  final String modelName;
  final Version hwVer;
  final Version fwVer;
  final bool isCE;

  const GeneralBorneoDeviceInfo({
    required this.id,
    required this.name,
    required this.compatible,
    required this.serno,
    required this.pid,
    required this.productMode,
    required this.transportChannel,
    required this.hasBT,
    required this.hasWifi,
    required this.hasMqtt,
    required this.vendorName,
    required this.modelName,
    required this.hwVer,
    required this.fwVer,
    required this.isCE,
  });

  factory GeneralBorneoDeviceInfo.fromMap(Map map) {
    return GeneralBorneoDeviceInfo(
      id: map['id'],
      compatible: map['compatible'],
      name: map['name'],
      serno: map['serno'],
      pid: map['pid'] ?? '',
      productMode: ProductMode.fromInt(map['productMode']),
      transportChannel: TransportChannel.fromInt(map['transport'] ?? 0),
      hasBT: map['hasBT'] ?? false,
      hasWifi: map['hasWifi'] ?? false,
      hasMqtt: map['hasMqtt'] ?? false,
      vendorName: map['vendor'],
      modelName: map['model'],
      hwVer: Version.parse(map['hwVer']),
      fwVer: Version.parse(map['fwVer']),
      isCE: map['isCE'] ?? true,
    );
  }
}

class GeneralBorneoDeviceStatus {
  final SystemMode mode;
  final bool power;
  final DateTime timestamp;
  final Duration bootDuration;
  final String timezone;
  final int wifiStatus;
  final int? wifiRssi;
  final int btStatus;
  final int serverStatus;
  final int error;
  final int shutdownReason;
  final DateTime? shutdownTimestamp;
  final double? powerVoltage;

  const GeneralBorneoDeviceStatus({
    this.mode = SystemMode.normal,
    this.power = false,
    required this.timestamp,
    required this.bootDuration,
    this.timezone = '',
    this.wifiStatus = 0,
    this.wifiRssi,
    this.btStatus = 0,
    this.serverStatus = 0,
    this.error = 0,
    this.shutdownReason = 0,
    this.shutdownTimestamp,
    this.powerVoltage,
  });

  factory GeneralBorneoDeviceStatus.fromMap(Map map) {
    return GeneralBorneoDeviceStatus(
      mode: SystemMode.fromInt(map['mode'] as int),
      power: map['power'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] * 1000, isUtc: true),
      bootDuration: Duration(milliseconds: map['bootDuration']),
      timezone: map['timezone'] ?? '',
      wifiStatus: map['wifiStatus'],
      wifiRssi: map['wifiRssi'],
      serverStatus: map['serverStatus'],
      error: map['error'],
      shutdownReason: map['shutdownReason'],
      shutdownTimestamp: map['shutdownTimestamp'] > 0
          ? DateTime.fromMillisecondsSinceEpoch(map['shutdownTimestamp'] * 1000, isUtc: true)
          : null,
      powerVoltage: map['powerVoltage'] != null ? map['powerVoltage'] / 1000.0 : null,
    );
  }
}

class BorneoDeviceUpgradeInfo {
  final Version runningVersion;
  final Version newVersion;
  final bool canUpgrade;

  const BorneoDeviceUpgradeInfo({required this.runningVersion, required this.newVersion, required this.canUpgrade});
}

class BorneoRtcLocalNtpResponse {
  final int t1;
  final int t2;
  final int t3;

  const BorneoRtcLocalNtpResponse({required this.t1, required this.t2, required this.t3});

  factory BorneoRtcLocalNtpResponse.fromMap(Map map) {
    return BorneoRtcLocalNtpResponse(t1: map['t1'] as int, t2: map['t2'] as int, t3: map['t3'] as int);
  }
}

enum BorneoOtaCoapUpdateStatus {
  idle,
  inProgress;

  static BorneoOtaCoapUpdateStatus fromString(String value) => switch (value) {
    'idle' => BorneoOtaCoapUpdateStatus.idle,
    'in_progress' => BorneoOtaCoapUpdateStatus.inProgress,
    _ => throw ArgumentError('Invalid value for BorneoOtaCoapUpdateStatus: $value'),
  };
}

final class BorneoOtaCoapStatus {
  final String runningPartition;
  final BorneoOtaCoapUpdateStatus updateStatus;
  final int bytesReceived;
  final dynamic otaPartitions;

  const BorneoOtaCoapStatus({
    required this.runningPartition,
    required this.updateStatus,
    required this.bytesReceived,
    required this.otaPartitions,
  });

  factory BorneoOtaCoapStatus.fromMap(Map map) {
    return BorneoOtaCoapStatus(
      runningPartition: map['running_partition'] as String,
      updateStatus: BorneoOtaCoapUpdateStatus.fromString(map['update_status'] as String),
      bytesReceived: map['bytes_received'] as int,
      otaPartitions: map['ota_partitions'] as String,
    );
  }
}

abstract class IBorneoDeviceApi extends IDeviceApi {
  Future<Set<String>> getSupportedResourcePaths(Device dev, {CancellationToken? cancelToken});
  Future<String> getCompatible(Device dev, {CancellationToken? cancelToken});
  Future<Version> getFirmwareVersion(Device dev, {CancellationToken? cancelToken});

  Future<GeneralBorneoDeviceInfo> getGeneralDeviceInfo(Device dev, {CancellationToken? cancelToken});
  Future<GeneralBorneoDeviceStatus> getGeneralDeviceStatus(Device dev, {CancellationToken? cancelToken});

  Future<DateTime> getHeartbeat(Device dev, {CancellationToken? cancelToken});

  Future<bool> getOnOff(Device dev, {CancellationToken? cancelToken});
  Future setOnOff(Device dev, bool on, {CancellationToken? cancelToken});

  Future<PowerBehavior> getPowerBehavior(Device dev, {CancellationToken? cancelToken});
  Future setPowerBehavior(Device dev, PowerBehavior behavior, {CancellationToken? cancelToken});

  Future<BorneoRtcLocalNtpResponse> getRtcLocal(Device dev, DateTime timestamp, {CancellationToken? cancelToken});
  Future<void> setRtcLocalSkew(Device dev, Duration skew, {CancellationToken? cancelToken});

  Future<DateTime> getRtcTimestamp(Device dev, {CancellationToken? cancelToken});

  Future<SystemMode> getSystemMode(Device dev, {CancellationToken? cancelToken});

  Future<String> getTimeZone(Device dev, {CancellationToken? cancelToken});
  Future<void> setTimeZone(Device dev, String timezone, {CancellationToken? cancelToken});

  Future<String> getName(Device dev, {CancellationToken? cancelToken});
  Future<void> setName(Device dev, String newName, {CancellationToken? cancelToken});

  Future<void> reboot(Device dev, {CancellationToken? cancelToken});
  Future<void> factoryReset(Device dev, {CancellationToken? cancelToken});
  Future<void> networkReset(Device dev, {CancellationToken? cancelToken});

  Future<BorneoOtaCoapStatus> getOtaCoapStatus(Device dev, {CancellationToken? cancelToken});
  Future<void> otaCoapEngage(Device dev, final Uint8List firmwareBuffer, {CancellationToken? cancelToken});

  Future<int> getFactoryNvsU8(Device dev, String ns, String key, {CancellationToken? cancelToken});
  Future<void> setFactoryNvsU8(Device dev, String ns, String key, int u8, {CancellationToken? cancelToken});
  Future<int> getFactoryNvsU16(Device dev, String ns, String key, {CancellationToken? cancelToken});
  Future<void> setFactoryNvsU16(Device dev, String ns, String key, int u16, {CancellationToken? cancelToken});
  Future<int> getFactoryNvsU32(Device dev, String ns, String key, {CancellationToken? cancelToken});
  Future<void> setFactoryNvsU32(Device dev, String ns, String key, int u32, {CancellationToken? cancelToken});
  Future<int> getFactoryNvsI8(Device dev, String ns, String key, {CancellationToken? cancelToken});
  Future<void> setFactoryNvsI8(Device dev, String ns, String key, int i8, {CancellationToken? cancelToken});
  Future<int> getFactoryNvsI16(Device dev, String ns, String key, {CancellationToken? cancelToken});
  Future<void> setFactoryNvsI16(Device dev, String ns, String key, int i16, {CancellationToken? cancelToken});
  Future<int> getFactoryNvsI32(Device dev, String ns, String key, {CancellationToken? cancelToken});
  Future<void> setFactoryNvsI32(Device dev, String ns, String key, int i32, {CancellationToken? cancelToken});
  Future<String> getFactoryNvsString(Device dev, String ns, String key, {CancellationToken? cancelToken});
  Future<void> setFactoryNvsString(Device dev, String ns, String key, String value, {CancellationToken? cancelToken});
  Future<List<int>> getFactoryNvsBlob(Device dev, String ns, String key, {CancellationToken? cancelToken});
  Future<void> setFactoryNvsBlob(Device dev, String ns, String key, List<int> value, {CancellationToken? cancelToken});
  Future<bool> factoryNvsExists(Device dev, String ns, String key, {CancellationToken? cancelToken});
}

mixin BorneoDeviceCoapApi on Driver implements IBorneoDeviceApi {
  @override
  Future<Set<String>> getSupportedResourcePaths(Device dev, {CancellationToken? cancelToken}) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      return await fetchSupportedResourcePaths(dd.coap, cancelToken: cancelToken);
    }, cancelToken: cancelToken);
  }

  Future<int> _getFactoryNvs(Device dev, Uri path, String ns, String key, {CancellationToken? cancelToken}) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final uri = path.replace(queryParameters: {'ns': ns, 'k': key});
      return await dd.coap.getCbor<int>(uri, cancelToken: cancelToken);
    }, cancelToken: cancelToken);
  }

  Future<void> _setFactoryNvs(
    Device dev,
    Uri path,
    String ns,
    String key,
    int value, {
    CancellationToken? cancelToken,
  }) async {
    await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final response = await dd.coap.postBytes(
        path,
        payload: simple_cbor.cbor.encode({"ns": ns, "k": key, "v": value}),
        accept: CoapMediaType.applicationCbor,
      );
      if (!response.isSuccess) {
        throw DeviceError("Failed to post `${response.location}`", dev);
      }
    }, cancelToken: cancelToken);
  }

  Future<String> _getFactoryNvsString(
    Device dev,
    Uri path,
    String ns,
    String key, {
    CancellationToken? cancelToken,
  }) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final uri = path.replace(queryParameters: {'ns': ns, 'k': key});
      return await dd.coap.getCbor<String>(uri, cancelToken: cancelToken);
    }, cancelToken: cancelToken);
  }

  Future<void> _setFactoryNvsString(
    Device dev,
    Uri path,
    String ns,
    String key,
    String value, {
    CancellationToken? cancelToken,
  }) async {
    await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final response = await dd.coap.postBytes(
        path,
        payload: simple_cbor.cbor.encode({"ns": ns, "k": key, "v": value}),
        accept: CoapMediaType.applicationCbor,
      );
      if (!response.isSuccess) {
        throw DeviceError("Failed to post `${response.location}`", dev);
      }
    }, cancelToken: cancelToken);
  }

  Future<List<int>> _getFactoryNvsBlob(
    Device dev,
    Uri path,
    String ns,
    String key, {
    CancellationToken? cancelToken,
  }) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final uri = path.replace(queryParameters: {'ns': ns, 'k': key});
      return await dd.coap.getCbor<List<int>>(uri, cancelToken: cancelToken);
    }, cancelToken: cancelToken);
  }

  Future<void> _setFactoryNvsBlob(
    Device dev,
    Uri path,
    String ns,
    String key,
    List<int> value, {
    CancellationToken? cancelToken,
  }) async {
    await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final response = await dd.coap.postBytes(
        path,
        payload: simple_cbor.cbor.encode({"ns": ns, "k": key, "v": value}),
        accept: CoapMediaType.applicationCbor,
      );
      if (!response.isSuccess) {
        throw DeviceError("Failed to post `${response.location}`", dev);
      }
    }, cancelToken: cancelToken);
  }

  @override
  Future<String> getCompatible(Device dev, {CancellationToken? cancelToken}) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      return await dd.coap.getCbor<String>(BorneoPaths.compatible, cancelToken: cancelToken);
    }, cancelToken: cancelToken);
  }

  @override
  Future<Version> getFirmwareVersion(Device dev, {CancellationToken? cancelToken}) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final verStr = await dd.coap.getCbor<String>(BorneoPaths.firmwareVersion, cancelToken: cancelToken);
      return Version.parse(verStr);
    }, cancelToken: cancelToken);
  }

  @override
  Future<bool> getOnOff(Device dev, {CancellationToken? cancelToken}) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      return await dd.coap.getCbor<bool>(BorneoPaths.power, cancelToken: cancelToken);
    }, cancelToken: cancelToken);
  }

  @override
  Future setOnOff(Device dev, bool on, {CancellationToken? cancelToken}) async {
    await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final response = await dd.coap.putBytes(
        BorneoPaths.power,
        payload: simple_cbor.cbor.encode(on),
        accept: CoapMediaType.applicationCbor,
      );
      if (!response.isSuccess) {
        throw DeviceError("Failed to post to `${response.location}`", dev);
      }
    }, cancelToken: cancelToken);
  }

  @override
  Future<PowerBehavior> getPowerBehavior(Device dev, {CancellationToken? cancelToken}) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final value = await dd.coap.getCbor<int>(BorneoPaths.powerBehavior, cancelToken: cancelToken);
      return PowerBehavior.values[value];
    }, cancelToken: cancelToken);
  }

  @override
  Future<DateTime> getHeartbeat(Device dev, {CancellationToken? cancelToken}) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final timestamp = await dd.coap.getCbor<int>(BorneoPaths.heartbeat, cancelToken: cancelToken);
      return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    }, cancelToken: cancelToken);
  }

  @override
  Future<BorneoRtcLocalNtpResponse> getRtcLocal(
    Device dev,
    DateTime timestamp, {
    CancellationToken? cancelToken,
  }) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final timestampUS = timestamp.isUtc ? timestamp.microsecondsSinceEpoch : timestamp.toUtc().microsecondsSinceEpoch;
      final request = CoapRequest.get(
        BorneoPaths.rtcLocal,
        confirmable: true,
        accept: CoapMediaType.applicationCbor,
        payload: simple_cbor.cbor.encode(timestampUS),
      );
      final response = await dd.coap.send(request);
      final payload = simple_cbor.cbor.decode(response.payload) as Map;
      return BorneoRtcLocalNtpResponse.fromMap(payload);
    }, cancelToken: cancelToken);
  }

  @override
  Future<void> setRtcLocalSkew(Device dev, Duration skew, {CancellationToken? cancelToken}) async {
    await this.withQueue(dev, () async {
      if (skew.isNegative) {
        throw ArgumentError('Skew must be a non-negative duration.');
      }
      if (skew < const Duration(microseconds: 1000)) {
        throw ArgumentError('Skew must be greater than 1ms.');
      }
      final dd = dev.driverData as BorneoCoapDriverData;
      await dd.coap.postCbor(BorneoPaths.rtcLocal, skew.inMicroseconds, cancelToken: cancelToken);
    }, cancelToken: cancelToken);
  }

  @override
  Future<DateTime> getRtcTimestamp(Device dev, {CancellationToken? cancelToken}) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final timestamp = await dd.coap.getCbor<int>(BorneoPaths.rtcTimestamp, cancelToken: cancelToken);
      return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    }, cancelToken: cancelToken);
  }

  @override
  Future setPowerBehavior(Device dev, PowerBehavior behavior, {CancellationToken? cancelToken}) async {
    await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      await dd.coap.putCbor(BorneoPaths.powerBehavior, behavior.index, cancelToken: cancelToken);
    }, cancelToken: cancelToken);
  }

  @override
  Future<GeneralBorneoDeviceStatus> getGeneralDeviceStatus(Device dev, {CancellationToken? cancelToken}) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final payload = await dd.coap.getCbor<Map>(BorneoPaths.status, cancelToken: cancelToken);
      return GeneralBorneoDeviceStatus.fromMap(payload);
    }, cancelToken: cancelToken);
  }

  @override
  Future<void> reboot(Device dev, {CancellationToken? cancelToken}) async {
    await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      await dd.coap.postCbor<void>(BorneoPaths.reboot, null, cancelToken: cancelToken);
    }, cancelToken: cancelToken);
  }

  @override
  Future<void> factoryReset(Device dev, {CancellationToken? cancelToken}) async {
    await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final response = await dd.coap.postBytes(
        BorneoPaths.factoryReset,
        payload: simple_cbor.cbor.encode(null),
        accept: CoapMediaType.applicationCbor,
      );
      if (!response.isSuccess) {
        throw DeviceError("Failed to put `${response.location}`", dev);
      }
    }, cancelToken: cancelToken);
  }

  @override
  Future<void> networkReset(Device dev, {CancellationToken? cancelToken}) async {
    await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final response = await dd.coap.postBytes(
        BorneoPaths.networkReset,
        payload: simple_cbor.cbor.encode(null),
        accept: CoapMediaType.applicationCbor,
      );
      if (!response.isSuccess) {
        throw DeviceError("Failed to put `${response.location}`", dev);
      }
    }, cancelToken: cancelToken);
  }

  @override
  Future<SystemMode> getSystemMode(Device dev, {CancellationToken? cancelToken}) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      return SystemMode.fromInt(await dd.coap.getCbor<int>(BorneoPaths.systemMode, cancelToken: cancelToken));
    }, cancelToken: cancelToken);
  }

  @override
  Future<String> getTimeZone(Device dev, {CancellationToken? cancelToken}) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      return await dd.coap.getCbor<String>(BorneoPaths.timezone, cancelToken: cancelToken);
    }, cancelToken: cancelToken);
  }

  @override
  Future<void> setTimeZone(Device dev, String timezone, {CancellationToken? cancelToken}) async {
    await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final response = await dd.coap.putBytes(
        BorneoPaths.timezone,
        payload: simple_cbor.cbor.encode(timezone),
        accept: CoapMediaType.applicationCbor,
      );
      if (!response.isSuccess) {
        throw DeviceError("Failed to put to `${response.location}`", dev);
      }
    }, cancelToken: cancelToken);
  }

  @override
  Future<String> getName(Device dev, {CancellationToken? cancelToken}) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      return await dd.coap.getCbor<String>(BorneoPaths.name, cancelToken: cancelToken);
    }, cancelToken: cancelToken);
  }

  @override
  Future<void> setName(Device dev, String newName, {CancellationToken? cancelToken}) async {
    if (newName.isEmpty) {
      throw ArgumentError('Device name cannot be empty.');
    }
    if (newName.trim().isEmpty) {
      throw ArgumentError('Device name cannot be pure whitespace.');
    }
    if (newName.trim() != newName) {
      throw ArgumentError('Device name cannot have leading or trailing whitespace.');
    }
    if (utf8.encode(newName).length > kDeviceNameMaxInBytes) {
      throw ArgumentError(
        'Device name is too long. Maximum length is $kDeviceNameMaxInBytes bytes when encoded as UTF-8.',
      );
    }
    await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final response = await dd.coap.putBytes(
        BorneoPaths.name,
        payload: simple_cbor.cbor.encode(newName),
        accept: CoapMediaType.applicationCbor,
      );
      if (!response.isSuccess) {
        throw DeviceError("Failed to set to `$newName`", dev);
      }
    }, cancelToken: cancelToken);
  }

  @override
  Future<BorneoOtaCoapStatus> getOtaCoapStatus(Device dev, {CancellationToken? cancelToken}) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final payload = await dd.coap.getCbor<Map>(BorneoPaths.coapOtaStatus, cancelToken: cancelToken);
      return BorneoOtaCoapStatus.fromMap(payload);
    }, cancelToken: cancelToken);
  }

  @override
  Future<void> otaCoapEngage(Device dev, final Uint8List firmwareBuffer, {CancellationToken? cancelToken}) async {
    await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      // Step 1: PUT the firmware data; the CoAP library handles Block1 block transfer automatically.
      final putResponse = await dd.coap
          .putBytes(
            BorneoPaths.coapOtaDownload,
            payload: firmwareBuffer,
            accept: CoapMediaType.applicationCbor,
            format: CoapMediaType.applicationCbor,
          )
          .asCancellable(cancelToken);
      if (!putResponse.isSuccess) {
        throw DeviceError('OTA firmware upload failed (${putResponse.codeString})', dev);
      }
      // Step 2: POST to complete the update (triggers esp_ota_end + set boot partition).
      final postResponse = await dd.coap
          .postBytes(
            BorneoPaths.coapOtaDownload,
            payload: simple_cbor.cbor.encode(null),
            accept: CoapMediaType.applicationCbor,
          )
          .asCancellable(cancelToken);
      if (!postResponse.isSuccess) {
        throw DeviceError('OTA firmware completion failed (${postResponse.codeString})', dev);
      }
    }, cancelToken: cancelToken);
  }

  @override
  Future<int> getFactoryNvsU8(Device dev, String ns, String key, {CancellationToken? cancelToken}) async {
    return await _getFactoryNvs(dev, BorneoPaths.nvsU8, ns, key, cancelToken: cancelToken);
  }

  @override
  Future<void> setFactoryNvsU8(Device dev, String ns, String key, int u8, {CancellationToken? cancelToken}) async {
    await _setFactoryNvs(dev, BorneoPaths.nvsU8, ns, key, u8, cancelToken: cancelToken);
  }

  @override
  Future<int> getFactoryNvsU16(Device dev, String ns, String key, {CancellationToken? cancelToken}) async {
    return await _getFactoryNvs(dev, BorneoPaths.nvsU16, ns, key, cancelToken: cancelToken);
  }

  @override
  Future<void> setFactoryNvsU16(Device dev, String ns, String key, int u16, {CancellationToken? cancelToken}) async {
    await _setFactoryNvs(dev, BorneoPaths.nvsU16, ns, key, u16, cancelToken: cancelToken);
  }

  @override
  Future<int> getFactoryNvsU32(Device dev, String ns, String key, {CancellationToken? cancelToken}) async {
    return await _getFactoryNvs(dev, BorneoPaths.nvsU32, ns, key, cancelToken: cancelToken);
  }

  @override
  Future<void> setFactoryNvsU32(Device dev, String ns, String key, int u32, {CancellationToken? cancelToken}) async {
    await _setFactoryNvs(dev, BorneoPaths.nvsU32, ns, key, u32, cancelToken: cancelToken);
  }

  @override
  Future<int> getFactoryNvsI8(Device dev, String ns, String key, {CancellationToken? cancelToken}) async {
    return await _getFactoryNvs(dev, BorneoPaths.nvsI8, ns, key, cancelToken: cancelToken);
  }

  @override
  Future<void> setFactoryNvsI8(Device dev, String ns, String key, int i8, {CancellationToken? cancelToken}) async {
    await _setFactoryNvs(dev, BorneoPaths.nvsI8, ns, key, i8, cancelToken: cancelToken);
  }

  @override
  Future<int> getFactoryNvsI16(Device dev, String ns, String key, {CancellationToken? cancelToken}) async {
    return await _getFactoryNvs(dev, BorneoPaths.nvsI16, ns, key, cancelToken: cancelToken);
  }

  @override
  Future<void> setFactoryNvsI16(Device dev, String ns, String key, int i16, {CancellationToken? cancelToken}) async {
    await _setFactoryNvs(dev, BorneoPaths.nvsI16, ns, key, i16, cancelToken: cancelToken);
  }

  @override
  Future<int> getFactoryNvsI32(Device dev, String ns, String key, {CancellationToken? cancelToken}) async {
    return await _getFactoryNvs(dev, BorneoPaths.nvsI32, ns, key, cancelToken: cancelToken);
  }

  @override
  Future<void> setFactoryNvsI32(Device dev, String ns, String key, int i32, {CancellationToken? cancelToken}) async {
    await _setFactoryNvs(dev, BorneoPaths.nvsI32, ns, key, i32, cancelToken: cancelToken);
  }

  @override
  Future<String> getFactoryNvsString(Device dev, String ns, String key, {CancellationToken? cancelToken}) async {
    return await _getFactoryNvsString(dev, BorneoPaths.nvsString, ns, key, cancelToken: cancelToken);
  }

  @override
  Future<bool> factoryNvsExists(Device dev, String ns, String key, {CancellationToken? cancelToken}) async {
    return await this.withQueue(dev, () async {
      final dd = dev.driverData as BorneoCoapDriverData;
      final uri = BorneoPaths.nvsExists.replace(queryParameters: {'ns': ns, 'k': key});
      return await dd.coap.getCbor<bool>(uri, cancelToken: cancelToken);
    }, cancelToken: cancelToken);
  }

  @override
  Future<void> setFactoryNvsString(
    Device dev,
    String ns,
    String key,
    String value, {
    CancellationToken? cancelToken,
  }) async {
    await _setFactoryNvsString(dev, BorneoPaths.nvsString, ns, key, value, cancelToken: cancelToken);
  }

  @override
  Future<List<int>> getFactoryNvsBlob(Device dev, String ns, String key, {CancellationToken? cancelToken}) async {
    return await _getFactoryNvsBlob(dev, BorneoPaths.nvsBlob, ns, key, cancelToken: cancelToken);
  }

  @override
  Future<void> setFactoryNvsBlob(
    Device dev,
    String ns,
    String key,
    List<int> value, {
    CancellationToken? cancelToken,
  }) async {
    await _setFactoryNvsBlob(dev, BorneoPaths.nvsBlob, ns, key, value, cancelToken: cancelToken);
  }
}
