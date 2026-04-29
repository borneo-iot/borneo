import 'package:borneo_app/features/devices/models/device_module_metadata.dart';
import 'package:borneo_app/routes/route_manager.dart';
import 'package:borneo_kernel_abstractions/device.dart';
import 'package:borneo_kernel_abstractions/driver.dart';
import 'package:borneo_kernel_abstractions/models/discovered_device.dart';
import 'package:borneo_kernel_abstractions/models/driver_descriptor.dart';
import 'package:borneo_kernel_abstractions/models/heartbeat_method.dart';
import 'package:borneo_kernel_abstractions/models/supported_device_descriptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:logger/logger.dart';

import '../mocks/mocks.dart';

class _TestDeviceModuleMetadata extends DeviceModuleMetadata {
  _TestDeviceModuleMetadata()
    : super(
        id: 'test-driver',
        name: 'Test Driver',
        driverDescriptor: const DriverDescriptor(
          id: 'test-driver',
          name: 'Test Driver',
          heartbeatMethod: HeartbeatMethod.poll,
          discoveryMethod: MdnsDeviceDiscoveryMethod('_test._tcp'),
          matches: _matches,
          factory: _factory,
        ),
        detailsViewBuilder: (_) => const Scaffold(body: Text('DETAIL PAGE')),
        detailsViewModelBuilder: (_, _) => throw UnimplementedError(),
        deviceIconBuilder: (_, _, _) => const SizedBox.shrink(),
        primaryStateIconBuilder: (_, _) => const SizedBox.shrink(),
        secondaryStatesBuilder: (_, _) => const <Widget>[],
        createSummaryVM: (_, _, _, _) => throw UnimplementedError(),
        createWotThing: (_, _, {logger, cancelToken}) => throw UnimplementedError(),
      );

  static SupportedDeviceDescriptor? _matches(DiscoveredDevice device) => null;
  static Driver _factory({Logger? logger}) => _TestDriver(logger: logger);
}

class _TestDriver extends Driver {
  const _TestDriver({super.logger});

  @override
  void dispose() {}

  @override
  Future<bool> heartbeat(Device dev, {CancellationToken? cancelToken}) async => false;

  @override
  Future<bool> probe(Device dev, {CancellationToken? cancelToken}) async => false;

  @override
  Future<bool> remove(Device dev, {CancellationToken? cancelToken}) async => false;
}

void main() {
  testWidgets('RouteManager resolves device detail routes with device id suffix', (tester) async {
    final registry = StubDeviceModuleRegistry({'test-driver': _TestDeviceModuleMetadata()});
    final routeManager = RouteManager(registry);
    const deviceRoute = '/devices/test-driver/device-123';

    await tester.pumpWidget(
      MaterialApp(
        home: _RoutePushHost(
          onBuild: (context) {
            Navigator.of(context).push(routeManager.onGenerateRoute(RouteSettings(name: deviceRoute)));
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('DETAIL PAGE'), findsOneWidget);
  });
}

class _RoutePushHost extends StatefulWidget {
  final void Function(BuildContext context) onBuild;

  const _RoutePushHost({required this.onBuild});

  @override
  State<_RoutePushHost> createState() => _RoutePushHostState();
}

class _RoutePushHostState extends State<_RoutePushHost> {
  bool _didPush = false;

  @override
  Widget build(BuildContext context) {
    if (!_didPush) {
      _didPush = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onBuild(context);
        }
      });
    }

    return const SizedBox.shrink();
  }
}
