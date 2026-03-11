import 'dart:io';

import 'package:borneo_app/core/infrastructure/logging.dart';
import 'package:borneo_app/core/services/clock.dart';
import 'package:borneo_app/core/services/device_exception_handler.dart';
import 'package:borneo_app/core/services/devices/ble_provisioner.dart';
import 'package:borneo_app/core/services/devices/device_module_harvesters.dart';
import 'package:borneo_app/core/services/devices/device_module_registry.dart';
import 'package:borneo_app/core/services/devices/mdns.dart';
import 'package:borneo_app/core/services/network_change_monitor.dart';
import 'package:borneo_app/core/services/devices/ota/ota_providers.dart';
import 'package:borneo_app/core/services/devices/static_modular_driver_registry.dart';
import 'package:borneo_kernel/kernel.dart';
import 'package:borneo_kernel_abstractions/kernel.dart';
import 'package:flutter/material.dart';
import 'package:screen_corner_radius/screen_corner_radius.dart';

import 'core/models/platform_device_info.dart';
import 'package:flutter/services.dart';
// import 'package:flutter_gettext/gettext/gettext.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart' as provider;
import 'package:borneo_app/core/services/platform_service.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

// riverpod providers for the root services; added as part of the
// step‑1 migration plan described in .design-docs/riverpod-migration-plan.md
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/providers.dart';

import 'dart:async';

import 'package:sembast/sembast.dart';
import 'package:window_size/window_size.dart';

import 'app/app.dart';
import 'core/config/language_config.dart';
import 'routes/route_manager.dart';

import 'core/services/app_storage.dart';
import 'core/services/db.dart';
import 'core/services/local_service.dart';

Future<Database> openDatabase() async {
  final appDir = await getAppSupportDataDirectory();
  await appDir.create(recursive: true);

  final dbProvider = DBProvider(appDir.path);
  await dbProvider.initialize();

  if (await dbProvider.isExisted()) {
    // For Debug only!
    // await dbProvider.delete();
  }

  return await dbProvider.open();
}

final _fatalErrorLogger = createLogger();

/// Builds the root app widget with all service providers wired up.
///
/// All parameters are optional; when omitted the production implementations
/// are used.  Pass explicit values to inject test-friendly alternatives
/// (e.g. an in-memory [Database] created with `databaseFactoryMemory`).
Future<Widget> buildAppWidget({
  Database? database,
  SharedPreferences? sharedPreferences,
  EventBus? eventBus,
  IDeviceModuleRegistry? deviceModuleRegistry,
  IMdnsProvider? mdnsProvider,
  INetworkMonitor? networkMonitor,

  /// Optional override of the screen radius, used by tests or fallback
  /// environments.  If `null` the real plugin result is fetched.
  ScreenRadius? screenRadiusOverride,
}) async {
  final db = database ?? await openDatabase();
  final prefs = sharedPreferences ?? await SharedPreferences.getInstance();
  final bus = eventBus ?? EventBus();
  final registry = deviceModuleRegistry ?? DeviceModuleRegistry(StaticDeviceModuleHarvester());
  final localeService = AppLocaleService();

  // Read locale synchronously from the already-loaded SharedPreferences so the
  // first frame uses the correct locale instead of the system locale.
  final localeStr = prefs.getString('app.locale');
  final initialLocale = localeStr != null ? LanguageConfig.languageCodeToLocale(localeStr) : null;

  // determine platform device info before constructing providers
  ScreenRadius screenRadius;
  if (screenRadiusOverride != null) {
    screenRadius = screenRadiusOverride;
  } else {
    try {
      screenRadius = (await ScreenCornerRadius.get()) ?? ScreenRadius.value(0);
    } catch (_) {
      // plugin failed (tests, desktop, etc.) – fall back to 0
      screenRadius = ScreenRadius.value(0);
    }
  }
  final platformInfo = PlatformDeviceInfo(screenCornerRadius: screenRadius);

  // network monitor override for tests; fall back to the real connectivity
  // implementation otherwise.
  final nm = networkMonitor ?? ConnectivityNetworkChangeMonitor();

  final List<SingleChildWidget> providers = [
    // Logger
    provider.Provider<Logger>(
      create: (_) => createLogger(),
      lazy: false,
      dispose: (_, logger) {
        logger.close();
      },
    ),

    // IClock
    provider.Provider<IClock>(create: (_) => DefaultClock()),

    // DB
    provider.Provider<Database>(
      create: (_) => db,
      lazy: false,
      dispose: (_, db) {
        db.close();
      },
    ),

    // DeviceExceptionHandler
    provider.ProxyProvider<Logger, DeviceExceptionHandler>(
      update: (_, t, r) => r ?? DeviceExceptionHandler(logger: t),
      lazy: true,
    ),

    // mDns provider
    provider.Provider<IMdnsProvider>(create: (_) => mdnsProvider ?? NsdMdnsProvider(), lazy: true),

    // IDeviceModuleRegistry
    provider.Provider<IDeviceModuleRegistry>(create: (_) => registry, lazy: true),

    // RouteManager
    provider.ProxyProvider<IDeviceModuleRegistry, RouteManager>(
      update: (_, reg, rm) => rm ?? RouteManager(reg),
      lazy: true,
    ),

    // IDriverRegistry
    provider.ProxyProvider<IDeviceModuleRegistry, IDriverRegistry>(
      update: (_, reg, smdr) => smdr ?? StaticModularDriverRegistry(reg),
      lazy: true,
    ),

    // Network monitor used by the kernel to react to local network changes.
    // this may have been provided by the caller (tests) or is created above.
    provider.Provider<INetworkMonitor>(create: (_) => nm, lazy: false),

    // IKernel
    provider.ProxyProvider4<Logger, IDriverRegistry, IMdnsProvider, INetworkMonitor, IKernel>(
      update: (_, logger, driverReg, nsdMdns, networkMonitor, kernel) =>
          kernel ?? DefaultKernel(logger, driverReg, mdnsProvider: nsdMdns, networkMonitor: networkMonitor),
      dispose: (context, kernel) => kernel.dispose(),
      lazy: true,
    ),

    // LocaleService
    provider.Provider<ILocaleService>(create: (_) => localeService, lazy: false),

    // PlatformService (used by various components to make platform checks testable)
    provider.Provider<PlatformService>(create: (_) => PlatformServiceImpl(), lazy: false),

    // device-specific information (corner radii, etc.)
    provider.Provider<PlatformDeviceInfo>(create: (_) => platformInfo, lazy: false),

    // EventBus
    provider.Provider<EventBus>(create: (_) => bus, lazy: false),

    // SharedPreferences
    provider.Provider<SharedPreferences>(create: (_) => prefs, lazy: false),

    // IBleProvisioner
    provider.ProxyProvider<Logger, IBleProvisioner>(update: (_, logger, prev) => prev ?? BleProvisioner(), lazy: true),

    provider.Provider<OtaProvider>(create: (_) => OtaProvider(), lazy: true),
  ];

  // Wrap the existing provider graph in a ProviderScope so that
  // new Riverpod consumers can begin accessing the same service instances.
  // The overrides ensure objects already created above are reused rather
  // than recreated.
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      eventBusProvider.overrideWithValue(bus),
      deviceModuleRegistryProvider.overrideWithValue(registry),
      localeServiceProvider.overrideWithValue(localeService),
      platformDeviceInfoProvider.overrideWithValue(platformInfo),
      // other overrides may be added as the migration continues
    ],
    child: provider.MultiProvider(
      providers: providers,
      child: BorneoApp(initialLocale: initialLocale, globalEventBus: bus),
    ),
  );
}

Future<void> main() async {
  // Ensure binding initialization and app startup occur in the SAME zone as runApp
  runZonedGuarded(
    () async {
      WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
      // portrait lock is only necessary on phones/tablets; desktop apps are
      // already freeform and we enforce a 9:19.5 ratio ourselves below.
      if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

      final db = await openDatabase();

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Get current screen information
        final screen = await getCurrentScreen();
        if (screen != null) {
          final screenSize = screen.visibleFrame.size;
          final screenWidth = screenSize.width;
          final screenHeight = screenSize.height;

          // Define portrait aspect ratio (width/height ≈ 0.4615).
          // this value is used both for the initial frame and to enforce
          // the ratio whenever the window is resized.
          const double aspectRatio = 9 / 19.5;

          // Calculate window height: set to 80% of screen height, clamped
          // between 600 and 960 so the window isn't ridiculous on very large
          // or very small screens.
          double height = screenHeight * 0.8;
          if (height > 960) height = 960; // Upper limit
          if (height < 600) height = 600; // Lower limit for usability

          // Calculate width based on aspect ratio
          double width = height * aspectRatio;

          // Ensure width does not exceed 90% of screen width; adjust height
          // accordingly to keep the aspect ratio.
          if (width > screenWidth * 0.9) {
            width = screenWidth * 0.9;
            height = width / aspectRatio;
          }

          // Allow the user to resize freely, but keep the aspect ratio fixed by
          // listening for metric changes.  We still provide reasonable minimums
          // so the window remains portrait-ish and usable.
          setWindowMinSize(Size(width * 0.3, height * 0.3));
          // don't set a hard max size; the enforcer will clamp the ratio.

          setWindowFrame(
            Rect.fromLTWH(
              (screenWidth - width) / 2, // Center horizontally
              (screenHeight - height) / 2, // Center vertically
              width,
              height,
            ),
          );

          // Attach a metrics observer to enforce the aspect ratio whenever the
          // user resizes the window manually.
          WidgetsBinding.instance.addObserver(_AspectRatioEnforcer(aspectRatio));
        } else {
          // Fallback to fixed size if screen info unavailable.  We still
          // enforce the portrait ratio, but allow arbitrary resizing.
          const double aspectRatio = 9 / 19.5;
          const double height = 960;
          final double width = height * aspectRatio;
          setWindowMinSize(Size(width * 0.3, height * 0.3));
          setWindowFrame(Rect.fromLTWH(100, 100, width, height));
          WidgetsBinding.instance.addObserver(_AspectRatioEnforcer(aspectRatio));
        }
      }

      // debugRepaintRainbowEnabled = true;
      final sharedPreferences = await SharedPreferences.getInstance();
      final eventBus = EventBus();

      runApp(await buildAppWidget(database: db, sharedPreferences: sharedPreferences, eventBus: eventBus));
    },
    (Object error, StackTrace stack) {
      _fatalErrorLogger.e(error, error: error, stackTrace: stack);
    },
  );
}

/// A [WidgetsBindingObserver] that keeps the desktop window locked to a
/// particular aspect ratio whenever the user resizes it.  The approach is
/// simple: watch for metric changes, query the current frame, then immediately
/// adjust whichever dimension drifted away from the target ratio.
///
/// This is necessary because the `window_size` plugin doesn't provide a built‑
/// in API for aspect‑ratio constraints, so we implement one ourselves.
class _AspectRatioEnforcer with WidgetsBindingObserver {
  final double aspectRatio;

  _AspectRatioEnforcer(this.aspectRatio);

  @override
  void didChangeMetrics() {
    // ignore: unawaited_futures
    _enforce();
  }

  Future<void> _enforce() async {
    final info = await getWindowInfo();
    final frame = info.frame;

    final currentRatio = frame.width / frame.height;
    if ((currentRatio - aspectRatio).abs() < 0.005) return; // already close

    double newWidth = frame.width;
    double newHeight = frame.height;

    if (currentRatio > aspectRatio) {
      // window is too wide, shrink width
      newWidth = frame.height * aspectRatio;
    } else {
      // window is too tall, shrink height
      newHeight = frame.width / aspectRatio;
    }

    setWindowFrame(Rect.fromLTWH(frame.left, frame.top, newWidth, newHeight));
  }
}
