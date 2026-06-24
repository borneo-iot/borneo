import 'dart:async';
import 'dart:typed_data';

import 'package:borneo_common/exceptions.dart';
import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel_abstractions/models/prov.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:cbor/simple.dart' as simple_cbor;
import 'package:esp_ble_prov_dart/esp_ble_prov_dart.dart';

abstract class IBleProvisioner {
  Future<List<String>> scanBleDevices(String prefix, {CancellationToken? cancelToken});
  Future<List<WiFiNetwork>> scanWifiNetworks(String deviceName, {String pop = '', CancellationToken? cancelToken});
  Future<void> provisionWifi(String deviceName, String ssid, String password, {CancellationToken? cancelToken});
  Future<GeneralBorneoDeviceInfo> fetchDeviceInfo({required String deviceName, CancellationToken? cancelToken});
}

class BleProvisioner implements IBleProvisioner {
  static const _customInfoEndpoint = 'cbor';

  BleProvisioner();

  @override
  Future<List<String>> scanBleDevices(String prefix, {CancellationToken? cancelToken}) async {
    final provisioner = EspBleProvisioner(
      deviceNamePrefix: prefix,
      security: Security1(pop: ''),
    );
    final devices = await provisioner.scanDevices().asCancellable(cancelToken);
    return devices.map((device) => device.name ?? device.id).toList(growable: false);
  }

  @override
  Future<List<WiFiNetwork>> scanWifiNetworks(
    String deviceName, {
    String pop = '',
    CancellationToken? cancelToken,
  }) async {
    return _withProvisioner(
      deviceName: deviceName,
      pop: pop,
      cancelToken: cancelToken,
      action: (provisioner) => provisioner.scan(),
    );
  }

  @override
  Future<void> provisionWifi(String deviceName, String ssid, String password, {CancellationToken? cancelToken}) async {
    await _withProvisioner(
      deviceName: deviceName,
      cancelToken: cancelToken,
      action: (provisioner) => provisioner.sendCredentials(WiFiConfig(ssid: ssid, passphrase: password)),
    );
  }

  @override
  Future<GeneralBorneoDeviceInfo> fetchDeviceInfo({required String deviceName, CancellationToken? cancelToken}) async {
    final request = ProvRequest(method: 1, id: DateTime.now().millisecondsSinceEpoch % 0xFFFFFF);
    final requestBuf = Uint8List.fromList(simple_cbor.cbor.encode(request.toMap()));
    final repBytes = await _withProvisioner(
      deviceName: deviceName,
      cancelToken: cancelToken,
      action: (provisioner) async {
        provisioner.registerCustomEndpoint(_customInfoEndpoint);
        await provisioner.writeValueToEndpoint(_customInfoEndpoint, requestBuf).asCancellable(cancelToken);
        await Future<void>.delayed(const Duration(milliseconds: 200)).asCancellable(cancelToken);
        return provisioner.readValueFromEndpoint(_customInfoEndpoint).asCancellable(cancelToken);
      },
    );

    final repMap = simple_cbor.cbor.decode(repBytes);
    final rep = ProvResponse.fromMap(repMap);
    if (rep.id != request.id) {
      throw InvalidDataException(message: 'Unmatched package ID: ${request.id}');
    }
    if (rep.errorCode != 0) {
      throw InvalidDataException(message: 'Failed to get device info, error=${rep.errorCode}');
    }
    if (rep.results == null) {
      throw InvalidDataException(message: 'Failed to get device info: `results` cannot be null');
    }
    return GeneralBorneoDeviceInfo.fromMap(rep.results);
  }

  Future<T> _withProvisioner<T>({
    required String deviceName,
    String pop = '',
    CancellationToken? cancelToken,
    required Future<T> Function(EspBleProvisioner provisioner) action,
  }) async {
    final securityCandidates = _securityCandidates(pop);
    Object? lastError;
    StackTrace? lastStackTrace;

    for (final security in securityCandidates) {
      final provisioner = EspBleProvisioner(deviceNamePrefix: deviceName, security: security);
      try {
        final devices = await provisioner.scanDevices().asCancellable(cancelToken);
        final device = _findDeviceByName(devices, deviceName);
        if (device == null) {
          throw StateError('BLE device is not available: $deviceName');
        }
        await provisioner.connect(device: device).asCancellable(cancelToken);
        await provisioner.establishSession().asCancellable(cancelToken);
        return await action(provisioner).asCancellable(cancelToken);
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
      } finally {
        await provisioner.disconnect();
      }
    }

    if (lastError != null) {
      Error.throwWithStackTrace(lastError, lastStackTrace!);
    }
    throw StateError('No BLE provisioning security candidates available for $deviceName');
  }

  EspBleDevice? _findDeviceByName(List<EspBleDevice> devices, String deviceName) {
    for (final device in devices) {
      if (device.name == deviceName) {
        return device;
      }
    }
    return null;
  }

  List<Security> _securityCandidates(String pop) {
    if (pop.isNotEmpty) {
      return [Security1(pop: pop)];
    }
    return [Security1(pop: ''), const Security0()];
  }
}
