// GENERATED/START: manual migration helpers for riverpod
// This module contains top-level Riverpod providers corresponding to the
// services that used to be registered in main.dart via provider/MultiProvider.
//
// During the early stages of the migration both graphs will coexist: the
// old `provider` instances remain in place for the unconverted UI, while
// the new Riverpod providers are constructed lazily and can be consumed
// incrementally.  Once every consumer has been migrated we can remove the
// legacy providers and eliminate this file or repurpose it per feature.

import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_app/core/services/chore_manager.dart';
import 'package:borneo_app/core/services/devices/ble_provisioner.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/core/services/group_manager.dart';
import 'package:borneo_app/core/services/local_service.dart';
import 'package:borneo_app/core/services/scene_manager.dart';
import 'package:borneo_app/routes/route_manager.dart';
import 'package:borneo_app/core/app_flags.dart';
import 'package:borneo_app/features/settings/providers/app_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:borneo_app/core/infrastructure/logging.dart';
import 'package:logger/logger.dart';
import 'package:borneo_app/core/services/clock.dart';
import 'package:borneo_app/core/services/device_exception_handler.dart';
import 'package:borneo_app/core/services/devices/mdns.dart';
import 'package:borneo_app/core/services/network_change_monitor.dart';
import 'package:borneo_app/core/services/devices/device_module_registry.dart';
import 'package:borneo_app/core/services/devices/static_modular_driver_registry.dart';
import 'package:borneo_kernel_abstractions/kernel.dart';
import 'package:borneo_kernel/kernel.dart';
import 'package:borneo_app/core/services/platform_service.dart';
import 'package:borneo_app/core/models/platform_device_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:event_bus/event_bus.dart';
import 'package:sembast/sembast.dart';

/// Basic logger provider.  The legacy implementation closes itself when disposed.
final loggerProvider = Provider<Logger>((ref) {
  final logger = createLogger();
  ref.onDispose(() => logger.close());
  return logger;
});

/// Simple clock implementation.
final clockProvider = Provider<IClock>((ref) => DefaultClock());

/// Placeholder for a database instance; overridden in main.dart.
final databaseProvider = Provider<Database>((ref) => throw UnimplementedError('databaseProvider must be overridden'));

/// Device exception handler built from [logger].
final deviceExceptionHandlerProvider = Provider<DeviceExceptionHandler>((ref) {
  final logger = ref.watch(loggerProvider);
  return DeviceExceptionHandler(logger: logger);
});

/// mDNS provider.  Can be overridden for tests or platform-specific
/// implementations.
final mdnsProvider = Provider<IMdnsProvider>((ref) => NsdMdnsProvider());

/// Network monitor used by the kernel to react to local network changes.
final networkMonitorProvider = Provider<INetworkMonitor>((ref) => ConnectivityNetworkChangeMonitor());

/// Device module registry; overridden by the value created in main.
final deviceModuleRegistryProvider = Provider<IDeviceModuleRegistry>(
  (ref) => throw UnimplementedError('deviceModuleRegistryProvider must be overridden'),
);

/// Route manager constructed from [deviceModuleRegistry].
final routeManagerProvider = Provider<RouteManager>((ref) {
  final reg = ref.watch(deviceModuleRegistryProvider);
  return RouteManager(reg);
});

/// Driver registry derived from the module registry.
final driverRegistryProvider = Provider<IDriverRegistry>((ref) {
  final reg = ref.watch(deviceModuleRegistryProvider);
  return StaticModularDriverRegistry(reg);
});

/// Kernel implementation built from logger, driver registry and mDNS.
final kernelProvider = Provider<IKernel>((ref) {
  final logger = ref.watch(loggerProvider);
  final driverReg = ref.watch(driverRegistryProvider);
  final mdns = ref.watch(mdnsProvider);
  final networkMonitor = ref.watch(networkMonitorProvider);
  return DefaultKernel(logger, driverReg, mdnsProvider: mdns, networkMonitor: networkMonitor);
});

/// Locale service, eagerly created.
final localeServiceProvider = Provider<ILocaleService>((ref) {
  return AppLocaleService();
});

/// Platform service used for feature checks.
final platformServiceProvider = Provider<PlatformService>((ref) {
  return PlatformServiceImpl();
});

/// Platform device info (corner radii, etc.); overridden by main.
final platformDeviceInfoProvider = Provider<PlatformDeviceInfo>(
  (ref) => throw UnimplementedError('platformDeviceInfoProvider must be overridden'),
);

/// Event bus for app-wide events.  Overridden from main to allow reuse.
final eventBusProvider = Provider<EventBus>((ref) => throw UnimplementedError('eventBusProvider must be overridden'));

/// Shared preferences; overridden in main.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

/// BLE provisioner, simple default.
final bleProvisionerProvider = Provider<IBleProvisioner>((ref) {
  // original provider had a Logger dependency but did not use it directly
  return BleProvisioner();
});

/// Group manager; overridden at the widget-tree level for screens that need it.
final groupManagerProvider = Provider<IGroupManager>(
  (ref) => throw UnimplementedError('groupManagerProvider must be overridden'),
);

/// Scene manager; overridden at the widget-tree level for screens that need it.
final sceneManagerProvider = Provider<ISceneManager>(
  (ref) => throw UnimplementedError('sceneManagerProvider must be overridden'),
);

/// Device manager; overridden at the widget-tree level for screens that need it.
final deviceManagerProvider = Provider<IDeviceManager>(
  (ref) => throw UnimplementedError('deviceManagerProvider must be overridden'),
);

/// Chore manager; overridden at the widget-tree level for screens that need it.
final choreManagerProvider = Provider<IChoreManager>(
  (ref) => throw UnimplementedError('choreManagerProvider must be overridden'),
);

/// App notification service; overridden at the widget-tree level.
final appNotificationServiceProvider = Provider<IAppNotificationService>(
  (ref) => throw UnimplementedError('appNotificationServiceProvider must be overridden'),
);

// Additional providers (if needed) can be added here as the migration
// proceeds (e.g. StateNotifierProviders for view models).

// ---------------------------------------------------------------------------
// Demo mode derived provider
// ---------------------------------------------------------------------------
//
// A simple synchronous boolean so the UI does not have to unwrap an
// AsyncValue everywhere it needs to check demo mode.

/// `true` when demo mode is currently enabled.  Derived from
/// [appSettingsProvider] so that it updates reactively.
final demoModeProvider = Provider<bool>((ref) {
  return ref.watch(appSettingsProvider).asData?.value.demoMode ?? kDefaultDemoMode;
});
