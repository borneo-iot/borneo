import 'package:borneo_app/core/models/events.dart';
import 'package:borneo_app/core/services/chore_manager.dart';
import 'package:borneo_app/core/services/clock.dart';
import 'package:borneo_app/core/services/scene_manager.dart';
import 'package:borneo_app/features/chores/models/abstract_chore.dart';
import 'package:borneo_app/features/chores/models/builtin_chores.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/core/services/chore_history_store.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_gettext/flutter_gettext.dart';
import 'package:logger/logger.dart';
import 'package:sembast/sembast.dart';
import 'package:synchronized/synchronized.dart';

final class ChoreManagerImpl implements IChoreManager {
  final GettextLocalizations gettext;
  final Logger? logger;
  final IClock clock;

  // ignore: unused_field
  final Database _db;

  final _opLock = Lock();

  // ignore: unused_field
  final EventBus _globalBus;

  final ISceneManager _sceneManager;
  final IDeviceManager _deviceManager;

  final ChoreHistoryStore _historyStore;

  final List<AbstractChore> allChores = [];

  ChoreManagerImpl(
    this._globalBus,
    this._db,
    this._sceneManager,
    this._deviceManager, {
    required this.clock,
    required this.gettext,
    this.logger,
  }) : _historyStore = ChoreHistoryStore(_db) {
    allChores.addAll([
      PowerOffAllChore(name: gettext.translate('Power Off All')),
      FeedModeChore(name: gettext.translate('Feed Mode')),
      WaterChangeModeChore(name: gettext.translate('Water Change Mode')),
      DryScapeModeChore(name: gettext.translate('Dry Scape Mode')),
    ]);

    // Subscribe to device reload events and publish a ChoresChangedEvent so UI can refresh
    _globalBus.on<CurrentSceneDevicesReloadedEvent>().listen((event) {
      _globalBus.fire(ChoresChangedEvent(event.scene));
    });
  }

  @override
  List<AbstractChore> getAvailableChores() {
    List<AbstractChore> chores = [];
    final currentScene = _sceneManager.current;

    logger?.d('Getting available chores for scene: ${currentScene.name} (${currentScene.id})');

    for (final r in allChores) {
      final isAvailable = r.checkAvailable(currentScene, _deviceManager);
      logger?.d('  Chore ${r.name}: ${isAvailable ? "available" : "not available"}');
      if (isAvailable) {
        chores.add(r);
      }
    }

    logger?.d('Total available chores: ${chores.length}');
    return chores;
  }

  @override
  Future<void> executeChore(String choreId) async {
    await _opLock.synchronized(() async {
      final chore = allChores.singleWhere((r) => r.id == choreId);
      final currentScene = _sceneManager.current;
      await _undoMutuallyExclusiveChores(chore);
      final steps = await chore.execute(currentScene, _deviceManager);
      if (steps.isNotEmpty) {
        await _historyStore.addRecord(ChoreHistoryRecord(choreId: choreId, timestamp: this.clock.now(), steps: steps));
      }
      _globalBus.fire(ChoresChangedEvent(currentScene));
    });
  }

  @override
  Future<void> undoChore(String choreId) async {
    await _opLock.synchronized(() async {
      await _undoChoreById(choreId);
      _globalBus.fire(ChoresChangedEvent(_sceneManager.current));
    });
  }

  @override
  Future<bool> hasHistoryForChore(String choreId) async {
    return await _historyStore.hasHistoryForChore(choreId);
  }

  Future<void> _undoMutuallyExclusiveChores(AbstractChore chore) async {
    for (final other in allChores) {
      if (!chore.isMutuallyExclusiveWith(other)) {
        continue;
      }

      final hasHistory = await _historyStore.hasHistoryForChore(other.id);
      if (!hasHistory) {
        continue;
      }

      await _undoChoreById(other.id);
    }
  }

  Future<void> _undoChoreById(String choreId) async {
    final chore = allChores.singleWhere((r) => r.id == choreId);
    final records = await _historyStore.getAllRecords();
    final last = records.where((r) => r.choreId == choreId).lastOrNull;
    if (last == null) {
      return;
    }

    final stepObjs = last.steps.map(chore.createAction).toList();
    for (final step in stepObjs.reversed) {
      await step.undo(_deviceManager);
    }
    await _historyStore.clearByChoreId(choreId);
  }

  @override
  void dispose() {
    // do nothing
  }
}
