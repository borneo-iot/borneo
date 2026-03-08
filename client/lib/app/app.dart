import 'dart:async';
import 'package:borneo_app/core/events/app_events.dart';
import 'package:borneo_app/core/services/chore_manager_impl.dart';
import 'package:borneo_app/core/services/clock.dart';
import 'package:borneo_app/core/services/app_notification_service_impl.dart';
import 'package:borneo_app/core/services/devices/device_manager_impl.dart';
import 'package:borneo_app/core/services/group_manager_impl.dart';
import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_app/core/services/scene_manager_impl.dart';
import 'package:borneo_app/core/services/url_launcher_service.dart';
import 'package:borneo_app/main/views/main_screen.dart';
import 'package:borneo_kernel_abstractions/kernel.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gettext/flutter_gettext.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:sembast/sembast.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:toastification/toastification.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../routes/route_manager.dart';
import '../core/services/blob_manager.dart';
import '../core/services/devices/device_manager.dart';
import '../core/services/group_manager.dart';
import '../core/services/chore_manager.dart';
import '../core/services/scene_manager.dart';
import '../features/devices/providers/new_device_candidates_store.dart';
import 'package:borneo_app/core/services/devices/device_module_registry.dart';
import 'package:borneo_app/core/config/language_config.dart';

final kSupportedLocales = LanguageConfig.supportedLocales;

class BorneoApp extends StatefulWidget {
  /// The shared event bus used by both Riverpod and provider consumers.
  final EventBus globalEventBus;

  final Locale? initialLocale;
  const BorneoApp({super.key, required this.globalEventBus, this.initialLocale});

  @override
  State<BorneoApp> createState() => _BorneoAppState();
}

class _BorneoAppState extends State<BorneoApp> {
  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale;
  late StreamSubscription _localeSub;
  late StreamSubscription _themeSub;
  late StreamSubscription _tempUnitSub;
  ThemeData _currentTheme = ThemeData();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Only trigger a rebuild if the loaded theme mode differs from the current
    // default to avoid a spurious rebuild that can upset nested navigators and
    // cause stateless-widget form keys to be recreated.
    _loadThemeMode().then((mode) {
      if (mode != _themeMode) setState(() => _themeMode = mode);
    });
    // Apply the pre-loaded initial locale synchronously so the first frame
    // already uses the correct locale (avoids race with async _loadLocale).
    _locale = widget.initialLocale;
    _loadLocale().then((loc) {
      // Only trigger a rebuild if the locale actually differs to avoid a
      // spurious second rebuild that can upset nested navigators.
      if (loc != _locale) setState(() => _locale = loc);
    });
    _localeSub = widget.globalEventBus.on<AppLocaleChangedEvent>().listen((event) {
      setState(() {
        _locale = event.locale;
      });
    });
    _themeSub = widget.globalEventBus.on<ThemeChangedEvent>().listen((event) {
      setState(() {
        _themeMode = event.themeMode;
      });
    });
    _tempUnitSub = widget.globalEventBus.on<AppTemperatureUnitChangedEvent>().listen((event) {
      // rebuilding the root forces every widget/provider under MaterialApp
      // to rebuild so that new temperature formatting takes effect even if
      // they don't explicitly observe the service. this mirrors how
      // language/theme changes work and gives the impression of a "soft
      // restart".
      setState(() {});
    });
  }

  @override
  void dispose() {
    _localeSub.cancel();
    _themeSub.cancel();
    _tempUnitSub.cancel();
    super.dispose();
  }

  Future<ThemeMode> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt('app.brightness');
    if (idx != null && idx >= 0 && idx < ThemeMode.values.length) {
      return ThemeMode.values[idx];
    }
    return ThemeMode.system;
  }

  Future<Locale?> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final localeStr = prefs.getString('app.locale');
    return LanguageConfig.languageCodeToLocale(localeStr);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<EventBus>(create: (_) => widget.globalEventBus),
        Provider<IBlobManager>(create: (_) => FlutterAppBlobManager()),
      ],
      child: Builder(
        builder: (context) {
          return MaterialApp(
            title: 'Borneo Aqua',
            navigatorKey: _navigatorKey,
            //theme: BorneoTheme(Theme.of(context).textTheme).light(),
            //darkTheme: BorneoTheme(Theme.of(context).textTheme).dark(),
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff493b72), brightness: Brightness.light),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff493b72), brightness: Brightness.dark),
              useMaterial3: true,
            ),
            themeMode: _themeMode,
            locale: _locale,
            supportedLocales: kSupportedLocales,
            onGenerateRoute: context.read<RouteManager>().onGenerateRoute,
            debugShowCheckedModeBanner: false,
            localizationsDelegates: [
              GettextLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            builder: (context, child) {
              final gt = GettextLocalizations.of(context);
              final theme = Theme.of(context);
              _currentTheme = theme;
              final effectiveBrightness = _themeMode == ThemeMode.dark
                  ? Brightness.dark
                  : (_themeMode == ThemeMode.light ? Brightness.light : theme.brightness);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                SystemChrome.setSystemUIOverlayStyle(
                  SystemUiOverlayStyle(
                    statusBarColor: Colors.transparent,
                    statusBarIconBrightness: theme.brightness,
                    systemNavigationBarColor: theme.colorScheme.surfaceContainer,
                    /*
                    effectiveBrightness == Brightness.light
                        ? Colors.white
                        : theme.colorScheme.surfaceContainer,
                        */
                    systemNavigationBarIconBrightness: effectiveBrightness == Brightness.light
                        ? Brightness.dark
                        : Brightness.light,
                  ),
                );
              });
              return MultiProvider(
                providers: [
                  Provider<GettextLocalizations>(create: (context) => gt),

                  Provider<IAppNotificationService>(
                    create: (_) =>
                        AppNotificationServiceImpl(getTheme: () => _currentTheme, navigatorKey: _navigatorKey),
                  ),

                  Provider<UrlLauncherService>(
                    create: (context) => UrlLauncherService(
                      notification: Provider.of<IAppNotificationService>(context, listen: false),
                      logger: Provider.of<Logger>(context, listen: false),
                    ),
                    lazy: false,
                  ),

                  // Here >>> register all providers that need to access the gettext interface <<<
                  // SceneManager
                  Provider<ISceneManager>(
                    create: (context) => SceneManagerImpl(
                      gt,
                      context.read<Database>(),
                      context.read<EventBus>(),
                      context.read<IBlobManager>(),
                      clock: context.read<IClock>(),
                      logger: context.read<Logger>(),
                    ),
                  ),

                  // GroupManager
                  Provider<IGroupManager>(
                    create: (context) => GroupManagerImpl(
                      context.read<Logger>(),
                      context.read<EventBus>(),
                      context.read<Database>(),
                      context.read<ISceneManager>(),
                    ),
                  ),

                  // DeviceManager
                  Provider<IDeviceManager>(
                    create: (context) => DeviceManagerImpl(
                      context.read<Database>(),
                      context.read<IKernel>(),
                      context.read<EventBus>(),
                      context.read<ISceneManager>(),
                      context.read<IGroupManager>(),
                      context.read<IDeviceModuleRegistry>(),
                      gettext: gt,
                      logger: context.read<Logger>(),
                    ),
                    dispose: (context, dm) => dm.dispose(),
                  ),

                  ChangeNotifierProvider<NewDeviceCandidatesStore>(
                    create: (context) => NewDeviceCandidatesStore(context.read<IDeviceManager>()),
                    lazy: false,
                  ),

                  // ChoreManager
                  Provider<IChoreManager>(
                    create: (context) => ChoreManagerImpl(
                      context.read<EventBus>(),
                      context.read<Database>(),
                      context.read<ISceneManager>(),
                      context.read<IDeviceManager>(),
                      clock: context.read<IClock>(),
                      logger: context.read<Logger>(),
                      gettext: gt,
                    ),
                    dispose: (context, rm) => rm.dispose(),
                    lazy: true,
                  ),
                ],
                child: ToastificationWrapper(
                  config: ToastificationConfig(animationDuration: Duration(milliseconds: 300), maxToastLimit: 3),
                  child: child!,
                ),
              );
            },
            home: MainScreen(),
          );
        },
      ),
    );
  }
}
