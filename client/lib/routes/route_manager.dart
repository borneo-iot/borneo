// lib/routes/route_manager.dart

import 'package:borneo_app/features/devices/models/device_module_metadata.dart';
import 'package:borneo_app/core/services/devices/device_module_registry.dart';
import 'package:borneo_app/features/devices/views/device_discovery_screen.dart';
import 'package:flutter/material.dart';

import '../routes/app_routes.dart';
import '../routes/platform_page_route.dart';
import '../main/views/main_screen.dart';
import '../features/devices/views/devices_screen.dart';
import '../features/my/views/my_screen.dart';

class RouteManager {
  final Map<String, WidgetBuilder> _routes = {
    AppRoutes.kMainScreen: (_) => MainScreen(),
    // Updated to use provider-based ScenesScreen is handled elsewhere (main_screen tab). If needed as a route:
    // AppRoutes.kScreens: (_) => const ScenesScreen(),
    AppRoutes.kDevices: (_) => const DevicesScreen(),
    AppRoutes.kDeviceDiscovery: (_) => const DeviceDiscoveryScreen(),
    AppRoutes.kAccount: (_) => const MyScreen(),
  };

  final IDeviceModuleRegistry _modules;

  RouteManager(this._modules) {
    for (final x in _modules.metaModules.entries) {
      _routes[AppRoutes.makeDeviceScreenRoute(x.key)] = (context) => _makeDeviceDetailsScreenBuilder(context, x.value);
    }
  }

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final builder = _routes[settings.name];
    if (builder != null) {
      return platformPageRoute(builder: builder, settings: settings);
    } else {
      return platformPageRoute(builder: (_) => const DevicesScreen(), settings: settings);
    }
  }

  Widget _makeDeviceDetailsScreenBuilder(BuildContext context, DeviceModuleMetadata meta) {
    return meta.detailsViewBuilder(context);
  }
}
