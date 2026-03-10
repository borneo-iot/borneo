import 'dart:collection';

import 'package:borneo_app/features/devices/models/device_module_metadata.dart';
import 'package:borneo_app/core/services/devices/device_module_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:integration_test/integration_test.dart';

import 'package:borneo_app/main.dart' as app;
import 'package:borneo_kernel_abstractions/network.dart';

// ---------------------------------------------------------------------------
// Fake implementations for testing
// ---------------------------------------------------------------------------

class _FakeRegistry implements IDeviceModuleRegistry {
  @override
  UnmodifiableMapView<String, DeviceModuleMetadata> get metaModules => UnmodifiableMapView({});
}

class _NoOpNetworkMonitor implements INetworkMonitor {
  @override
  Stream<NetworkSnapshot> get onNetworkChanged => const Stream<NetworkSnapshot>.empty();
  @override
  Future<NetworkSnapshot> getCurrentSnapshot() async =>
      const NetworkSnapshot(localDiscoveryAvailable: false, fingerprint: '');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds the full app widget backed by an in-memory database, suitable for
/// integration tests that must not touch the filesystem.
Future<Widget> _buildTestApp({IDeviceModuleRegistry? registry, INetworkMonitor? networkMonitor}) async {
  // Force English locale so text-matching assertions are language-independent.
  SharedPreferences.setMockInitialValues({'app.locale': 'en_US'});
  final db = await databaseFactoryMemory.openDatabase('test_${DateTime.now().microsecondsSinceEpoch}.db');
  return app.buildAppWidget(
    database: db,
    sharedPreferences: await SharedPreferences.getInstance(),
    deviceModuleRegistry: registry ?? _FakeRegistry(),
    networkMonitor: networkMonitor ?? _NoOpNetworkMonitor(),
  );
}

/// Repeatedly pumps the tester until [finder] is found or the [timeout]
/// expires.  This is more reliable than `pumpAndSettle` when the UI shows an
/// indefinite animation (e.g. a loading spinner) that would otherwise keep
/// scheduling frames.
Future<void> _waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (tester.any(finder)) return;
  }
  // Final check to produce a sensible failure message
  await tester.pump();
  expect(tester.any(finder), true, reason: 'Expected $finder to appear within $timeout');
}

/// Register device-group related integration tests with a caller.
///
/// The binding is initialized by the aggregator so this file only provides
/// a function that adds the relevant `testWidgets` case(s).
void deviceGroupTests() {
  testWidgets('Manage device groups via UI', (WidgetTester tester) async {
    await tester.pumpWidget(await _buildTestApp());
    await tester.pumpAndSettle();

    // navigate to devices tab by tapping bottom navigation icon
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.device_hub_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.device_hub_outlined));
    await tester.pumpAndSettle();

    // Devices screen should be fully initialized before we continue.  The title
    // contains the current scene name which is "My Home" in the fresh
    // in-memory database.
    await _waitFor(tester, find.text('Devices in My Home'));

    // open add menu and select Add Devices Group
    await tester.tap(find.byIcon(Icons.add_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu_item_add_group')));
    await tester.pumpAndSettle();

    // fill in group name and submit
    await tester.enterText(find.byKey(const Key('field_group_name')), 'Test Group');
    // Ensure the form field has focus and text committed before tapping submit
    await tester.pump();
    // Verify submit button is present before tapping
    expect(find.byKey(const Key('btn_submit')), findsOneWidget);
    await tester.tap(find.byKey(const Key('btn_submit')));
    // give database and event bus a moment to complete, then wait for list update
    // Use multiple pumps so that: (1) async submit completes, (2) navigation
    // animations play out, and (3) the Selector widget rebuilds with new data.
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // At this point GroupEditScreen should have been popped (navigator.pop(true))
    // and GroupedDevicesViewModel.refresh() should have been called.
    // Verify we are back on the devices screen.
    await _waitFor(tester, find.text('Test Group'), timeout: const Duration(seconds: 10));

    // edit the group
    await tester.tap(find.byKey(const Key('btn_edit_group_Test Group')));
    await tester.pumpAndSettle();

    // change name and submit
    await tester.enterText(find.byKey(const Key('field_group_name')), 'Updated Group');
    await tester.tap(find.byKey(const Key('btn_submit')));
    await tester.pump(const Duration(milliseconds: 500));
    await _waitFor(tester, find.text('Updated Group'));

    expect(find.text('Updated Group'), findsOneWidget);

    // delete the group
    await tester.tap(find.byKey(const Key('btn_edit_group_Updated Group')));
    await tester.pumpAndSettle();

    // tap delete icon in app bar
    await tester.tap(find.byKey(const Key('btn_delete_group')));
    await tester.pumpAndSettle();

    // confirm deletion (confirmation sheet uses btn_ok key)
    await tester.tap(find.byKey(const Key('btn_ok')));
    await tester.pump(const Duration(milliseconds: 1000));
    // group should no longer be present
    expect(find.text('Updated Group'), findsNothing);
  });
}

// standalone entrypoint so this file can be run directly in CI
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  deviceGroupTests();
}
