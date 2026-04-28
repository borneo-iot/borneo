abstract class AppRoutes {
  static const kMainScreen = '/';
  static const kScreens = '/scenes';
  static const kGroups = '/groups';
  static const kDevices = '/devices';
  static const kAccount = '/account';
  static const kDeviceDiscovery = '/devices/discovery';
  static const kDeviceDiscoveryWifiSelection = '/devices/discovery/wifi-selection';
  static const kDeviceDiscoveryProvisioning = '/devices/discovery/provisioning';

  static String makeDeviceScreenRoute(String driverID, [String? deviceID]) {
    if (driverID.isEmpty) {
      throw ArgumentError('The argument cannot be empty', 'driverID');
    }
    if (deviceID == null || deviceID.isEmpty) {
      return '/devices/$driverID';
    }
    return '/devices/$driverID/$deviceID';
  }
}
