import 'dart:async';

import 'package:borneo_app/core/models/events.dart';
import 'package:borneo_app/core/services/device_manager.dart';
import 'package:borneo_app/core/services/i_app_notification_service.dart';
import 'package:borneo_app/core/services/routine_manager.dart';
import 'package:borneo_app/core/services/scene_manager.dart';
import 'package:borneo_app/core/models/scene_entity.dart';
import 'package:borneo_app/shared/view_models/base_view_model.dart';
import 'package:borneo_app/features/routines/view_models/routine_summary_view_model.dart';
import 'package:borneo_app/features/scenes/view_models/scene_summary_view_model.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/foundation.dart';

class ScenesViewModel extends BaseViewModel with ViewModelEventBusMixin, ViewModelInitFutureMixin {
  final List<SceneSummaryViewModel> _scenes = [];
  final SceneManager _sceneManager;
  final DeviceManager _deviceManager;
  final RoutineManager _routineManager;
  final IAppNotificationService _notification;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  late final StreamSubscription<CurrentSceneChangedEvent> _currentSceneChangedEventSub;
  late final StreamSubscription<SceneCreatedEvent> _sceneCreatedEventSub;
  late final StreamSubscription<SceneDeletedEvent> _sceneDeletedEventSub;
  late final StreamSubscription<SceneUpdatedEvent> _sceneUpdatedEventSub;

  List<SceneSummaryViewModel> get scenes => _scenes;

  final ValueNotifier<List<RoutineSummaryViewModel>> _routines = ValueNotifier<List<RoutineSummaryViewModel>>([]);
  ValueNotifier<List<RoutineSummaryViewModel>> get routines => _routines;

  final ValueNotifier<bool> _isRoutinesLoading = ValueNotifier<bool>(false);
  ValueNotifier<bool> get isRoutinesLoading => _isRoutinesLoading;

  ScenesViewModel(
    EventBus globalEventBus,
    this._sceneManager,
    this._deviceManager,
    this._routineManager,
    this._notification, {
    super.logger,
  }) {
    super.globalEventBus = globalEventBus;

    //event subscriptions
    _currentSceneChangedEventSub = super.globalEventBus.on<CurrentSceneChangedEvent>().listen(_onCurrentSceneChanged);

    _sceneCreatedEventSub = super.globalEventBus.on<SceneCreatedEvent>().listen(_onSceneCreated);
    _sceneDeletedEventSub = super.globalEventBus.on<SceneDeletedEvent>().listen(_onSceneDeleted);
    _sceneUpdatedEventSub = super.globalEventBus.on<SceneUpdatedEvent>().listen(_onSceneUpdated);
  }

  Future<void> initialize() async {
    assert(!isInitialized);
    super.setBusy(true);
    try {
      await _reload();
    } finally {
      super.setBusy(false);
      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    if (!super.isDisposed) {
      _currentSceneChangedEventSub.cancel();
      _sceneCreatedEventSub.cancel();
      _sceneDeletedEventSub.cancel();
      _sceneUpdatedEventSub.cancel();
      super.dispose();
    }
  }

  Future<void> _reload() async {
    for (final sceneViewModel in _scenes) {
      sceneViewModel.dispose();
    }
    _scenes.clear();

    final scenes = await _sceneManager.all();

    final sceneViewModels = <SceneSummaryViewModel>[];

    for (final scene in scenes) {
      final deviceStat = await _sceneManager.getDeviceStatistics(_sceneManager.current.id);
      final vm = SceneSummaryViewModel(scene, globalEventBus, _sceneManager, _deviceManager, deviceStat);
      sceneViewModels.add(vm);

      _reloadRoutines();
    }

    sceneViewModels.sort((a, b) {
      if (a.model.isCurrent && !b.model.isCurrent) {
        return -1;
      } else if (!a.model.isCurrent && b.model.isCurrent) {
        return 1;
      } else {
        return b.model.lastAccessTime.compareTo(a.model.lastAccessTime);
      }
    });

    _scenes.addAll(sceneViewModels);
  }

  void _reloadRoutines() async {
    _isRoutinesLoading.value = true;
    final routines = _routineManager.getAvailableRoutines();
    for (final r in _routines.value) {
      r.dispose();
    }
    _routines.value = routines
        .map((r) => RoutineSummaryViewModel(r, _routineManager, _notification, logger: super.logger))
        .toList();
    _isRoutinesLoading.value = false;
  }

  Future<void> switchCurrentScene(String newSceneID) async {
    assert(!isBusy.value && _isInitialized);

    if (newSceneID == _sceneManager.current.id) {
      return;
    }

    super.setBusy(true);
    try {
      await _sceneManager.changeCurrent(newSceneID);
    } finally {
      super.setBusy(false);
    }
  }

  void _onCurrentSceneChanged(CurrentSceneChangedEvent event) {
    assert(!isDisposed);
    doSceneChanged(event.from, event.to);
  }

  void _onSceneDeleted(SceneDeletedEvent event) {
    if (isBusy.value) {
      return;
    }
    _reload().then((_) => notifyListeners());
  }

  void _onSceneUpdated(SceneUpdatedEvent event) {
    /*
    if (isBusy.value) {
      return;
    }
    for (final svm in _scenes) {
      if (svm.id == event.scene.id) {
        svm.notifyListeners();
        break;
      }
    }
    */
  }

  Future<void> doSceneChanged(SceneEntity from, SceneEntity to) async {
    assert(!isDisposed);
    for (final scene in _scenes) {
      scene.notifyListeners();
    }
    _reloadRoutines();
  }

  void _onSceneCreated(SceneCreatedEvent event) {
    if (isBusy.value) {
      return;
    }
    _reload().then((_) => notifyListeners());
  }
}
