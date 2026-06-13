import 'dart:async';
import 'dart:typed_data';
import 'package:borneo_common/exceptions.dart';
import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel_abstractions/models/prov.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:cbor/simple.dart' as simple_cbor;
import 'package:flutter_esp_ble_prov/flutter_esp_ble_prov.dart';

abstract class IBleProvisioner {
  Future<List<String>> scanBleDevices(String prefix, {CancellationToken? cancelToken});
  Future<List<WifiNetwork>> scanWifiNetworks(String deviceName, {String pop = '', CancellationToken? cancelToken});
  Future<void> provisionWifi(String deviceName, String ssid, String password, {CancellationToken? cancelToken});
  Future<GeneralBorneoDeviceInfo> fetchDeviceInfo({required String deviceName, CancellationToken? cancelToken});
}

class BleProvisioner implements IBleProvisioner {
  final _plugin = FlutterEspBleProv(defaultSecurity: SecurityLevel.unsecure);

  BleProvisioner();

  @override
  Future<List<String>> scanBleDevices(String prefix, {CancellationToken? cancelToken}) async {
    // The scanBleDevices returns List<String> which are device names properly prefixed.
    final devices = await _plugin.scanBleDevices(prefix).asCancellable(cancelToken);
    return devices;
  }

  @override
  Future<List<WifiNetwork>> scanWifiNetworks(
    String deviceName, {
    String pop = '',
    CancellationToken? cancelToken,
  }) async {
    // According to documentation, this returns List<String> of SSIDs.
    // We pass empty string as proofOfPossession for devices without PoP.
    return await _plugin.scanWifiNetworksWithDetails(deviceName, pop).asCancellable(cancelToken);
  }

  @override
  Future<void> provisionWifi(String deviceName, String ssid, String password, {CancellationToken? cancelToken}) async {
    final result = await _plugin.provisionWifi(deviceName, '', ssid, password).asCancellable(cancelToken);
    if (result != true) {
      throw StateError('Provisioning failed');
    }
  }

  @override
  Future<GeneralBorneoDeviceInfo> fetchDeviceInfo({required String deviceName, CancellationToken? cancelToken}) async {
    final request = ProvRequest(method: 1, id: DateTime.now().millisecondsSinceEpoch % 0xFFFFFF);
    final requestBuf = Uint8List.fromList(simple_cbor.cbor.encode(request.toMap()));
    final repBytes = await _plugin
        .sendDataToCustomEndPoint(deviceName, '', 'cbor', requestBuf)
        .asCancellable(cancelToken);
    if (repBytes != null) {
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
    } else {
      throw InvalidDataException(message: 'Failed to parse device CBOR info');
    }
  }
}
