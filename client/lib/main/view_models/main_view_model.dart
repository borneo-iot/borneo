import 'dart:async';

import 'package:borneo_app/core/events/app_events.dart';
import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_app/core/services/blob_manager.dart';
import 'package:borneo_app/core/services/clock.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/core/services/group_manager.dart';
import 'package:borneo_app/core/services/scene_manager.dart';
import 'package:borneo_app/core/services/local_service.dart';
import 'package:borneo_app/shared/view_models/base_view_model.dart';
import 'package:borneo_kernel_abstractions/events.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';

enum TabIndices { scenes, devices, my }

class MainViewModel extends BaseViewModel with ViewModelEventBusMixin, ViewModelInitFutureMixin {
  static final Duration kStartupScanningDuration = Duration(seconds: 5);
  final IBlobManager _blobManager;
  final ISceneManager _sceneManager;
  final IGroupManager _groupManager;
  final IDeviceManager _deviceManager;
  final ILocaleService _localeService;
  final IClock clock;
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

  final IAppNotificationService notification;
  final GettextLocalizations _gt;

  MainViewModel(
    EventBus globalEventBus,
    this._blobManager,
    this._sceneManager,
    this._groupManager,
    this._deviceManager,
    this._localeService,
    this._gt, {
    required this.notification,
    required this.clock,
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
    if (_isInitialized) {
      return;
    }
    logger?.i('Starting to initialize MainViewModel...');
    try {
      await _blobManager.initialize();
      await _sceneManager.initialize(_groupManager, _deviceManager);
      await _groupManager.initialize();
      await _deviceManager.initialize();
      await _localeService.initialize();
      logger?.i('MainViewModel initialized.');
    } catch (e, stackTrace) {
      logger?.e("Failed to initialize MainViewModel: $e", error: e, stackTrace: stackTrace);
    } finally {
      _isInitialized = true;
      if (!isDisposed) {
        notifyListeners();
      }
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
    final isDuplicate = _errorsStack.isNotEmpty && _errorsStack.last.message == event.message;
    if (event.allowDuplicates || !isDuplicate) {
      _errorsStack.add(event);
      notification.showError(_gt.translate("ERROR"), body: event.message);
    }
    logger?.e('APP_ERROR: ${event.message}', error: event.error, stackTrace: event.stackTrace);
  }

  void _onDeviceDiscoveringStarted(DeviceDiscoveringStartedEvent event) {
    if (!isDisposed && !isBusy) {
      notifyListeners();
    }
  }

  void _onDeviceDiscoveringStopped(DeviceDiscoveringStoppedEvent event) {
    if (!isDisposed && !isBusy) {
      notifyListeners();
    }
  }

  Future<bool> handleWillPop() async {
    final now = clock.now();

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
