import 'dart:async';
import 'dart:core';

import 'package:borneo_common/exceptions.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_gettext/flutter_gettext.dart';
import 'package:logger/logger.dart';
import 'package:sembast/sembast.dart';
import 'package:synchronized/synchronized.dart';
import 'package:lw_wot/wot.dart';

import 'package:borneo_app/features/devices/models/events.dart';
import 'package:borneo_app/core/models/events.dart';
import 'package:borneo_app/core/services/group_manager.dart';
import 'package:borneo_app/core/services/scene_manager.dart';
import 'package:borneo_app/core/services/devices/device_module_registry.dart';

import 'package:borneo_app/core/services/store_names.dart';
import 'package:borneo_kernel_abstractions/kernel.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/shared/models/base_entity.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';

final class DeviceManagerImpl extends IDeviceManager {
  final GettextLocalizations gettext;
  final Logger? logger;
  bool _isDisposed = false;
  final Database _db;
  bool _isInitialized = false;
  final ISceneManager _sceneManager;

  final Lock _deviceOperLock = Lock();

  // ignore: unused_field
  final EventBus _globalBus;
  // ignore: unused_field
  final IGroupManager _groupManager;

  // event subscriptions
  late final StreamSubscription<UnboundDeviceDiscoveredEvent> _unboundDeviceDiscoveredEventSub;
  late final StreamSubscription<KnownDeviceDiscoveryUpdatedEvent> _knownDeviceDiscoveryUpdatedEventSub;
  late final StreamSubscription<CurrentSceneChangedEvent> _currentSceneChangedEventSub;
  late final StreamSubscription<LoadingDriverFailedEvent> _loadingDriverFailedEventSub;
  late final StreamSubscription<DeviceBoundEvent> _deviceBoundEventSub;

  // WotThing management
  final Map<String, WotThing> _wotThings = {};
  final Map<String, String> _lastDeviceErrors = {};
  final IDeviceModuleRegistry _deviceModuleRegistry;

  final IKernel _kernel;

  DeviceManagerImpl(
    this._db,
    this._kernel,
    this._globalBus,
    this._sceneManager,
    this._groupManager,
    this._deviceModuleRegistry, {
    required this.gettext,
    this.logger,
  }) {
    logger?.i("Creating DeviceManagerImpl...");
    _unboundDeviceDiscoveredEventSub = allDeviceEvents.on<UnboundDeviceDiscoveredEvent>().listen(
      _onUnboundDeviceDiscovered,
    );
    _knownDeviceDiscoveryUpdatedEventSub = allDeviceEvents.on<KnownDeviceDiscoveryUpdatedEvent>().listen(
      _onKnownDeviceDiscoveryUpdated,
    );
    _loadingDriverFailedEventSub = allDeviceEvents.on<LoadingDriverFailedEvent>().listen(_onLoadingDriverFailed);
    _deviceBoundEventSub = allDeviceEvents.on<DeviceBoundEvent>().listen(_onDeviceBound);

    // Listen for scene changes to manage WotThing lifecycle
    _currentSceneChangedEventSub = _globalBus.on<CurrentSceneChangedEvent>().listen(_onCurrentSceneChanged);
  }

  @override
  bool get isInitialized => _isInitialized;

  @override
  EventDispatcher get allDeviceEvents => _kernel.events;

  @override
  IKernel get kernel => _kernel;

  @override
  Iterable<BoundDevice> get boundDevices => _kernel.boundDevices;

  @override
  Future<void> initialize({CancellationToken? cancelToken}) async {
    assert(!_isInitialized);

    logger?.i('Initializing DeviceManagerImpl...');
    try {
      final devices = await fetchAllDevicesInScene().asCancellable(cancelToken);
      _kernel.registerDevices(devices.map((x) => BoundDeviceDescriptor(device: x, driverID: x.driverID)));
      await _kernel.start();

      // Load WotThings for ALL scenes so they persist across scene switches.
      await _loadAllWotThings(cancelToken: cancelToken);
      // Activate only the current scene's WotThings.
      await _activateSceneWotThings(_sceneManager.current.id);
      await _rebindAll(devices, cancelToken: cancelToken);

      final currentScene = _sceneManager.current;
      _globalBus.fire(CurrentSceneDevicesReloadedEvent(currentScene));

      logger?.i('DeviceManagerImpl has been initialized successfully.');
    } finally {
      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    if (!_isDisposed) {
      _unboundDeviceDiscoveredEventSub.cancel();
      _knownDeviceDiscoveryUpdatedEventSub.cancel();
      _currentSceneChangedEventSub.cancel();
      _loadingDriverFailedEventSub.cancel();
      _deviceBoundEventSub.cancel();

      _disposeAllWotThings();

      _isDisposed = true;
    }
  }

  @override
  bool isBound(String deviceID) => _kernel.isBound(deviceID);

  @override
  BoundDevice getBoundDevice(String deviceID) => _kernel.getBoundDevice(deviceID);

  @override
  Iterable<BoundDevice> getBoundDevicesInCurrentScene() {
    final currentScene = _sceneManager.current;
    final devices = _kernel.boundDevices.where((x) => (x.device as DeviceEntity).sceneID == currentScene.id);
    return devices;
  }

  @override
  Future<void> reloadAllDevices({CancellationToken? cancelToken}) async {
    // Suppress periodic heartbeat while performing expensive device operations;
    // this prevents the timer from racing with the rebind loop and eliminates
    // spurious CoAP timeouts.
    _kernel.enterHeartbeatBatch();
    try {
      await _deviceOperLock
          .synchronized(() async {
            await _kernel.unbindAll(cancelToken: cancelToken);
            _kernel.unregisterAllDevices();
            final devices = await fetchAllDevicesInScene().asCancellable(cancelToken);
            _kernel.registerDevices(devices.map((x) => BoundDeviceDescriptor(device: x, driverID: x.driverID)));
            await _rebindAll(devices, cancelToken: cancelToken);
            // WotThings are never disposed here; only sync the active ones.
            for (final thing in wotThingsInCurrentScene) {
              unawaited(thing.sync(cancelToken: cancelToken));
            }
          })
          .asCancellable(cancelToken);
    } finally {
      _kernel.exitHeartbeatBatch();
    }
  }

  Future<void> _rebindAll(Iterable<DeviceEntity> devices, {CancellationToken? cancelToken}) async {
    await _kernel.unbindAll();
    final futures = <Future>[];
    for (var device in devices) {
      futures.add(tryBind(device));
    }
    await Future.wait(futures).asCancellable(cancelToken);
    _globalBus.fire(DeviceManagerReadyEvent());
  }

  @override
  Future<bool> tryBind(DeviceEntity device) async => _kernel.tryBind(device, device.driverID);

  @override
  Future<void> bind(DeviceEntity device) => _kernel.bind(device, device.driverID);

  @override
  Future<void> unbind(String deviceID) => _kernel.unbind(deviceID);

  @override
  Future<void> delete(String id, {Transaction? tx, CancellationToken? cancelToken}) async {
    if (tx == null) {
      await _db.transaction((tx) => delete(id, tx: tx, cancelToken: cancelToken)).asCancellable(cancelToken);
    } else {
      if (_kernel.isBound(id)) {
        await _kernel.unbind(id, cancelToken: cancelToken);
      }
      _kernel.unregisterDevice(id);
      _disposeWotThing(id);
      final store = stringMapStoreFactory.store(StoreNames.devices);
      await store.record(id).delete(tx).asCancellable(cancelToken);
      allDeviceEvents.fire(DeviceEntityDeletedEvent(id));
      final currentScene = _sceneManager.current;
      _globalBus.fire(CurrentSceneDevicesReloadedEvent(currentScene));
    }
  }

  @override
  Future<void> update(String id, {Transaction? tx, String? name, String? groupID}) async {
    if (tx == null) {
      await _db.transaction((tx) async {
        await _update(id, tx: tx, name: name, groupID: groupID);
      });
    } else {
      await _update(id, tx: tx, name: name, groupID: groupID);
    }
  }

  @override
  Future<void> updateAddress(String id, Uri address, {CancellationToken? cancelToken}) async {
    final updatedEntity = await _db
        .transaction((tx) => _update(id, tx: tx, address: address))
        .asCancellable(cancelToken);
    await _refreshKernelRegistration(updatedEntity, cancelToken: cancelToken);
  }

  Future<DeviceEntity> _update(
    String id, {
    required Transaction tx,
    String? name,
    String? groupID,
    Uri? address,
  }) async {
    final store = stringMapStoreFactory.store(StoreNames.devices);
    final originalRecord = await store.record(id).get(tx);
    if (originalRecord == null) {
      throw KeyNotFoundException(message: 'Cannot found device with ID `$id`');
    }
    final oldEntity = DeviceEntity.fromMap(id, originalRecord);
    _restoreLastError(oldEntity);
    final fieldsToUpdate = <String, dynamic>{};

    if (name != null) {
      fieldsToUpdate[DeviceEntity.kNameFieldName] = name;
    }
    if (groupID != null) {
      fieldsToUpdate[DeviceEntity.kGroupIDFieldName] = groupID;
    }
    if (address != null) {
      fieldsToUpdate[DeviceEntity.kAddressFieldName] = address.toString();
    }

    final updatedRecord = await store.record(id).update(tx, fieldsToUpdate);
    final updatedEntity = DeviceEntity.fromMap(id, updatedRecord!);
    _restoreLastError(updatedEntity);
    allDeviceEvents.fire(DeviceEntityUpdatedEvent(oldEntity, updatedEntity));
    return updatedEntity;
  }

  Future<bool> _groupExists(Transaction tx, String groupID) async {
    final groupStore = stringMapStoreFactory.store(StoreNames.groups);
    final groupRecord = await groupStore.record(groupID).get(tx);
    return groupRecord != null;
  }

  @override
  Future<void> moveToGroup(String id, String newGroupID) async {
    await _db.transaction((tx) async {
      // Allow empty string for ungrouped devices
      if (newGroupID.isNotEmpty) {
        final exists = await _groupExists(tx, newGroupID);
        if (!exists) {
          throw KeyNotFoundException(message: 'Cannot find group with ID `$newGroupID`');
        }
      }
      await _update(id, tx: tx, groupID: newGroupID);
    });
  }

  @override
  Future<bool> isNewDevice(SupportedDeviceDescriptor matched, {Transaction? tx}) async {
    if (tx == null) {
      return await _db.transaction((tx) => isNewDevice(matched, tx: tx));
    } else {
      final store = stringMapStoreFactory.store(StoreNames.devices);
      final filter = Filter.equals(DeviceEntity.kFngerprintFieldName, matched.fingerprint);
      final n = await store.count(tx, filter: filter);
      return n == 0;
    }
  }

  @override
  Future<DeviceEntity?> singleOrDefaultByFingerprint(String fingerprint, {Transaction? tx}) async {
    if (tx == null) {
      return await _db.transaction((tx) => singleOrDefaultByFingerprint(fingerprint, tx: tx));
    } else {
      final store = stringMapStoreFactory.store(StoreNames.devices);
      final record = await store.findFirst(
        tx,
        finder: Finder(filter: Filter.equals(DeviceEntity.kFngerprintFieldName, fingerprint)),
      );
      if (record == null) {
        return null;
      }
      final device = DeviceEntity.fromMap(record.key, record.value);
      return _restoreLastError(device);
    }
  }

  @override
  Future<DeviceEntity> addNewDevice(SupportedDeviceDescriptor discovered, {String? groupID, Transaction? tx}) async {
    assert(isInitialized);

    final device = tx == null
        ? await _db.transaction((tx) async => await _addNewDeviceToStore(discovered, groupID: groupID, tx: tx))
        : await _addNewDeviceToStore(discovered, tx: tx);

    _kernel.registerDevice(BoundDeviceDescriptor(device: device, driverID: device.driverID));

    // Always create a WotThing twin, even when the device is unbound/offline.
    await _loadWotThingForDevice(device, replaceExisting: true);
    // Activate immediately when the new device belongs to the current scene.
    if (device.sceneID == _sceneManager.current.id) {
      _wotThings[device.id]?.activate();
    }

    final bindResult = await tryBind(device);
    _restoreLastError(device);
    if (!bindResult) {
      logger?.e('Failed to bind device: $device');
    }

    allDeviceEvents.fire(NewDeviceEntityAddedEvent(device));

    // Fire event to notify that devices in current scene have been reloaded
    final currentScene = _sceneManager.current;
    _globalBus.fire(CurrentSceneDevicesReloadedEvent(currentScene));
    return device;
  }

  Future<DeviceEntity> _addNewDeviceToStore(
    SupportedDeviceDescriptor discovered, {
    String? groupID,
    required Transaction tx,
  }) async {
    assert(isInitialized);
    final store = stringMapStoreFactory.store(StoreNames.devices);

    final device = DeviceEntity(
      id: BaseEntity.generateID(),
      sceneID: _sceneManager.current.id,
      driverID: discovered.driverDescriptor.id,
      groupID: groupID,
      address: discovered.address,
      compatible: discovered.compatible,
      fingerprint: discovered.fingerprint,
      name: discovered.name,
      model: discovered.model,
    );
    await store.record(device.id).put(tx, device.toMap());
    return device;
  }

  @override
  Future<DeviceEntity> getDevice(String id, {Transaction? tx}) async {
    if (tx == null) {
      return await _db.transaction((tx) async {
        return await getDevice(id, tx: tx);
      });
    } else {
      final store = stringMapStoreFactory.store(StoreNames.devices);
      final record = await store.record(id).get(tx);
      if (record == null) {
        throw KeyNotFoundException(message: 'Cannot find device with ID `$id`', key: id);
      }
      final device = DeviceEntity.fromMap(id, record);
      return _restoreLastError(device);
    }
  }

  @override
  Future<List<DeviceEntity>> fetchAllDevicesInScene({String? sceneID}) async {
    return await _db.transaction((tx) async {
      final store = stringMapStoreFactory.store(StoreNames.devices);
      final finder = Finder(filter: Filter.equals(DeviceEntity.kSceneIDFieldName, sceneID ?? _sceneManager.current.id));
      final records = await store.find(tx, finder: finder);
      final devices = records
          .map((record) => _restoreLastError(DeviceEntity.fromMap(record.key, record.value)))
          .toList();
      return devices;
    });
  }

  void _onLoadingDriverFailed(LoadingDriverFailedEvent event) {
    _lastDeviceErrors[event.device.id] = _formatLoadingDriverFailed(event);
  }

  void _onDeviceBound(DeviceBoundEvent event) {
    _lastDeviceErrors.remove(event.device.id);
  }

  DeviceEntity _restoreLastError(DeviceEntity device) {
    device.lastErrorMessage = _lastDeviceErrors[device.id];
    return device;
  }

  String _formatLoadingDriverFailed(LoadingDriverFailedEvent event) {
    final error = event.error;
    if (error is UnsupportedVersionError) {
      return gettext.translate(
        'Device firmware version {currentVersion} is not supported. Required: {requiredVersion}.',
        nArgs: {
          'currentVersion': error.currentVersion.toString(),
          'requiredVersion': error.versionRange?.toString() ?? 'unknown',
        },
      );
    }

    if (error is UncompatibleDeviceError) {
      return gettext.translate('This device is not compatible with the selected driver.');
    }

    if (error is TimeoutException) {
      return gettext.translate('Timed out while probing the device.');
    }

    final message = event.message?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }

    if (error != null) {
      return error.toString();
    }

    return gettext.translate('Unable to connect to this device.');
  }

  @override
  bool get isDiscoverying => _kernel.isScanning;

  @override
  Future<void> startDiscovery({Duration? timeout, CancellationToken? cancelToken}) async {
    assert(!_kernel.isScanning);
    await _kernel.startDevicesScanning(timeout: timeout, cancelToken: cancelToken);
  }

  @override
  Future<void> stopDiscovery() async {
    assert(_kernel.isScanning);
    await _kernel.stopDevicesScanning();
  }

  Future<void> _onUnboundDeviceDiscovered(UnboundDeviceDiscoveredEvent event) async {
    logger?.i('Device discovered: ${event.matched}');
    assert(isInitialized);

    return await _db.transaction((tx) async {
      final existed = await singleOrDefaultByFingerprint(event.matched.fingerprint, tx: tx);
      if (existed == null) {
        allDeviceEvents.fire(NewDeviceFoundEvent(event.matched));
      }
    });
  }

  Future<void> _onKnownDeviceDiscoveryUpdated(KnownDeviceDiscoveryUpdatedEvent event) async {
    logger?.i('Known device discovery updated: ${event.device.id} -> ${event.matched.address}');
    assert(isInitialized);

    if (event.device.address == event.matched.address) {
      return;
    }

    await updateAddress(event.device.id, event.matched.address);
  }

  Future<void> _refreshKernelRegistration(DeviceEntity updatedEntity, {CancellationToken? cancelToken}) async {
    final wasBound = _kernel.boundDevices.any((bound) => bound.device.id == updatedEntity.id);

    _kernel.enterHeartbeatBatch();
    try {
      await _deviceOperLock
          .synchronized(() async {
            if (wasBound) {
              await _kernel.unbind(updatedEntity.id, cancelToken: cancelToken);
            }

            _kernel.unregisterDevice(updatedEntity.id);
            _kernel.registerDevice(BoundDeviceDescriptor(device: updatedEntity, driverID: updatedEntity.driverID));

            if (wasBound) {
              await _kernel.tryBind(updatedEntity, updatedEntity.driverID, cancelToken: cancelToken);
            }
          })
          .asCancellable(cancelToken);
    } finally {
      _kernel.exitHeartbeatBatch();
    }
  }

  @override
  WotThing getWotThing(String deviceID) {
    // Only return WotThings for devices that are already loaded (current scene)
    final wotThing = _wotThings[deviceID];
    if (wotThing == null) {
      throw StateError(
        'WotThing not found for device $deviceID. Ensure the device is in the current scene and WotThing was loaded successfully.',
      );
    }
    return wotThing;
  }

  @override
  bool hasWotThing(String deviceID) => _wotThings.containsKey(deviceID);

  @override
  Iterable<WotThing> get allWotThings => _wotThings.values;

  @override
  Iterable<WotThing> get wotThingsInCurrentScene => _wotThings.values.where((t) => t.isActive);

  @override
  Iterable<String> get deviceIDsWithWotThings => _wotThings.keys;

  @override
  int get wotThingCount => _wotThings.length;

  // ---------------------------------------------------------------------------
  // Scene-change handler
  // ---------------------------------------------------------------------------

  /// Handle scene change: deactivate old scene's Things, switch kernel,
  /// ensure + activate new scene's Things.
  Future<void> _onCurrentSceneChanged(CurrentSceneChangedEvent event) async {
    logger?.i('Scene changed: ${event.from.name} → ${event.to.name}');

    // 1. Deactivate WotThings of the old scene.
    await _deactivateSceneWotThings(event.from.id);

    // 2. Kernel-layer switch: unbind old devices, register & bind new scene.
    _kernel.enterHeartbeatBatch();
    try {
      await _deviceOperLock.synchronized(() async {
        await _kernel.unbindAll();
        _kernel.unregisterAllDevices();
        final devices = await fetchAllDevicesInScene(sceneID: event.to.id);
        _kernel.registerDevices(devices.map((x) => BoundDeviceDescriptor(device: x, driverID: x.driverID)));
        await _rebindAll(devices);
      });
    } finally {
      _kernel.exitHeartbeatBatch();
    }

    // 3. Ensure WotThings exist for the new scene (lazy-create if missing).
    await _ensureWotThingsForScene(event.to.id);

    // 4. Activate the new scene's WotThings.
    await _activateSceneWotThings(event.to.id);

    _globalBus.fire(CurrentSceneDevicesReloadedEvent(event.to));
  }

  // ---------------------------------------------------------------------------
  // WotThing lifecycle helpers
  // ---------------------------------------------------------------------------

  /// Load WotThings for ALL scenes so they persist globally.
  Future<void> _loadAllWotThings({CancellationToken? cancelToken}) async {
    try {
      final allScenes = await _sceneManager.all();
      for (final scene in allScenes) {
        final devices = await fetchAllDevicesInScene(sceneID: scene.id);
        for (final device in devices) {
          await _loadWotThingForDevice(device, replaceExisting: false, cancelToken: cancelToken);
        }
      }
      logger?.d('Loaded ${_wotThings.length} WotThings for all scenes');
    } catch (e) {
      logger?.e('Failed to load WotThings for all scenes: $e');
    }
  }

  /// Activate every WotThing whose device belongs to [sceneID].
  Future<void> _activateSceneWotThings(String sceneID) async {
    final devices = await fetchAllDevicesInScene(sceneID: sceneID);
    for (final device in devices) {
      _wotThings[device.id]?.activate();
    }
  }

  /// Deactivate every WotThing whose device belongs to [sceneID].
  Future<void> _deactivateSceneWotThings(String sceneID) async {
    final devices = await fetchAllDevicesInScene(sceneID: sceneID);
    for (final device in devices) {
      _wotThings[device.id]?.deactivate();
    }
  }

  /// Ensure WotThings are created for all devices in [sceneID] (lazy patch).
  Future<void> _ensureWotThingsForScene(String sceneID, {CancellationToken? cancelToken}) async {
    final devices = await fetchAllDevicesInScene(sceneID: sceneID);
    for (final device in devices) {
      if (!_wotThings.containsKey(device.id)) {
        await _loadWotThingForDevice(device, replaceExisting: false, cancelToken: cancelToken);
      }
    }
  }

  /// Dispose all existing WotThings (called only on full app shutdown).
  void _disposeAllWotThings() {
    for (final wotThing in _wotThings.values) {
      try {
        wotThing.dispose();
      } catch (e) {
        logger?.w('Failed to dispose WotThing: $e');
      }
    }
    _wotThings.clear();
    logger?.d('Disposed all WotThings');
  }

  /// Dispose a single WotThing for a device
  void _disposeWotThing(String deviceID) {
    final wotThing = _wotThings[deviceID];
    if (wotThing != null) {
      try {
        wotThing.dispose();
        _wotThings.remove(deviceID);
        logger?.d('Disposed WotThing for device $deviceID');
      } catch (e) {
        logger?.w('Failed to dispose WotThing for device $deviceID: $e');
      }
    }
  }

  /// Load WotThing for a single device
  Future<void> _loadWotThingForDevice(
    DeviceEntity device, {
    bool replaceExisting = true,
    CancellationToken? cancelToken,
  }) async {
    try {
      final metaModule = _deviceModuleRegistry.metaModules[device.driverID];
      if (metaModule != null) {
        final wotThing = await metaModule.createWotThing(device, this, logger: logger, cancelToken: cancelToken);
        if (!replaceExisting && _wotThings.containsKey(device.id)) {
          return;
        }
        final oldThing = _wotThings[device.id];
        _wotThings[device.id] = wotThing;

        if (replaceExisting && oldThing != null && oldThing != wotThing) {
          try {
            oldThing.dispose();
          } catch (e) {
            logger?.w('Failed to dispose replaced WotThing for device ${device.id}: $e');
          }
        }

        // If device is bound, sync WotThing with actual device state
        if (isBound(device.id)) {
          await _syncWotThingWithBoundDevice(device.id, wotThing, cancelToken: cancelToken);
        }
        logger?.d('Successfully loaded WotThing for device ${device.id}');
      }
    } catch (e) {
      logger?.w('Failed to create WotThing for device ${device.id}: $e');
    }
  }

  /// Sync WotThing properties with actual device state
  Future<void> _syncWotThingWithBoundDevice(
    String deviceID,
    WotThing wotThing, {
    CancellationToken? cancelToken,
  }) async {
    try {
      wotThing.sync(cancelToken: cancelToken);
      logger?.d('WotThing synced for device $deviceID');
    } catch (e) {
      logger?.w('Failed to sync WotThing for device $deviceID: $e');
    }
  }
}
