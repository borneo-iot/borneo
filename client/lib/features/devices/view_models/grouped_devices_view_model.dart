import 'dart:async';

import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/core/models/scene_entity.dart';
import 'package:borneo_app/core/services/devices/device_module_registry.dart';
import 'package:event_bus/event_bus.dart';
import 'package:cancellation_token/cancellation_token.dart';

import 'package:borneo_app/features/devices/models/device_group_entity.dart';
import 'package:borneo_app/features/devices/models/events.dart';
import 'package:borneo_app/core/services/scene_manager.dart';
import 'package:borneo_app/core/services/group_manager.dart';
import 'package:borneo_app/features/devices/view_models/group_view_model.dart';

import 'package:borneo_app/core/services/device_manager.dart';
import 'package:borneo_app/shared/view_models/base_view_model.dart';

import '../../../core/models/events.dart';

class GroupedDevicesViewModel extends BaseViewModel with ViewModelEventBusMixin, ViewModelInitFutureMixin {
  final SceneManager _sceneManager;
  final GroupManager _groupManager;
  final DeviceManager _deviceManager;
  final IDeviceModuleRegistry _deviceModuleRegistry;
  final CancellationToken _cancellationToken = CancellationToken();
  bool _isInitialized = false;

  // Getter for loading state
  bool get isInitialized => _isInitialized;
  // Getter for error message

  bool get isEmpty => _groups.isEmpty;

  // Getter for users list
  final List<GroupViewModel> _groups = [];
  List<GroupViewModel> get groups => _groups;

  GroupViewModel get dummyGroup => _groups.singleWhere((g) => g.isDummy);

  SceneEntity get currentScene => _sceneManager.current;

  late final StreamSubscription<NewDeviceEntityAddedEvent> _deviceAddedEventSub;
  late final StreamSubscription<DeviceEntityDeletedEvent> _deviceDeletedEventSub;
  late final StreamSubscription<CurrentSceneChangedEvent> _currentSceneChangedEventSub;

  // Device group event subscriptions
  late final StreamSubscription<DeviceGroupCreatedEvent> _deviceGroupCreatedEventSub;
  late final StreamSubscription<DeviceGroupDeletedEvent> _deviceGroupDeletedEventSub;
  late final StreamSubscription<DeviceGroupUpdatedEvent> _deviceGroupUpdatedEventSub;

  GroupedDevicesViewModel(
    EventBus globalEventBus,
    this._sceneManager,
    this._groupManager,
    this._deviceManager,
    this._deviceModuleRegistry, {
    super.logger,
  }) {
    super.globalEventBus = globalEventBus;
    _deviceAddedEventSub = _deviceManager.allDeviceEvents.on<NewDeviceEntityAddedEvent>().listen(
      (event) => _onNewDeviceEntityAdded(event),
    );
    _deviceDeletedEventSub = _deviceManager.allDeviceEvents.on<DeviceEntityDeletedEvent>().listen(
      (event) => _onDeviceDeleted(event),
    );
    _currentSceneChangedEventSub = super.globalEventBus.on<CurrentSceneChangedEvent>().listen(_onCurrentSceneChanged);

    _deviceGroupCreatedEventSub = super.globalEventBus.on<DeviceGroupCreatedEvent>().listen(_onDeviceGroupCreated);

    _deviceGroupDeletedEventSub = super.globalEventBus.on<DeviceGroupDeletedEvent>().listen(_onDeviceGroupDeleted);

    _deviceGroupUpdatedEventSub = super.globalEventBus.on<DeviceGroupUpdatedEvent>().listen(_onDeviceGroupUpdated);
  }

  Future<void> initialize() async {
    assert(!isInitialized);
    super.setBusy(true);
    try {
      await _reloadAll();
    } on CancelledException {
      logger?.i("Initialization future cancelled");
    } finally {
      _isInitialized = true;
      super.setBusy(false);
    }
  }

  @override
  void dispose() {
    _cancellationToken.cancel();
    _deviceAddedEventSub.cancel();
    _deviceDeletedEventSub.cancel();
    _currentSceneChangedEventSub.cancel();

    _deviceGroupCreatedEventSub.cancel();
    _deviceGroupDeletedEventSub.cancel();
    _deviceGroupUpdatedEventSub.cancel();

    super.dispose();
  }

  Future<void> refresh({bool probeOfflineDevices = false}) async {
    if (isBusy.value) {
      return;
    }
    _tryReloadAll();
  }

  Future<void> _tryReloadAll() async {
    if (isBusy.value) {
      return;
    }

    super.setBusy(true);

    try {
      await _reloadAll();
    } on CancelledException {
      logger?.i("Refreshing task cancelled");
    } finally {
      super.setBusy(false);
    }
  }

  void _clearAllItems() {
    for (final g in _groups) {
      g.clearDevices();
      g.dispose();
    }
    _groups.clear();
  }

  Future<void> _reloadAll() async {
    final groupEntities = await _groupManager.fetchAllGroupsInCurrentScene().asCancellable(_cancellationToken);

    _clearAllItems();

    final dummyGroup = GroupViewModel(
      DeviceGroupEntity(id: '', sceneID: _sceneManager.current.id, name: 'Ungrouped devices'),
    );

    _groups.addAll(groupEntities.map((g) => GroupViewModel(g)).followedBy([dummyGroup]));

    final deviceEntities = await _deviceManager.fetchAllDevicesInScene().asCancellable(_cancellationToken);
    for (final deviceEntity in deviceEntities) {
      final metaModule = _deviceModuleRegistry.metaModules[deviceEntity.driverID];
      final deviceVM = metaModule!.createSummaryVM(deviceEntity, _deviceManager, globalEventBus);
      if (deviceEntity.groupID != null) {
        final g = _groups.singleWhere((x) => x.id == deviceEntity.groupID);
        g.addDevice(deviceVM);
      } else {
        dummyGroup.addDevice(deviceVM);
      }
    }
  }

  Future<void> changeDeviceGroup(DeviceEntity device, String? newGroupID) async {
    final originalGroupVM = _groups.singleWhere((g) => g.devices.any((d) => d.deviceEntity.id == device.id));
    final newGroupVM = newGroupID != null ? _groups.singleWhere((g) => g.id == newGroupID) : dummyGroup;
    final deviceVM = originalGroupVM.devices.singleWhere((d) => d.deviceEntity.id == device.id);

    if (identical(originalGroupVM, newGroupVM)) {
      return;
    }
    try {
      await _deviceManager.moveToGroup(device.id, newGroupVM.id);
      newGroupVM.insertDevice(0, deviceVM);
      originalGroupVM.removeDevice(deviceVM);
    } catch (e, stackTrace) {
      notifyAppError('Failed to change the group for device "${device.name}"', error: e, stackTrace: stackTrace);
    } finally {
      setBusy(false);
    }
  }

  Future<void> _onNewDeviceEntityAdded(NewDeviceEntityAddedEvent event) async {
    try {
      final metaModule = _deviceModuleRegistry.metaModules[event.device.driverID];
      if (metaModule != null) {
        final deviceVM = metaModule.createSummaryVM(event.device, _deviceManager, globalEventBus);

        GroupViewModel targetGroup;
        if (event.device.groupID != null) {
          targetGroup = _groups.singleWhere((g) => g.id == event.device.groupID);
        } else {
          targetGroup = dummyGroup;
        }

        targetGroup.addDevice(deviceVM);

        logger?.i('Device ${event.device.name} added to group ${targetGroup.name}');
      }
    } catch (e, stackTrace) {
      logger?.e('Failed to add device incrementally, falling back to full reload', error: e, stackTrace: stackTrace);
      await _tryReloadAll();
    }
    notifyListeners();
  }

  Future<void> _onDeviceDeleted(DeviceEntityDeletedEvent event) async {
    final int changedGroupIndex = _groups.indexWhere((g) => g.devices.any((d) => d.deviceEntity.id == event.id));
    // Remove the deleted device from UI
    if (changedGroupIndex != -1) {
      final changedGroup = _groups[changedGroupIndex];
      final deviceToRemove = changedGroup.devices.firstWhere((d) => d.deviceEntity.id == event.id);
      deviceToRemove.dispose();
      changedGroup.removeDeviceById(event.id);
    }
    if (isEmpty) {
      notifyListeners();
    }
  }

  Future<void> deleteDevice(String id) async {
    assert(!isBusy.value);
    setBusy(true);
    try {
      await _deviceManager.delete(id);
    } catch (e, stackTrace) {
      notifyAppError('Failed to delete device', error: e, stackTrace: stackTrace);
    } finally {
      setBusy(false);
    }
  }

  void _onCurrentSceneChanged(CurrentSceneChangedEvent event) {
    if (!super.isDisposed && _isInitialized && !super.isBusy.value) {
      _tryReloadAll();
    }
  }

  void _onDeviceGroupCreated(DeviceGroupCreatedEvent event) {
    if (!isBusy.value) {
      _tryReloadAll();
      notifyListeners();
    }
  }

  void _onDeviceGroupDeleted(DeviceGroupDeletedEvent event) {
    if (!isBusy.value) {
      _tryReloadAll();
      notifyListeners();
    }
  }

  void _onDeviceGroupUpdated(DeviceGroupUpdatedEvent event) {
    for (final gvm in _groups) {
      if (gvm.id == event.group.id) {
        gvm.model = event.group;
        gvm.notifyListeners();
      }
    }
  }
}
