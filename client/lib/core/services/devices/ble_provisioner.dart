import 'dart:async';

import 'package:borneo_common/exceptions.dart';
import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel_abstractions/models/prov.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:cbor/simple.dart' as simple_cbor;
import 'package:esp_ble_prov_dart/esp_ble_prov_dart.dart';
import 'package:flutter/foundation.dart';

abstract class IBleProvisioner {
  Future<List<String>> scanBleDevices(String prefix, {CancellationToken? cancelToken});
  Future<List<WiFiNetwork>> scanWifiNetworks(String deviceName, {String pop = '', CancellationToken? cancelToken});
  Future<void> provisionWifi(
    String deviceName,
    String ssid,
    String password, {
    WiFiNetwork? network,
    CancellationToken? cancelToken,
  });
  Future<GeneralBorneoDeviceInfo> fetchDeviceInfo({required String deviceName, CancellationToken? cancelToken});
  Future<void> closeDeviceSession(String deviceName);
}

class BleProvisioner implements IBleProvisioner {
  static const _customInfoEndpoint = 'cbor';
  static const _postDisconnectDelay = Duration(milliseconds: 800);
  static const _idleSessionTimeout = Duration(seconds: 90);
  static const _bleResponseTimeout = Duration(seconds: 20);
  static const _wifiScanTimeout = Duration(seconds: 45);
  static const _wifiScanPollInterval = Duration(seconds: 1);
  static const _wifiScanResultPageSize = 4;

  EspBleProvisioner? _activeProvisioner;
  String? _activeDeviceName;
  Timer? _activeDisconnectTimer;
  Future<void> _operationTail = Future<void>.value();

  BleProvisioner();

  @override
  Future<List<String>> scanBleDevices(String prefix, {CancellationToken? cancelToken}) async {
    final provisioner = _createProvisioner(deviceNamePrefix: prefix);
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
      keepAlive: true,
      action: (provisioner) => _scanWifiNetworks(provisioner, cancelToken: cancelToken),
    );
  }

  @override
  Future<void> provisionWifi(
    String deviceName,
    String ssid,
    String password, {
    WiFiNetwork? network,
    CancellationToken? cancelToken,
  }) async {
    await _withProvisioner(
      deviceName: deviceName,
      cancelToken: cancelToken,
      action: (provisioner) => provisioner.sendCredentials(
        WiFiConfig(ssid: ssid, passphrase: password, bssid: network?.bssid, channel: network?.channel ?? 0),
      ),
    );
  }

  @override
  Future<GeneralBorneoDeviceInfo> fetchDeviceInfo({required String deviceName, CancellationToken? cancelToken}) async {
    final request = ProvRequest(method: 1, id: DateTime.now().millisecondsSinceEpoch % 0xFFFFFF);
    final requestBuf = Uint8List.fromList(simple_cbor.cbor.encode(request.toMap()));
    final repBytes = await _withProvisioner(
      deviceName: deviceName,
      cancelToken: cancelToken,
      keepAlive: _hasActiveProvisioner(deviceName),
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

  @override
  Future<void> closeDeviceSession(String deviceName) async {
    await _runExclusive(() async {
      if (_activeDeviceName == deviceName) {
        await _closeActiveProvisioner();
      }
    });
  }

  Future<T> _withProvisioner<T>({
    required String deviceName,
    String pop = '',
    CancellationToken? cancelToken,
    bool keepAlive = false,
    required Future<T> Function(EspBleProvisioner provisioner) action,
  }) {
    return _runExclusive(
      () => _withProvisionerUnlocked(
        deviceName: deviceName,
        pop: pop,
        cancelToken: cancelToken,
        keepAlive: keepAlive,
        action: action,
      ),
    );
  }

  Future<T> _withProvisionerUnlocked<T>({
    required String deviceName,
    String pop = '',
    CancellationToken? cancelToken,
    bool keepAlive = false,
    required Future<T> Function(EspBleProvisioner provisioner) action,
  }) async {
    final activeProvisioner = _activeProvisioner;
    if (_activeDeviceName == deviceName && activeProvisioner != null && activeProvisioner.isConnected) {
      _activeDisconnectTimer?.cancel();
      try {
        final result = await action(activeProvisioner).asCancellable(cancelToken);
        if (keepAlive) {
          _scheduleActiveDisconnect();
        } else {
          await _closeActiveProvisioner();
        }
        return result;
      } catch (error, stackTrace) {
        await _closeActiveProvisioner();
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    // Do not leave a stale session object around when the connection stream
    // reported a disconnect before the next operation starts.
    if (activeProvisioner != null) {
      await _closeActiveProvisioner();
    }

    final provisioner = _createProvisioner(deviceNamePrefix: deviceName, pop: pop);
    var keepProvisionerOpen = false;
    try {
      final devices = await provisioner.scanDevices().asCancellable(cancelToken);
      final device = _findDeviceByName(devices, deviceName);
      if (device == null) {
        throw StateError('BLE device is not available: $deviceName');
      }
      await provisioner.connect(device: device).asCancellable(cancelToken);
      await provisioner.establishSession().asCancellable(cancelToken);
      final result = await action(provisioner).asCancellable(cancelToken);
      if (keepAlive) {
        _activeProvisioner = provisioner;
        _activeDeviceName = deviceName;
        keepProvisionerOpen = true;
        _scheduleActiveDisconnect();
      }
      return result;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (!keepProvisionerOpen) {
        await _disconnectProvisioner(provisioner);
      }
    }
  }

  bool _hasActiveProvisioner(String deviceName) {
    return _activeDeviceName == deviceName && _activeProvisioner != null && _activeProvisioner!.isConnected;
  }

  EspBleProvisioner _createProvisioner({required String deviceNamePrefix, String pop = ''}) {
    return EspBleProvisioner(
      deviceNamePrefix: deviceNamePrefix,
      security: Security1(pop: pop),
      mtu: 512,
      responseTimeout: _bleResponseTimeout,
      readRetryInterval: const Duration(milliseconds: 250),
      onLog: (message) => debugPrint('BLE provisioning: $message'),
    );
  }

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _operationTail = _operationTail.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<List<WiFiNetwork>> _scanWifiNetworks(EspBleProvisioner provisioner, {CancellationToken? cancelToken}) async {
    await provisioner.startScan().asCancellable(cancelToken);

    final deadline = DateTime.now().add(_wifiScanTimeout);
    WiFiScanStatus? status;
    while (DateTime.now().isBefore(deadline)) {
      status = await provisioner.getScanStatusDetails().asCancellable(cancelToken);
      if (status.scanFinished) {
        return _readWifiScanResults(provisioner, status.resultCount, cancelToken: cancelToken);
      }
      await Future<void>.delayed(_wifiScanPollInterval).asCancellable(cancelToken);
    }

    throw TimeoutException('WiFi scan timed out', _wifiScanTimeout);
  }

  Future<List<WiFiNetwork>> _readWifiScanResults(
    EspBleProvisioner provisioner,
    int resultCount, {
    CancellationToken? cancelToken,
  }) async {
    if (resultCount <= 0) {
      return const <WiFiNetwork>[];
    }

    final networks = <WiFiNetwork>[];
    for (var startIndex = 0; startIndex < resultCount; startIndex += _wifiScanResultPageSize) {
      final count = resultCount - startIndex;
      final page = await provisioner
          .getScanResults(
            startIndex: startIndex,
            count: count < _wifiScanResultPageSize ? count : _wifiScanResultPageSize,
          )
          .asCancellable(cancelToken);
      networks.addAll(page);
    }
    return networks;
  }

  void _scheduleActiveDisconnect() {
    _activeDisconnectTimer?.cancel();
    _activeDisconnectTimer = Timer(_idleSessionTimeout, () {
      unawaited(_closeActiveProvisioner());
    });
  }

  Future<void> _closeActiveProvisioner() async {
    _activeDisconnectTimer?.cancel();
    _activeDisconnectTimer = null;

    final provisioner = _activeProvisioner;
    _activeProvisioner = null;
    _activeDeviceName = null;

    if (provisioner != null) {
      await _disconnectProvisioner(provisioner);
    }
  }

  Future<void> _disconnectProvisioner(EspBleProvisioner provisioner) async {
    try {
      await provisioner.disconnect(timeout: const Duration(seconds: 5));
    } catch (_) {
      // Ignore cleanup errors so the provisioning operation reports the
      // original failure.
    }
    await Future<void>.delayed(_postDisconnectDelay);
  }

  EspBleDevice? _findDeviceByName(List<EspBleDevice> devices, String deviceName) {
    for (final device in devices) {
      if (device.name == deviceName) {
        return device;
      }
    }
    if (devices.length == 1) {
      return devices.single;
    }
    return null;
  }
}
