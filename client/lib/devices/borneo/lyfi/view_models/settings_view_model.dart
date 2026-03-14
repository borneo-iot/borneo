import 'package:borneo_app/devices/borneo/lyfi/view_models/base_lyfi_device_view_model.dart';
import 'package:borneo_app/core/infrastructure/timezone.dart';
import 'package:borneo_common/exceptions.dart' as bo_ex;
import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';
import 'package:geolocator/geolocator.dart';

class SettingsViewModel extends BaseLyfiDeviceViewModel {
  final Uri address;
  final GeneralBorneoDeviceStatus borneoStatus;
  final GeneralBorneoDeviceInfo borneoInfo;
  final LyfiDeviceInfo ledInfo;
  final LyfiDeviceStatus ledStatus;
  GettextLocalizations get _gt => super.gt;

  ILyfiDeviceApi get api => deviceManager.getBoundDevice(deviceID).api<ILyfiDeviceApi>();

  GeoLocation? get location => lyfiThing.getProperty<GeoLocation?>('location');
  bool get canUpdateGeoLocation => !isBusy && isOnline && !isSuspectedOffline;

  String? _timezone;
  String? get timezone => _timezone;
  bool get canUpdateTimezone => !isBusy && isOnline && !isSuspectedOffline;

  LedCorrectionMethod _correctionMethod = LedCorrectionMethod.log;
  LedCorrectionMethod get correctionMethod => _correctionMethod;
  bool get canUpdateCorrectionMethod => !isBusy && isOnline && !isSuspectedOffline;

  Duration _temporaryDuration = Duration(minutes: 20);
  Duration get temporaryDuration => _temporaryDuration;
  bool get canUpdateTemporaryDuration => !isBusy && isOnline && !isSuspectedOffline;

  bool _cloudEnabled = false;
  bool get cloudEnabled => _cloudEnabled;
  bool get canUpdateCloudEnabled => !isBusy && isOnline && !isSuspectedOffline;

  FanMode _fanMode = FanMode.manual;
  FanMode get fanMode => _fanMode;
  bool get canUpdateFanMode => !isBusy && isOnline && !isSuspectedOffline;

  int _manualFanPower = 0;
  int get manualFanPower => _manualFanPower;
  bool get canUpdateManualFanPower => !isBusy && !isSuspectedOffline && isOnline && _fanMode == FanMode.manual;

  PowerBehavior _powerBehavior;
  PowerBehavior get powerBehavior => _powerBehavior;
  bool get canUpdatePowerBehavior => !isBusy && isOnline;
  bool get isControllerSettingsAvailable =>
      !isBusy && isOnline && !isSuspectedOffline && !isDemo && borneoInfo.productMode == ProductMode.standalone;

  SettingsViewModel({
    required super.deviceManager,
    required super.globalEventBus,
    required super.notification,
    required super.wotThing,
    required this.address,
    required this.borneoStatus,
    required this.borneoInfo,
    required this.ledInfo,
    required this.ledStatus,
    required PowerBehavior powerBehavior,
    required super.gt,
    super.logger,
  }) : _powerBehavior = powerBehavior,
       _timezone = borneoStatus.timezone;

  @override
  Future<void> onInitialize() async {
    await super.onInitialize();
    _correctionMethod = await api.getCorrectionMethod(boundDevice!.device, cancelToken: masterCancellation);
    _temporaryDuration = await api.getTemporaryDuration(boundDevice!.device, cancelToken: masterCancellation);
    _cloudEnabled = await api.getCloudEnabled(boundDevice!.device, cancelToken: masterCancellation);
    _fanMode = await api.getFanMode(boundDevice!.device, cancelToken: masterCancellation);
    _manualFanPower = await api.getFanManualPower(boundDevice!.device, cancelToken: masterCancellation);
  }

  Future<Position> getLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled().asCancellable(masterCancellation);
    if (!serviceEnabled) {
      throw bo_ex.InvalidOperationException(message: _gt.translate('Please enable location services'));
    }

    // Check permissions
    permission = await Geolocator.checkPermission().asCancellable(masterCancellation);
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission().asCancellable(masterCancellation);
      if (permission == LocationPermission.denied) {
        throw bo_ex.PermissionDeniedException(message: _gt.translate('Location permissions are denied'));
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw bo_ex.PermissionDeniedException(message: _gt.translate('Location permissions are permanently denied'));
    }

    // Get current position
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 30),
          distanceFilter: 100,
        ),
      ).asCancellable(masterCancellation);
      return position;
    } catch (e, st) {
      notifyAppError(_gt.translate("Failed to get location"), error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<void> updateGeoLocation(GeoLocation location) async {
    setBusy(true);
    try {
      await super.lyfiDeviceApi.setLocation(super.boundDevice!.device, location, cancelToken: masterCancellation);
      lyfiThing.findProperty('location')?.value.notifyOfExternalUpdate(location);
      notification.showSuccess(_gt.translate("Location updated successfully"));
    } catch (e, st) {
      await lyfiThing.sync(cancelToken: masterCancellation);
      notifyAppError(_gt.translate("Failed to update device location"), error: e, stackTrace: st);
    } finally {
      await lyfiThing.sync(cancelToken: masterCancellation);
      setBusy(false);
    }
  }

  Future<void> updateTimezone() async {
    isBusy = true;
    notifyListeners();
    try {
      final tzc = TimezoneConverter();
      await tzc.init();
      final posixTZ = await tzc.getLocalPosixTimezone();
      await api.setTimeZone(boundDevice!.device, posixTZ!, cancelToken: masterCancellation);
      _timezone = posixTZ;
      notification.showSuccess(_gt.translate("Time zone updated successfully"));
    } catch (e, st) {
      notifyAppError(_gt.translate("Failed to update device time zone"), error: e, stackTrace: st);
    } finally {
      await lyfiThing.sync(cancelToken: masterCancellation);
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> updateLedCorrectionMethod(LedCorrectionMethod newMethod) async {
    isBusy = true;
    notifyListeners();
    try {
      await api.setCorrectionMethod(boundDevice!.device, newMethod, cancelToken: masterCancellation);
      _correctionMethod = newMethod;
      notification.showSuccess(_gt.translate("LED correction method updated successfully"));
    } catch (e, st) {
      notifyAppError(_gt.translate("Failed to update LED correction method"), error: e, stackTrace: st);
    } finally {
      await lyfiThing.sync(cancelToken: masterCancellation);
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> updateTemporaryDuration(Duration dur) async {
    isBusy = true;
    notifyListeners();
    try {
      await api.setTemporaryDuration(boundDevice!.device, dur, cancelToken: masterCancellation);
      _temporaryDuration = dur;
      notification.showSuccess(_gt.translate("Temporary duration updated successfully"));
    } catch (e, st) {
      notifyAppError(_gt.translate("Failed to update temporary duration"), error: e, stackTrace: st);
    } finally {
      await lyfiThing.sync(cancelToken: masterCancellation);
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> updateCloudEnabled(bool enabled) async {
    isBusy = true;
    notifyListeners();
    try {
      await api.setCloudEnabled(boundDevice!.device, enabled, cancelToken: masterCancellation);
      _cloudEnabled = enabled;
      notification.showSuccess(_gt.translate("Cloud simulation mode updated successfully"));
    } catch (e, st) {
      notifyAppError(_gt.translate("Failed to update cloud simulation mode"), error: e, stackTrace: st);
    } finally {
      await lyfiThing.sync(cancelToken: masterCancellation);
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> updateFanMode(FanMode mode) async {
    isBusy = true;
    notifyListeners();
    try {
      await api.setFanMode(boundDevice!.device, mode, cancelToken: masterCancellation);
      _fanMode = mode;
      notification.showSuccess(_gt.translate("Fan mode updated successfully"));
    } catch (e, st) {
      notifyAppError(_gt.translate("Failed to update fan modee"), error: e, stackTrace: st);
    } finally {
      await lyfiThing.sync(cancelToken: masterCancellation);
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> updateManualFanPower(int power) async {
    isBusy = true;
    notifyListeners();
    try {
      await api.setFanManualPower(boundDevice!.device, power, cancelToken: masterCancellation);
      _manualFanPower = power;
      notification.showSuccess(_gt.translate("Manual fan power updated successfully"));
    } catch (e, st) {
      notifyAppError(_gt.translate("Failed to update manual fan power"), error: e, stackTrace: st);
    } finally {
      await lyfiThing.sync(cancelToken: masterCancellation);
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> updatePowerBehavior(PowerBehavior behavior) async {
    isBusy = true;
    notifyListeners();
    try {
      await api.setPowerBehavior(boundDevice!.device, behavior, cancelToken: masterCancellation);
      _powerBehavior = behavior;
      notification.showSuccess(_gt.translate("Power behavior updated successfully"));
    } catch (e, st) {
      notifyAppError(_gt.translate("Failed to update power behavior"), error: e, stackTrace: st);
    } finally {
      await lyfiThing.sync(cancelToken: masterCancellation);
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> updateName(String newName) async {
    isBusy = true;
    notifyListeners();
    try {
      await borneoDeviceApi.setName(boundDevice!.device, newName, cancelToken: masterCancellation);
      await deviceManager.update(deviceID, name: newName);
      notification.showSuccess(_gt.translate("Device name updated successfully"));
    } catch (e, st) {
      notifyAppError(_gt.translate("Failed to update device name"), error: e, stackTrace: st);
    } finally {
      await lyfiThing.sync(cancelToken: masterCancellation);
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> factoryReset() async {
    isBusy = true;
    notifyListeners();
    try {
      await api.factoryReset(boundDevice!.device);
      await deviceManager.delete(this.deviceID, cancelToken: masterCancellation);
      await Future.delayed(const Duration(milliseconds: 100)).asCancellable(masterCancellation);
    } catch (e, st) {
      notifyAppError(_gt.translate("Failed to restore device to factory settings"), error: e, stackTrace: st);
    } finally {
      await lyfiThing.sync();
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> networkReset() async {
    isBusy = true;
    notifyListeners();
    try {
      await api.networkReset(boundDevice!.device, cancelToken: masterCancellation);
      await deviceManager.delete(this.deviceID, cancelToken: masterCancellation);
      await Future.delayed(const Duration(milliseconds: 100)).asCancellable(masterCancellation);
    } catch (e, st) {
      notifyAppError(_gt.translate("Failed to reset device network settings"), error: e, stackTrace: st);
    } finally {
      await lyfiThing.sync();
      isBusy = false;
      notifyListeners();
    }
  }
}
