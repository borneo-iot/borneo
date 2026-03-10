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

/// Scenes related integration tests.
void scenesTests() {
  testWidgets('Manage scenes via UI', (WidgetTester tester) async {
    await tester.pumpWidget(await _buildTestApp());
    await tester.pumpAndSettle();

    // navigate to scenes tab by tapping bottom navigation icon.  The
    // active tab may show the filled house icon, so try to tap whichever is
    // present.
    await tester.pump(const Duration(seconds: 1));
    final filled = find.byIcon(Icons.house);
    final outlined = find.byIcon(Icons.house_outlined);
    if (tester.any(outlined)) {
      await tester.tap(outlined);
    } else {
      await tester.tap(filled);
    }
    await tester.pumpAndSettle();

    // the first card corresponds to the default scene "My Home"
    await _waitFor(tester, find.byKey(const Key('scene_card_My Home')));

    // add a new scene
    await tester.tap(find.byKey(const Key('btn_add_scene')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('field_scene_name')), 'Test Scene');
    await tester.pump();
    expect(find.byKey(const Key('btn_submit')), findsOneWidget);
    await tester.tap(find.byKey(const Key('btn_submit')));

    // give database and animations a moment
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _waitFor(tester, find.byKey(const Key('scene_card_Test Scene')), timeout: const Duration(seconds: 10));

    // Switch back to the original scene.  After the new scene is created it
    // becomes selected and may push the old card off-screen.
    const targetKey = Key('scene_card_My Home');
    // Scroll the horizontal list back until the 'My Home' card is built and
    // visible.  scrollUntilVisible / dragUntilVisible call element(finder)
    // immediately, which throws when the card hasn't been built yet by the
    // lazy ListView (it's off-screen).  Use a simple drag loop instead.
    final scrollableFinder = find.descendant(
      of: find.byKey(const Key('scene_list')),
      matching: find.byType(Scrollable),
    );
    for (int i = 0; i < 10; i++) {
      if (tester.any(find.byKey(targetKey))) break;
      await tester.drag(scrollableFinder, const Offset(300, 0));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(targetKey));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // ensure current scene indicator moved (the edit button should show on selected card)
    expect(find.byKey(const Key('btn_edit_scene_My Home')), findsOneWidget);
    // On narrow/mobile viewports the "Test Scene" card will be off-screen and
    // not built, but on wide desktop windows it can remain visible.  Don't
    // assert anything here; the scroll loop below handles both cases.

    // scroll back to "Test Scene" to bring its card into the tree
    for (int i = 0; i < 10; i++) {
      if (tester.any(find.byKey(const Key('scene_card_Test Scene')))) break;
      await tester.drag(scrollableFinder, const Offset(-300, 0));
      await tester.pumpAndSettle();
    }
  });
}

// standalone runner entrypoint
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  scenesTests();
}
