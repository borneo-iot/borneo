import 'package:borneo_kernel_abstractions/events.dart';
import 'package:borneo_kernel_abstractions/event_dispatcher.dart';
import 'package:borneo_kernel_abstractions/driver.dart';
import 'package:borneo_kernel_abstractions/models/heartbeat_state.dart';
import 'package:cancellation_token/cancellation_token.dart';

import 'package:borneo_common/borneo_common.dart';
import 'package:borneo_kernel_abstractions/device.dart';

import 'models/bound_device.dart';

export 'driver.dart';
export 'driver_registry.dart';
export 'errors.dart';
export 'events.dart';
export 'device.dart';
export 'mdns.dart';
export 'network.dart';

export 'models/bound_device.dart';
export 'models/discovered_device.dart';
export 'models/driver_data.dart';
export 'models/driver_descriptor.dart';
export 'models/heartbeat_method.dart';
export 'models/heartbeat_state.dart';
export 'models/supported_device_descriptor.dart';

// new kernel interface exports
export 'discovery_manager.dart';
export 'binding_engine.dart';
export 'heartbeat_service.dart';
export 'driver_factory.dart';
export 'event_dispatcher.dart';
export 'device_bus.dart';

/// Core interface for the device management kernel.  The kernel
/// maintains a set of registered devices, drives the probing/binding
/// lifecycle and periodically polls bound devices for heartbeat information.
///
/// Concrete implementations (such as [DefaultKernel]) should be started by
/// calling [start] before they are used; most other methods will throw if
/// the kernel has not been initialized.
abstract class IKernel implements IDisposable {
  /// Currently bound devices.  Each [BoundDevice] holds a reference to the
  /// device entity and the driver instance managing it.
  Iterable<BoundDevice> get boundDevices;

  /// Indicates whether [start] has completed successfully.
  bool get isInitialized;

  /// Event dispatcher exposed by the kernel; all device-related events are
  /// fired through this dispatcher.  The concrete object may currently be a
  /// [GlobalDevicesEventBus] for backwards compatibility, but callers should
  /// program against the [EventDispatcher] interface to avoid depending on a
  /// global singleton.  Eventually this property will return a
  /// [DefaultEventDispatcher].
  EventDispatcher get events;

  /// Drivers that have been activated.  Drivers are activated lazily when the
  /// first device requiring them is bound; unused drivers are purged
  /// automatically.
  Iterable<Driver> get activatedDrivers;

  /// Whether the kernel is currently performing any binding/unbinding
  /// operations.  Used internally by the heartbeat task to avoid conflicts.
  bool get isBusy;

  /// `true` if an mDNS device scan has been started and not yet stopped.
  bool get isScanning;

  /// Initialize and start kernel processing.  After calling this method the
  /// kernel begins its periodic heartbeat/polling and may accept binding or
  /// scanning requests.
  Future<void> start();

  /// Returns whether a device with [deviceID] is currently bound.
  bool isBound(String deviceID);

  /// Temporarily suspend the kernel's periodic heartbeat/polling task.
  ///
  /// **Deprecated.** Use [enterHeartbeatBatch]/[exitHeartbeatBatch] instead.
  ///
  /// This is intended for long-running operations (bulk bind/unbind,
  /// scene reload, etc.) during which the kernel should not attempt to probe
  /// or bind devices. Callers **must** pair a suspend call with a matching
  /// [resumeHeartbeat] in a `try/finally` block to avoid leaving the kernel
  /// disabled indefinitely.
  @deprecated
  void suspendHeartbeat();

  /// Resume a previously suspended heartbeat task. Safe to call even if the
  /// kernel was not suspended (no-op).
  @deprecated
  void resumeHeartbeat();

  /// Signal that the kernel is entering a batch of operations during which
  /// heartbeats should be temporarily ignored.  Callers should pair this with
  /// [exitHeartbeatBatch] to return to normal processing.
  void enterHeartbeatBatch();

  /// Exit a previously-entered batch mode started by [enterHeartbeatBatch].
  void exitHeartbeatBatch();

  /// Returns the current heartbeat state for a given device, or `null` if the
  /// service has no record for it.
  HeartbeatState? getHeartbeatState(String deviceID);

  /// Retrieve a previously bound device.  Throws if the device is not
  /// registered or not currently bound.
  BoundDevice getBoundDevice(String deviceID);

  /// Probe and bind [device] with the driver identified by [driverID].
  ///
  /// Returns `true` if the driver probe completed successfully and the
  /// device is now bound.  Does not throw on probe errors; a failure simply
  /// results in `false`.
  Future<bool> tryBind(Device device, String driverID, {CancellationToken? cancelToken});

  /// Same as [tryBind] but throws on failure instead of returning `false`.
  Future<void> bind(Device device, String driverID, {CancellationToken? cancelToken});

  /// Unbind the device with the given ID, disposing its driver instance.
  Future<void> unbind(String deviceID, {CancellationToken? cancelToken});

  /// Unbind all currently bound devices.
  Future<void> unbindAll({CancellationToken? cancelToken});

  /// Begin scanning for devices (e.g. via mDNS).  If [timeout] is provided
  /// the scan will be automatically stopped after the duration elapses.
  Future<void> startDevicesScanning({Duration? timeout, CancellationToken? cancelToken});

  /// Stop any ongoing device scanning operation.
  Future<void> stopDevicesScanning();

  /// Register a device descriptor for later probing/binding.  Registered
  /// but unbound devices are periodically probed by the heartbeat task.
  void registerDevice(BoundDeviceDescriptor device);

  /// Register multiple devices at once.
  void registerDevices(Iterable<BoundDeviceDescriptor> devices);

  /// Remove a previously registered device.  The device must not be bound.
  void unregisterDevice(String deviceID);

  /// Remove all registered devices.
  void unregisterAllDevices();
}
