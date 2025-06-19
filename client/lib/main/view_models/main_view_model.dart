import 'dart:async';

import 'package:borneo_app/core/events/app_events.dart';
import 'package:borneo_app/core/services/blob_manager.dart';
import 'package:borneo_app/core/services/device_manager.dart';
import 'package:borneo_app/core/services/group_manager.dart';
import 'package:borneo_app/core/services/scene_manager.dart';
import 'package:borneo_app/core/services/local_service.dart';
import 'package:borneo_app/shared/view_models/base_view_model.dart';
import 'package:borneo_kernel_abstractions/events.dart';
import 'package:event_bus/event_bus.dart';

enum TabIndices { scenes, devices, my }

class MainViewModel extends BaseViewModel with ViewModelEventBusMixin, ViewModelInitFutureMixin {
  static final Duration kStartupScanningDuration = Duration(seconds: 5);
  final IBlobManager _blobManager;
  final SceneManager _sceneManager;
  final GroupManager _groupManager;
  final DeviceManager _deviceManager;
  final LocaleService _localeService;
  TabIndices _currentIndex = TabIndices.scenes;
  bool _isInitialized = false;

  DateTime? _lastPressedAt;
  bool _showExitPrompt = false;
  Timer? _exitTimer;

  bool get showExitPrompt => _showExitPrompt;

  late final StreamSubscription<AppErrorEvent> _appErrorEventSub;
  late final StreamSubscription<DeviceDiscoveringStartedEvent> _deviceDiscoveringStartedEventSub;
  late final StreamSubscription<DeviceDiscoveringStoppedEvent> _deviceDiscoveringStoppedEventSub;

  final List<AppErrorEvent> _errorsStack = [];

  String get errorMessage => _errorsStack.last.message;

  bool get hasError => _errorsStack.isNotEmpty;

  TabIndices get currentTabIndex => _currentIndex;

  bool get isInitialized => _isInitialized;

  String get currentSceneName => _isInitialized && _sceneManager.isInitialized ? _sceneManager.current.name : 'N/A';

  bool get isScanningDevices => _deviceManager.isDiscoverying;

  MainViewModel(
    EventBus globalEventBus,
    this._blobManager,
    this._sceneManager,
    this._groupManager,
    this._deviceManager,
    this._localeService, {
    super.logger,
  }) {
    this.globalEventBus = globalEventBus;
    _appErrorEventSub = globalEventBus.on<AppErrorEvent>().listen(_onAppError);
    _deviceDiscoveringStartedEventSub = _deviceManager.allDeviceEvents.on<DeviceDiscoveringStartedEvent>().listen(
      _onDeviceDiscoveringStarted,
    );
    _deviceDiscoveringStoppedEventSub = _deviceManager.allDeviceEvents.on<DeviceDiscoveringStoppedEvent>().listen(
      _onDeviceDiscoveringStopped,
    );
  }

  Future<void> initialize() async {
    assert(!isInitialized);
    logger?.i('Starting to initialize MainViewModel...');
    try {
      await _blobManager.initialize();
      await _sceneManager.initialize(_groupManager, _deviceManager);
      await _groupManager.initialize();
      await _deviceManager.initialize();
      await _localeService.initialize();
      logger?.i('MainViewModel initialized.');
    } finally {
      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    if (!isDisposed) {
      _exitTimer?.cancel();
      _appErrorEventSub.cancel();
      _errorsStack.clear();
      _deviceDiscoveringStartedEventSub.cancel();
      _deviceDiscoveringStoppedEventSub.cancel();
    }
    super.dispose();
  }

  void setIndex(TabIndices index) {
    _currentIndex = index;
    notifyListeners();
  }

  void clearError() {
    if (_errorsStack.isNotEmpty) {
      _errorsStack.removeLast();
      notifyListeners();
    }
  }

  void _onAppError(AppErrorEvent event) {
    if (_errorsStack.isEmpty || _errorsStack.last.error.runtimeType != event.error.runtimeType) {
      _errorsStack.add(event);
      notifyListeners();
    }
    logger?.e('APP_ERROR: ${event.message}', error: event.error, stackTrace: event.stackTrace);
  }

  void _onDeviceDiscoveringStarted(DeviceDiscoveringStartedEvent event) {
    if (!isDisposed && !isBusy.value) {
      notifyListeners();
    }
  }

  void _onDeviceDiscoveringStopped(DeviceDiscoveringStoppedEvent event) {
    if (!isDisposed && !isBusy.value) {
      notifyListeners();
    }
  }

  Future<bool> handleWillPop() async {
    final now = DateTime.now();

    if (_lastPressedAt == null || now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
      _lastPressedAt = now;
      _showExitPrompt = true;
      notifyListeners();

      _exitTimer?.cancel();
      _exitTimer = Timer(const Duration(seconds: 2), () {
        _showExitPrompt = false;
        notifyListeners();
      });

      return false;
    }

    return true;
  }
}
