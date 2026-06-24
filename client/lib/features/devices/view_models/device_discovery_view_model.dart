import 'dart:async';
import 'package:flutter/services.dart';
import 'package:borneo_app/features/devices/models/discoverable_device.dart';
import 'package:borneo_app/features/devices/providers/new_device_candidates_store.dart';
import 'package:borneo_app/core/services/devices/device_module_registry.dart';
import 'package:borneo_app/shared/view_models/abstract_screen_view_model.dart';
import 'package:borneo_kernel_abstractions/models/supported_device_descriptor.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:borneo_app/core/services/platform_service.dart';

import '../models/events.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/core/services/devices/ble_provisioner.dart';

const int kDiscoveryTimeoutSeconds = 30;

class DeviceDiscoveryViewModel extends AbstractScreenViewModel {
  bool _disposed = false;
  late CancellationToken _scanCancelToken = CancellationToken();
  Timer? _countdownTimer;
  int _remainingSeconds = kDiscoveryTimeoutSeconds;
  final Logger _logger;
  final IDeviceManager _deviceManager;
  final NewDeviceCandidatesStore _newDeviceCandidatesStore;
  final IBleProvisioner _bleProvisioner;
  final IDeviceModuleRegistry deviceMdoules;
  final PlatformService _platformService;

  // cache BLE name -> resolved device name as obtained via fetchDeviceInfo
  final Map<String, String> _resolvedDeviceNames = {};

  bool get _isDiscovering => _deviceManager.isDiscoverying;
  bool _isRefreshing = false;

  late final StreamSubscription<NewDeviceEntityAddedEvent> _deviceAddedEventSub;

  // Internal lists
  final List<String> _unprovisioned = [];

  // Exposed list
  final ValueNotifier<List<DiscoverableDevice>> _discoverableDevices = ValueNotifier([]);
  ValueNotifier<List<DiscoverableDevice>> get discoverableDevices => _discoverableDevices;

  final ValueNotifier<String?> _scanError = ValueNotifier(null);
  ValueNotifier<String?> get scanError => _scanError;

  bool get isDiscovering => _isRefreshing;
  int get remainingSeconds => _remainingSeconds;

  // Platform checks
  bool get isMobile => _platformService.isMobile;
  bool get supportsBleProvisioning => true;

  DeviceDiscoveryViewModel(
    this._logger,
    this._deviceManager,
    this._newDeviceCandidatesStore,
    this._bleProvisioner,
    this.deviceMdoules,
    this._platformService, {
    required super.globalEventBus,
    required super.gt,
    super.logger,
    // helper for testing permission error handling
    this.requestBlePermissions,
  }) {
    _deviceAddedEventSub = _deviceManager.allDeviceEvents.on<NewDeviceEntityAddedEvent>().listen(
      (event) => _onNewDeviceEntityAdded(event),
    );
    _newDeviceCandidatesStore.addListener(_onCandidatesChanged);
  }

  @override
  Future<void> onInitialize() async {
    try {
      await Future.delayed(Duration.zero);
      _updateDiscoverableList();
      await startDiscovery();
    } finally {}
  }

  @override
  void dispose() {
    if (!_disposed) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      _deviceAddedEventSub.cancel();
      _newDeviceCandidatesStore.removeListener(_onCandidatesChanged);
      _discoverableDevices.dispose();
      _scanError.dispose();
      if (_isRefreshing || _isDiscovering) {
        _scanCancelToken.cancel();
      }
      super.dispose();
      _disposed = true;
    }
  }

  Future<void> _stopRefresh() async {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _remainingSeconds = kDiscoveryTimeoutSeconds;
    _isRefreshing = false;
    _scanCancelToken.cancel();

    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> stopDiscovery() async {
    await _stopRefresh();

    if (_deviceManager.isDiscoverying) {
      await _deviceManager.stopDiscovery();
    }
  }

  // Clean resources when leaving screen or stopping
  Future<bool> onWillPop() async {
    await _stopRefresh();
    return true;
  }

  /// Begins a UI discovery session. mDNS itself is managed globally by the
  /// app lifecycle; this method refreshes the page state and optionally runs
  /// BLE discovery on supported platforms.
  Future<void> startDiscovery() async {
    if (_isRefreshing) return; // Already refreshing

    // reset resolved name cache when starting a fresh scan
    _resolvedDeviceNames.clear();

    // Create new cancellation token for this operation
    _scanCancelToken = CancellationToken();

    if (_deviceManager.isDiscoverying) {
      await _deviceManager.stopDiscovery();
    }
    await _deviceManager.startDiscovery(cancelToken: _scanCancelToken);

    // Clear session-scoped BLE results only.
    _unprovisioned.clear();
    _scanError.value = null; // Clear previous error
    _updateDiscoverableList();

    _isRefreshing = true;
    _remainingSeconds = kDiscoveryTimeoutSeconds;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      _remainingSeconds--;
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _countdownTimer = null;
        stopDiscovery();
      } else {
        notifyListeners();
      }
    });
    if (!_disposed) {
      notifyListeners(); // Update UI to show loading
    }

    try {
      // Ensure global mDNS discovery is active.

      await _beginBleScan();

      if (_scanCancelToken.isCancelled) {
        return;
      }
    } on CancelledException {
      _logger.i('Device discovery has been cancelled.');
    } catch (e, stackTrace) {
      if (_scanCancelToken.isCancelled) return;
      _logger.e('Discovery error', error: e, stackTrace: stackTrace);
      if (!_disposed) {
        _scanError.value = gt.translate('Bluetooth scan error, please check if Bluetooth device is enabled.');
      }
    }
  }

  /// Requests the set of permissions required for BLE discovery and
  /// returns `true` if all of them are granted. This method is deliberately
  /// public so that tests can supply a fake implementation.
  Future<bool> Function()? requestBlePermissions;

  @visibleForTesting
  List<Permission> blePermissionList() {
    if (!_platformService.isAndroid && !_platformService.isIOS) {
      return const [];
    }

    // iOS only has a single Bluetooth permission; Android requires location +
    // separate scan/connect permissions.  The list is kept in a method so tests
    // can verify the behaviour without mocking the plugin itself.
    if (_platformService.isIOS) {
      return [
        Permission.bluetooth,
        // location may also be required when scanning on iOS
        Permission.locationWhenInUse,
      ];
    } else {
      return [Permission.locationWhenInUse, Permission.bluetoothScan, Permission.bluetoothConnect];
    }
  }

  Future<bool> _ensureBlePermissions() async {
    // allow injection for tests
    if (requestBlePermissions != null) {
      return await requestBlePermissions!();
    }

    final permissions = blePermissionList();
    if (permissions.isEmpty) {
      return true;
    }

    final statuses = await permissions.request();
    _logger.d('BLE permission statuses: $statuses');

    // if any permission is not granted, treat as failure
    for (var status in statuses.values) {
      if (!status.isGranted) {
        return false;
      }
    }
    return true;
  }

  Future<void> _beginBleScan() async {
    final granted = await _ensureBlePermissions();
    if (!granted) {
      if (!_disposed) {
        _scanError.value = gt.translate('Bluetooth permissions are required to discover devices.');
      }
      return;
    }

    unawaited(
      _startBleScan().catchError((error, stackTrace) {
        _logger.e('BLE scan error', error: error, stackTrace: stackTrace);
        if (!_disposed) {
          _scanError.value = gt.translate('Bluetooth scan error, please check if Bluetooth device is enabled.');
        }
      }),
    );
  }

  Future<void> _startBleScan() async {
    try {
      final devices = await _bleProvisioner.scanBleDevices('BOPROV_', cancelToken: _scanCancelToken);
      _unprovisioned.clear();
      _unprovisioned.addAll(devices);
      _updateDiscoverableList();

      for (final name in devices) {
        if (_scanCancelToken.isCancelled) {
          break;
        }
        try {
          _logger.d('Fetching device info for BLE device: `$name`');
          final info = await _bleProvisioner.fetchDeviceInfo(deviceName: name, cancelToken: _scanCancelToken);
          if (info.name.isNotEmpty) {
            _resolvedDeviceNames[name] = info.name;
            _updateDiscoverableList();
          } else {
            _logger.w('Resolved info had empty name for $name, keeping BLE name');
          }
        } on CancelledException {
          rethrow;
        } catch (e, stackTrace) {
          _logger.w('Failed to resolve BLE device info for $name; keeping BLE name', error: e, stackTrace: stackTrace);
        }
      }
    } on CancelledException {
      _logger.w('BLE scan was cancelled by user.');
      if (!_disposed && _scanCancelToken.isCancelled) {
        await stopDiscovery();
      }
      return;
    } catch (e, stackTrace) {
      _logger.e('BLE provisioning scan failed', error: e, stackTrace: stackTrace);
      if (!_disposed) {
        if (e is PlatformException && e.code == 'PERMISSION_DENIED') {
          _scanError.value = gt.translate('Bluetooth permissions are required to discover devices.');
        } else {
          _scanError.value = gt.translate('Bluetooth scan error, please check if Bluetooth device is enabled.');
        }
      }
    }
  }

  Future<void> addNewDevice(SupportedDeviceDescriptor deviceInfo) async {
    if (this.isDisposed) {
      return;
    }

    try {
      await _deviceManager.addNewDevice(deviceInfo, groupID: null);
    } finally {}
  }

  Future<void> _onNewDeviceEntityAdded(NewDeviceEntityAddedEvent event) async {
    try {
      _updateDiscoverableList();
    } finally {
      if (!this.isDisposed) {
        notifyListeners();
      }
    }
  }

  void _onCandidatesChanged() {
    if (!_disposed) {
      _updateDiscoverableList();
      notifyListeners();
    }
  }

  void _updateDiscoverableList() {
    List<DiscoverableDevice> list = [];

    // Provisioned first
    list.addAll(_newDeviceCandidatesStore.candidates.map((d) => DiscoverableDevice.provisioned(d)));

    // Unprovisioned second; include any resolved names we have cached
    list.addAll(
      _unprovisioned.map((name) => DiscoverableDevice.unprovisioned(name, resolvedName: _resolvedDeviceNames[name])),
    );

    _discoverableDevices.value = list;
  }
}
