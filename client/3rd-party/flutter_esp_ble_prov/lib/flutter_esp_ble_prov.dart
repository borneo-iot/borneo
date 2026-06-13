import 'dart:typed_data';
import 'src/flutter_esp_ble_prov_platform_interface.dart';
import 'src/security_level.dart';
import 'src/wifi_network.dart';

export 'src/wifi_network.dart';
export 'src/security_level.dart';

/// Plugin provides core functionality to provision ESP32 devices over BLE
class FlutterEspBleProv {
  /// Security level for ESP provisioning.
  ///
  /// Defaults to [SecurityLevel.unsecure] to keep backward compatibility with
  /// firmware using SECURITY_0.
  final SecurityLevel defaultSecurity;

  FlutterEspBleProv({this.defaultSecurity = SecurityLevel.unsecure});

  /// Initiates a scan of BLE devices with the given [prefix].
  ///
  /// ESP32 Arduino demo defaults this value to "PROV_"
  Future<List<String>> scanBleDevices(String prefix) {
    return FlutterEspBleProvPlatform.instance.scanBleDevices(prefix);
  }

  /// Scan the available WiFi networks for the given [deviceName] and
  /// [proofOfPossession] string.
  ///
  /// Defaults to [SecurityLevel.unsecure]. When using SECURITY_1 or
  /// SECURITY_2, your firmware must be built accordingly and you must provide
  /// the proper proof of possession.
  Future<List<String>> scanWifiNetworks(
    String deviceName,
    String proofOfPossession, {
    SecurityLevel? security,
  }) {
    return FlutterEspBleProvPlatform.instance.scanWifiNetworks(
      deviceName,
      proofOfPossession,
      security ?? defaultSecurity,
    );
  }

  /// Scan the available WiFi networks with detailed information including RSSI
  /// for the given [deviceName] and [proofOfPossession] string.
  ///
  /// Defaults to [SecurityLevel.unsecure]. When using SECURITY_1 or
  /// SECURITY_2, your firmware must be built accordingly and you must provide
  /// the proper proof of possession.
  Future<List<WifiNetwork>> scanWifiNetworksWithDetails(
    String deviceName,
    String proofOfPossession, {
    SecurityLevel? security,
  }) {
    return FlutterEspBleProvPlatform.instance.scanWifiNetworksWithDetails(
      deviceName,
      proofOfPossession,
      security ?? defaultSecurity,
    );
  }

  /// Provision the named WiFi network at [ssid] with the given [passphrase] for
  /// the named device [deviceName] and [proofOfPossession] string.
  Future<bool?> provisionWifi(
    String deviceName,
    String proofOfPossession,
    String ssid,
    String passphrase, {
    SecurityLevel? security,
  }) {
    return FlutterEspBleProvPlatform.instance.provisionWifi(
      deviceName,
      proofOfPossession,
      ssid,
      passphrase,
      security ?? defaultSecurity,
    );
  }

  /// Send custom data to a custom endpoint on the device.
  Future<Uint8List?> sendDataToCustomEndPoint(
    String deviceName,
    String proofOfPossession,
    String path,
    Uint8List data, {
    SecurityLevel? security,
  }) {
    return FlutterEspBleProvPlatform.instance.sendDataToCustomEndPoint(
      deviceName,
      proofOfPossession,
      path,
      data,
      security ?? defaultSecurity,
    );
  }

  /// Returns the native platform version
  Future<String?> getPlatformVersion() {
    return FlutterEspBleProvPlatform.instance.getPlatformVersion();
  }
}
