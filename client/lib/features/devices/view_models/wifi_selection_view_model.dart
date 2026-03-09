import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_app/core/services/devices/ble_provisioner.dart';
import 'package:borneo_app/shared/view_models/abstract_screen_view_model.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:flutter_esp_ble_prov/flutter_esp_ble_prov.dart';

class WifiSelectionViewModel extends AbstractScreenViewModel {
  final IBleProvisioner _bleProvisioner;
  final String deviceName;
  final IAppNotificationService? notificationService;

  List<WifiNetwork>? _networks;
  List<WifiNetwork>? get networks => _networks;
  final CancellationToken _scanCancelToken = CancellationToken();

  WifiSelectionViewModel(
    this._bleProvisioner,
    this.deviceName, {
    required super.globalEventBus,
    required super.gt,
    super.logger,
    this.notificationService,
  });

  @override
  Future<void> onInitialize() async {
    await scanNetworks();
  }

  Future<void> scanNetworks() async {
    isBusy = true;
    notifyListeners();
    try {
      /*
      var deviceInfoPayload = await _bleProvisioner.fetchDeviceInfo(
        deviceName: deviceName,
        cancelToken: _scanCancelToken,
      );
      Future.delayed(Duration(milliseconds: 500)).asCancellable(_scanCancelToken);
      */
      // Assuming PoP is empty string as decided
      _networks = await _bleProvisioner.scanWifiNetworks(deviceName, cancelToken: _scanCancelToken);
    } on CancelledException {
      this.notificationService?.showWarning(super.gt.translate('The WiFi scanning has been cancelled.'));
    } catch (e, stackTrace) {
      notifyAppError(gt.translate('Failed to scan WiFi networks'), error: e, stackTrace: stackTrace);
    } finally {
      isBusy = false;
      if (!_scanCancelToken.isCancelled && !super.isDisposed) {
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (isBusy) {
      _scanCancelToken.cancel();
    }
    super.dispose();
  }
}
