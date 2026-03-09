import 'dart:async';

import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_app/core/services/devices/ble_provisioner.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/features/devices/models/ble_provision_state.dart';
import 'package:borneo_app/features/devices/models/events.dart';
import 'package:borneo_app/features/devices/providers/new_device_candidates_store.dart';
import 'package:borneo_app/shared/view_models/abstract_screen_view_model.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:flutter_esp_ble_prov/flutter_esp_ble_prov.dart';

/// Maximum number of seconds to wait for a registered device to appear on the
/// network after successful WiFi connection.  This is only used for the UI
/// countdown; the wizard will advance as soon as the device is detected.
const int kRegisterWaitSeconds = 30;

enum ProvisioningWizardStep { selectWifi, enterPassword, provisioning, done }

class ProvisioningWizardViewModel extends AbstractScreenViewModel {
  final IBleProvisioner _bleProvisioner;
  final IDeviceManager _deviceManager;
  final NewDeviceCandidatesStore _newDeviceCandidatesStore;
  final String deviceName;
  final IAppNotificationService? notificationService;

  /// Duration we will wait (for display) while registering the device on
  /// the network. Provided for testing.
  final int registerTimeoutSeconds;

  ProvisioningWizardStep _step = ProvisioningWizardStep.selectWifi;
  ProvisioningWizardStep get step => _step;

  // countdown timer used while registering device
  Timer? _registerTimer;
  int _registerRemainingSeconds = 0;
  int get registerRemainingSeconds => _registerRemainingSeconds;

  StreamSubscription<NewDeviceEntityAddedEvent>? _registerSub;

  // auto‑add tracking: true once a device has been successfully added during
  // the registration phase.  Exposed so UI can enable Done button.
  bool _autoAdded = false;
  bool get autoAdded => _autoAdded;

  String? _provisionedFingerprint;
  bool _isAutoAdding = false;

  List<WifiNetwork>? _networks;
  List<WifiNetwork>? get networks => _networks;

  String? _selectedSsid;
  String? get selectedSsid => _selectedSsid;

  BleProvisioningState _provisioningState = BleProvisioningState.idle;
  BleProvisioningState get provisioningState => _provisioningState;
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Whether provisioning succeeded (for the caller to know to refresh)
  bool _provisioningSucceeded = false;
  bool get provisioningSucceeded => _provisioningSucceeded;

  CancellationToken _cancelToken = CancellationToken();

  ProvisioningWizardViewModel(
    this._bleProvisioner,
    this._deviceManager,
    this._newDeviceCandidatesStore,
    this.deviceName, {
    required super.globalEventBus,
    required super.gt,
    super.logger,
    this.notificationService,
    this.registerTimeoutSeconds = kRegisterWaitSeconds,
  });

  @override
  Future<void> onInitialize() async {
    await scanNetworks();
  }

  Future<void> scanNetworks() async {
    isBusy = true;
    notifyListeners();
    try {
      _networks = await _bleProvisioner.scanWifiNetworks(deviceName, cancelToken: _cancelToken);
    } on CancelledException {
      logger?.i('The WiFi scanning has been cancelled.');
    } catch (e, stackTrace) {
      notifyAppError(gt.translate('Failed to scan  WiFi networks'), error: e, stackTrace: stackTrace);
    } finally {
      isBusy = false;
      if (!_cancelToken.isCancelled && !isDisposed) {
        notifyListeners();
      }
    }
  }

  void selectNetwork(String ssid) {
    _selectedSsid = ssid;
    _step = ProvisioningWizardStep.enterPassword;
    notifyListeners();
  }

  void backToWifiSelection() {
    _step = ProvisioningWizardStep.selectWifi;
    _selectedSsid = null;
    notifyListeners();
  }

  Future<void> startProvisioning(String password) async {
    _provisioningState = BleProvisioningState.idle;
    _errorMessage = null;
    _provisioningSucceeded = false;
    _step = ProvisioningWizardStep.provisioning;
    notifyListeners();

    isBusy = true;

    try {
      final info = await _bleProvisioner.fetchDeviceInfo(deviceName: deviceName, cancelToken: _cancelToken);
      _provisionedFingerprint = info.serno.isNotEmpty ? info.serno : null;

      _updateProvisioningState(BleProvisioningState.sendingCredentials);
      await _bleProvisioner.provisionWifi(deviceName, _selectedSsid!, password, cancelToken: _cancelToken);
      _updateProvisioningState(BleProvisioningState.connectingToWifi);

      _updateProvisioningState(BleProvisioningState.registeringDevice);
      _startRegisterTimer();
      _listenForRegisterEvent();
      _listenForCandidate();
    } on CancelledException {
      logger?.i('Provisioning cancelled.');
    } catch (e, stackTrace) {
      logger?.e('Provisioning failed', error: e, stackTrace: stackTrace);
      _errorMessage = e.toString();
      _updateProvisioningState(BleProvisioningState.failed);
      _step = ProvisioningWizardStep.done;
    } finally {
      isBusy = false;
      if (!_cancelToken.isCancelled && !isDisposed) {
        notifyListeners();
      }
    }
  }

  /// Retry from the beginning: back to WiFi scan.
  void retry() {
    _cancelRegisterTimer();
    _step = ProvisioningWizardStep.selectWifi;
    _selectedSsid = null;
    _provisioningState = BleProvisioningState.idle;
    _errorMessage = null;
    _provisioningSucceeded = false;
    // Create a fresh cancel token so the new scan/provision is not pre-cancelled.
    _cancelToken = CancellationToken();
    _provisionedFingerprint = null;
    _autoAdded = false;
    _isAutoAdding = false;
    _newDeviceCandidatesStore.removeListener(_onCandidatesChanged);
    notifyListeners();
    scanNetworks();
  }

  void _updateProvisioningState(BleProvisioningState state) {
    _provisioningState = state;
    notifyListeners();
  }

  void _startRegisterTimer() {
    _registerRemainingSeconds = registerTimeoutSeconds;
    _registerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _registerRemainingSeconds--;
      if (_registerRemainingSeconds <= 0) {
        // timeout does not change step; user may still press done later
        _cancelRegisterTimer();
      }
      notifyListeners();
    });
  }

  void _cancelRegisterTimer() {
    _registerTimer?.cancel();
    _registerTimer = null;
  }

  void _listenForRegisterEvent() {
    // listen for the moment the device actually makes it into the database.
    // once that happens we can transition the UI out of the provisioning step.
    _registerSub = _deviceManager.allDeviceEvents.on<NewDeviceEntityAddedEvent>().listen((event) {
      if (_provisionedFingerprint != null && event.device.fingerprint != _provisionedFingerprint) {
        return;
      }

      if (_step == ProvisioningWizardStep.provisioning) {
        _provisioningState = BleProvisioningState.success;
        _provisioningSucceeded = true;
        _step = ProvisioningWizardStep.done;
        _cancelRegisterTimer();
        _registerSub?.cancel();
        _newDeviceCandidatesStore.removeListener(_onCandidatesChanged);
        notifyListeners();
      }
    });
  }

  void _listenForCandidate() {
    _newDeviceCandidatesStore.removeListener(_onCandidatesChanged);
    _newDeviceCandidatesStore.addListener(_onCandidatesChanged);
    unawaited(_tryAutoAddFromCandidates());
  }

  void _onCandidatesChanged() {
    unawaited(_tryAutoAddFromCandidates());
  }

  Future<void> _tryAutoAddFromCandidates() async {
    if (_step != ProvisioningWizardStep.provisioning || _autoAdded || _isAutoAdding) {
      return;
    }

    final fingerprint = _provisionedFingerprint;
    if (fingerprint == null || fingerprint.isEmpty) {
      logger?.w('Provisioned device fingerprint is empty, cannot match discovery candidate.');
      return;
    }

    final candidate = _newDeviceCandidatesStore.byFingerprint(fingerprint);
    if (candidate == null) {
      return;
    }

    _isAutoAdding = true;
    try {
      _autoAdded = true;
      notifyListeners();
      await _deviceManager.addNewDevice(candidate);
    } catch (e, st) {
      _autoAdded = false;
      logger?.e('Auto-add during registration failed', error: e, stackTrace: st);
      notifyListeners();
    } finally {
      _isAutoAdding = false;
    }
  }

  @override
  void dispose() {
    if (isBusy) {
      _cancelToken.cancel();
    }
    _cancelRegisterTimer();
    _registerSub?.cancel();
    _newDeviceCandidatesStore.removeListener(_onCandidatesChanged);
    super.dispose();
  }
}
