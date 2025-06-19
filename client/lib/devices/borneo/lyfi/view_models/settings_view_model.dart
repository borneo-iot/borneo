import 'package:borneo_app/devices/borneo/lyfi/view_models/base_lyfi_device_view_model.dart';
import 'package:borneo_app/core/infrastructure/timezone.dart';
import 'package:borneo_app/core/services/i_app_notification_service.dart';
import 'package:borneo_common/exceptions.dart' as bo_ex;
import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:geolocator/geolocator.dart';

import 'package:latlong2/latlong.dart';

class SettingsViewModel extends BaseLyfiDeviceViewModel {
  final IAppNotificationService notification;
  final Uri address;
  final GeneralBorneoDeviceStatus borneoStatus;
  final GeneralBorneoDeviceInfo borneoInfo;
  final LyfiDeviceInfo ledInfo;
  final LyfiDeviceStatus ledStatus;

  ILyfiDeviceApi get api => deviceManager.getBoundDevice(deviceID).api<ILyfiDeviceApi>();
  GeoLocation? _location;
  GeoLocation? get location => _location;
  bool get canUpdateGeoLocation => !isBusy.value && isOnline;

  String? _timezone;
  String? get timezone => _timezone;
  bool get canUpdateTimezone => !isBusy.value && isOnline;

  LedCorrectionMethod _correctionMethod = LedCorrectionMethod.log;
  LedCorrectionMethod get correctionMethod => _correctionMethod;
  bool get canUpdateCorrectionMethod => !isBusy.value && isOnline;

  Duration _temporaryDuration = Duration(minutes: 20);
  Duration get temporaryDuration => _temporaryDuration;
  bool get canUpdateTemporaryDuration => !isBusy.value && isOnline;

  PowerBehavior _powerBehavior;
  PowerBehavior get powerBehavior => _powerBehavior;
  bool get canUpdatePowerBehavior => !isBusy.value && isOnline;

  SettingsViewModel({
    required super.deviceID,
    required super.deviceManager,
    required super.globalEventBus,
    required this.notification,
    required this.address,
    required this.borneoStatus,
    required this.borneoInfo,
    required this.ledInfo,
    required this.ledStatus,
    required GeoLocation? location,
    required PowerBehavior powerBehavior,
  }) : _location = location,
       _powerBehavior = powerBehavior,
       _timezone = borneoStatus.timezone;

  @override
  Future<void> onInitialize() async {
    _correctionMethod = await api.getCorrectionMethod(boundDevice!.device);
    _temporaryDuration = await api.getTemporaryDuration(boundDevice!.device);
  }

  Future<void> updateGeoLocation(LatLng location) async {
    super.enqueueUIJob(() async {
      /*
      final tzc = TimezoneConverter();
      await tzc.init();
      final device_posix_tz = await super.lyfiDeviceApi.getTimeZone(super.boundDevice!.device);
      final device_tz = await tzc.convertToIanaTimezone(device_posix_tz);
      final selected_tz = latLngToTimezoneString(location.latitude, location.longitude);
      final offset_enabled = device_tz != selected_tz;
      var offset = offset_enabled ? _getTimeDifference(device_tz!, selected_tz).inSeconds : 0;
      await super.lyfiDeviceApi.setTimeZoneEnabled(super.boundDevice!.device, offset_enabled);
      await super.lyfiDeviceApi.setTimeZoneOffset(super.boundDevice!.device, offset);

      //await super.lyfiDeviceApi.setTimeZoneOffset(super.boundDevice!.device, )
      */
      final loc = GeoLocation(lat: location.latitude, lng: location.longitude);
      await super.lyfiDeviceApi.setLocation(super.boundDevice!.device, loc);
      _location = loc;
      notification.showSuccess("Location updated successfully");
    });
  }

  /*
  Duration _getTimeDifference(String timezone1, String timezone2) {
    final location1 = tz.getLocation(timezone1);
    final location2 = tz.getLocation(timezone2);
    final now = tz.TZDateTime.now(location1);
    final offset1 = now.timeZoneOffset;
    final offset2 = tz.TZDateTime.now(location2).timeZoneOffset;
    return offset1 - offset2;
  }
  */

  Future<Position> getLocation({CancellationToken? cancel}) async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled().asCancellable(cancel);
    if (!serviceEnabled) {
      throw bo_ex.InvalidOperationException(message: 'Please enable location services');
    }

    // Check permissions
    permission = await Geolocator.checkPermission().asCancellable(cancel);
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission().asCancellable(cancel);
      if (permission == LocationPermission.denied) {
        throw bo_ex.PermissionDeniedException(message: 'Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw bo_ex.PermissionDeniedException(message: 'Location permissions are permanently denied');
    }

    // Get current position
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 30),
        distanceFilter: 100,
      ),
    ).asCancellable(cancel);

    return position;
  }

  Future<void> updateTimezone() async {
    super.enqueueUIJob(() async {
      notifyListeners();
      final tzc = TimezoneConverter();
      await tzc.init();
      final posixTZ = await tzc.getLocalPosixTimezone();
      await api.setTimeZone(boundDevice!.device, posixTZ!);
      _timezone = posixTZ;
      notification.showSuccess("Time zone updated successfully");
    });
  }

  Future<void> updateLedCorrectionMethod(LedCorrectionMethod newMethod) async {
    super.enqueueUIJob(() async {
      notifyListeners();
      await api.setCorrectionMethod(boundDevice!.device, newMethod);
      _correctionMethod = newMethod;
      notification.showSuccess("LED correction method updated successfully");
    });
  }

  Future<void> updateTemporaryDuration(Duration dur) async {
    super.enqueueUIJob(() async {
      notifyListeners();
      await api.setTemporaryDuration(boundDevice!.device, dur);
      _temporaryDuration = dur;
      notification.showSuccess("Temporary duration updated successfully");
    });
  }

  Future<void> updatePowerBehavior(PowerBehavior behavior) async {
    super.enqueueUIJob(() async {
      notifyListeners();
      await api.setPowerBehavior(boundDevice!.device, behavior);
      _powerBehavior = behavior;
      notification.showSuccess("Power behavior updated successfully");
    });
  }
}
