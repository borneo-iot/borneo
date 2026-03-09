import 'dart:async';
import 'package:borneo_app/core/services/devices/ble_provisioner.dart';
import 'package:borneo_app/features/devices/models/ble_provision_state.dart';
import 'package:borneo_app/shared/view_models/abstract_screen_view_model.dart';
import 'package:cancellation_token/cancellation_token.dart';

class ProvisioningProgressViewModel extends AbstractScreenViewModel {
  final IBleProvisioner _bleProvisioner;
  final String deviceName;
  final String ssid;
  final String password;

  BleProvisioningState _state = BleProvisioningState.idle;
  BleProvisioningState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  final CancellationToken _provCancel = CancellationToken();

  ProvisioningProgressViewModel(
    this._bleProvisioner,
    this.deviceName,
    this.ssid,
    this.password, {
    required super.globalEventBus,
    required super.gt,
    super.logger,
  });

  @override
  void dispose() {
    if (isBusy) {
      _provCancel.cancel();
    }
    super.dispose();
  }

  @override
  Future<void> onInitialize() async {
    // No-op or we could move startProvisioning here
  }

  Future<void> startProvisioning() async {
    if (isBusy || _state != BleProvisioningState.idle) {
      return;
    }

    isBusy = true;
    try {
      _updateState(BleProvisioningState.sendingCredentials);

      await _bleProvisioner.provisionWifi(deviceName, ssid, password, cancelToken: _provCancel);

      _updateState(BleProvisioningState.connectingToWifi);

      isBusy = false;
      _updateState(BleProvisioningState.success);
    } on CancelledException {
      logger?.i('The provisioning task has been cancelled.');
      isBusy = false;
      if (!super.isDisposed) {
        _updateState(BleProvisioningState.failed);
      }
    } catch (e, stackTrace) {
      logger?.e('Provisioning failed', error: e, stackTrace: stackTrace);
      if (!super.isDisposed) {
        _errorMessage = e.toString();
        isBusy = false;
        _updateState(BleProvisioningState.failed);
      }
    }
  }

  void _updateState(BleProvisioningState newState) {
    _state = newState;
    notifyListeners();
  }
}
