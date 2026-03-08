import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;

import 'package:event_bus/event_bus.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';

import 'package:borneo_app/features/scenes/view_models/scenes_view_model.dart';
import 'package:borneo_app/features/scenes/providers/scenes_provider.dart';
import 'package:borneo_app/features/scenes/views/scene_card.dart';
import 'package:borneo_app/features/chores/providers/chores_provider.dart';
import 'package:borneo_app/features/chores/providers/chore_summary_provider.dart';
import 'package:borneo_app/features/chores/views/chore_list.dart';
import 'package:borneo_app/features/chores/views/chore_card.dart';
import 'package:borneo_app/features/chores/models/builtin_chores.dart';

import 'package:borneo_kernel_abstractions/events.dart' show DeviceBoundEvent, DeviceRemovedEvent;

import 'package:borneo_app/core/models/scene_entity.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/features/devices/models/events.dart';
import 'package:borneo_app/core/models/events.dart';
import 'package:borneo_app/core/models/device_statistics.dart';
import 'package:borneo_app/features/chores/models/abstract_chore.dart';
import 'package:borneo_app/core/services/chore_manager.dart';
import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_app/core/providers.dart';
import 'package:lw_wot/wot.dart';

import '../../mocks/mocks.dart';

// ---------------------------------------------------------------------------
// Localisation helper
// ---------------------------------------------------------------------------

class _FakeGettextDelegate extends LocalizationsDelegate<GettextLocalizations> {
  const _FakeGettextDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<GettextLocalizations> load(Locale locale) async => FakeGettext();
  @override
  bool shouldReload(covariant LocalizationsDelegate<GettextLocalizations> old) => false;
}

// ---------------------------------------------------------------------------
// Chore-manager stubs
// ---------------------------------------------------------------------------

class _StaticChoreManager implements IChoreManager {
  final List<AbstractChore> _chores;
  _StaticChoreManager([this._chores = const []]);
  @override
  List<AbstractChore> getAvailableChores() => _chores;
  @override
  Future<void> executeChore(String choreId) async {}
  @override
  Future<void> undoChore(String choreId) async {}
  @override
  Future<bool> hasHistoryForChore(String choreId) async => false;
  @override
  void dispose() {}
}

class _DummyNotification implements IAppNotificationService {
  @override
  void showError(String title, {String? body}) {}
  @override
  void showInfo(String title, {String? body}) {}
  @override
  void showSuccess(String title, {String? body}) {}
  @override
  void showWarning(String title, {String? body}) {}
  @override
  void showNotificationWithAction(String title, {String? body, required Function onTapAction}) {}
}

// ---------------------------------------------------------------------------
// Simple bool toggle notifier (Riverpod 3 replacement for StateProvider<bool>).
// ---------------------------------------------------------------------------

class _BoolNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final _boolNotifierProvider = NotifierProvider<_BoolNotifier, bool>(_BoolNotifier.new);

// ---------------------------------------------------------------------------
// Fake ChoresNotifier for isolated widget tests.
// ---------------------------------------------------------------------------

class _FakeChoresNotifier extends ChoresNotifier {
  final List<AbstractChore> _initialChores;
  _FakeChoresNotifier([this._initialChores = const []]);

  @override
  ChoresState build() => ChoresState(chores: _initialChores, isLoading: false);

  /// Overridden to be a no-op so tests control state manually.
  @override
  Future<void> initialize() async {}

  void setLoadingFlag(bool loading) => state = state.copyWith(isLoading: loading);
  void setChores(List<AbstractChore> chores) => state = state.copyWith(chores: chores);
}

// ---------------------------------------------------------------------------
// Fake ScenesNotifier - overrides build() so no event subscriptions or
// real service calls are made during widget tests.
// ---------------------------------------------------------------------------

class _FakeScenesNotifier extends ScenesNotifier {
  final List<String> switchedTo = [];

  @override
  ScenesState build() => const ScenesState(scenes: []);

  void setScenes(List<SceneSummaryModel> scenes) => state = state.copyWith(scenes: scenes);
  void setLoading(bool v) => state = state.copyWith(isLoading: v);
  void setSwitchingSceneId(String? id) => state = state.copyWith(switchingSceneId: id);

  @override
  Future<void> switchCurrentScene(String newSceneId) async {
    switchedTo.add(newSceneId);
    setSwitchingSceneId(newSceneId);
    setLoading(true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    setSwitchingSceneId(null);
    setLoading(false);
  }
}

// ---------------------------------------------------------------------------
// Helper: build an UncontrolledProviderScope + widget for scene widget tests.
// ---------------------------------------------------------------------------

(ProviderContainer, Widget) _sceneTestScope({required _FakeScenesNotifier notifier, required Widget child}) {
  final container = ProviderContainer(overrides: [scenesProvider.overrideWith(() => notifier)]);
  final widget = UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: const [_FakeGettextDelegate()],
      supportedLocales: const [Locale('en', 'US')],
      home: child,
    ),
  );
  return (container, widget);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Visual / widget behaviour
  // -------------------------------------------------------------------------

  testWidgets('action slot remains constant when loading toggles', (WidgetTester tester) async {
    bool isLoading = false;
    late StateSetter stateSetter;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            stateSetter = setState;
            return Scaffold(
              appBar: AppBar(
                actions: [
                  SizedBox(
                    width: kToolbarHeight,
                    child: isLoading
                        ? const Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_outlined),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    expect(find.byIcon(Icons.add_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.actions?.length, 1);

    stateSetter(() => isLoading = true);
    await tester.pump();

    expect(find.byIcon(Icons.add_outlined), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final appBar2 = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar2.actions?.length, 1);
  });

  testWidgets('card shows spinner while switching and others disabled', (WidgetTester tester) async {
    final now = DateTime.now();
    final a = SceneSummaryModel(
      scene: SceneEntity(id: 'a', name: 'A', isCurrent: false, lastAccessTime: now),
      totalDeviceCount: 0,
      activeDeviceCount: 0,
      isSelected: false,
    );
    final b = SceneSummaryModel(
      scene: SceneEntity(id: 'b', name: 'B', isCurrent: false, lastAccessTime: now),
      totalDeviceCount: 0,
      activeDeviceCount: 0,
      isSelected: false,
    );

    final fakeNotifier = _FakeScenesNotifier();
    final (container, app) = _sceneTestScope(
      notifier: fakeNotifier,
      child: SingleChildScrollView(child: Column(children: [SceneCard(a), SceneCard(b)])),
    );
    addTearDown(container.dispose);

    // Prime the scenes list before first frame so cards are in the right state.
    (container.read(scenesProvider.notifier) as _FakeScenesNotifier).setScenes([a, b]);

    await tester.pumpWidget(app);

    // Simulate the start of a switch to scene 'b'.
    fakeNotifier.setSwitchingSceneId('b');
    fakeNotifier.setLoading(true);
    await tester.pump();

    // Card B should show a progress spinner.
    expect(find.byKey(const Key('scene_spinner_b')), findsOneWidget);

    // Tapping either card should be ignored while busy (onTap == null).
    await tester.tap(find.byKey(const Key('scene_card_A')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('scene_card_B')));
    await tester.tap(find.byKey(const Key('scene_card_B')));
    await tester.pump();
    expect(fakeNotifier.switchedTo, isEmpty);

    // After switch completes spinner should disappear.
    fakeNotifier.setSwitchingSceneId(null);
    fakeNotifier.setLoading(false);
    await tester.pump();
    expect(find.byKey(const Key('scene_spinner_b')), findsNothing);
  });

  testWidgets('chore list absorber toggles with scenes loading state', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        scenesIsLoadingProvider.overrideWith((ref) => ref.watch(_boolNotifierProvider)),
        choresProvider.overrideWith(() => _FakeChoresNotifier()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [_FakeGettextDelegate()],
          supportedLocales: const [Locale('en', 'US')],
          home: const CustomScrollView(slivers: [ChoreList()]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Initial state: no absorber.
    expect(find.byKey(const Key('chore_absorber')), findsNothing);

    container.read(_boolNotifierProvider.notifier).set(true);
    await tester.pump();
    expect(find.byKey(const Key('chore_absorber')), findsOneWidget);

    container.read(_boolNotifierProvider.notifier).set(false);
    await tester.pump();
    expect(find.byKey(const Key('chore_absorber')), findsNothing);
  });

  testWidgets('chores view shows spinner and clears items while loading', (WidgetTester tester) async {
    final chore = PowerOffAllChore(name: 'Power off all');
    final fakeNotifier = _FakeChoresNotifier([chore]);

    final container = ProviderContainer(
      overrides: [
        choreManagerProvider.overrideWithValue(_StaticChoreManager([chore])),
        appNotificationServiceProvider.overrideWithValue(_DummyNotification()),
        eventBusProvider.overrideWithValue(EventBus()),
        deviceManagerProvider.overrideWithValue(
          StubDeviceManager(
            things: [
              _buildThing(id: 'light-1', types: ['OnOffSwitch', 'Light'], on: true, online: true),
            ],
          ),
        ),
        choreSummaryProvider.overrideWith2((arg) => ChoreSummaryNotifier(arg)),
        choresProvider.overrideWith(() => fakeNotifier),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [_FakeGettextDelegate()],
          supportedLocales: const [Locale('en', 'US')],
          home: const Scaffold(body: CustomScrollView(slivers: [ChoreList()])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChoreCard), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // Start a load cycle - spinner appears and chore cards disappear.
    fakeNotifier.setLoadingFlag(true);
    await fakeNotifier.refresh();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ChoreCard), findsNothing);

    // Finish loading - spinner disappears and card reappears.
    fakeNotifier.setLoadingFlag(false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ChoreCard), findsOneWidget);
  });

  testWidgets('chore switch is disabled when applicable device count is zero', (WidgetTester tester) async {
    final chore = PowerOffAllChore(name: 'Power off all');

    final container = ProviderContainer(
      overrides: [
        choreManagerProvider.overrideWithValue(_StaticChoreManager([chore])),
        appNotificationServiceProvider.overrideWithValue(_DummyNotification()),
        eventBusProvider.overrideWithValue(EventBus()),
        deviceManagerProvider.overrideWithValue(
          StubDeviceManager(
            things: [
              _buildThing(id: 'light-1', types: ['OnOffSwitch', 'Light'], on: true, online: false),
            ],
          ),
        ),
        choreSummaryProvider.overrideWith2((arg) => ChoreSummaryNotifier(arg)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [_FakeGettextDelegate()],
          supportedLocales: const [Locale('en', 'US')],
          home: Scaffold(body: ChoreCard(chore)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0'), findsOneWidget);
    final switchWidget = tester.widget<Switch>(find.byKey(Key('chore_switch_${chore.id}')));
    expect(switchWidget.onChanged, isNull);
  });

  // -------------------------------------------------------------------------
  // ScenesNotifier unit tests
  // -------------------------------------------------------------------------

  group('ScenesNotifier ordering', () {
    ProviderContainer makeContainer({
      required StubSceneManager sceneManager,
      EventBus? eventBus,
      StubDeviceManager? deviceManager,
    }) {
      return ProviderContainer(
        overrides: [
          sceneManagerProvider.overrideWithValue(sceneManager),
          deviceManagerProvider.overrideWithValue(deviceManager ?? StubDeviceManager()),
          eventBusProvider.overrideWithValue(eventBus ?? EventBus()),
        ],
      );
    }

    test('current scene is moved to front on initialize', () async {
      final now = DateTime.now();
      final scenes = [
        SceneEntity(id: 'a', name: 'A', isCurrent: false, lastAccessTime: now.subtract(const Duration(days: 2))),
        SceneEntity(id: 'b', name: 'B', isCurrent: true, lastAccessTime: now.subtract(const Duration(days: 1))),
        SceneEntity(id: 'c', name: 'C', isCurrent: false, lastAccessTime: now),
      ];
      final mgr = StubSceneManager(scenes);
      final container = makeContainer(sceneManager: mgr);
      addTearDown(container.dispose);

      await container.read(scenesProvider.notifier).initialize();

      final state = container.read(scenesProvider);
      expect(state.scenes, isNotEmpty);
      expect(state.scenes.first.id, equals(mgr.current.id), reason: 'current scene must be at index 0');
    });

    test('switchCurrentScene resets switchingSceneId after completion', () async {
      final now = DateTime.now();
      final scenes = [
        SceneEntity(id: 'x', name: 'X', isCurrent: true, lastAccessTime: now),
        SceneEntity(id: 'y', name: 'Y', isCurrent: false, lastAccessTime: now),
      ];
      final container = makeContainer(sceneManager: StubSceneManager(scenes));
      addTearDown(container.dispose);

      await container.read(scenesProvider.notifier).initialize();
      expect(container.read(scenesProvider).switchingSceneId, isNull);

      await container.read(scenesProvider.notifier).switchCurrentScene('y');
      expect(container.read(scenesProvider).switchingSceneId, isNull);
    });

    test('device bound/removed events trigger statistics reload', () async {
      final now = DateTime.now();
      final scenes = [SceneEntity(id: 'a', name: 'A', isCurrent: true, lastAccessTime: now)];
      final mgr = StubSceneManager(scenes);
      mgr.statsByScene['a'] = DeviceStatistics(1, 1);
      final deviceMgr = _StubDeviceManager();

      final container = makeContainer(sceneManager: mgr, deviceManager: deviceMgr);
      addTearDown(container.dispose);

      await container.read(scenesProvider.notifier).initialize();
      expect(container.read(scenesProvider).scenes.first.activeDeviceCount, equals(1));

      final boundDevice = DeviceEntity(
        id: 'd1',
        address: Uri.parse('coap://localhost'),
        fingerprint: 'fp',
        sceneID: 'a',
        driverID: 'drv',
        compatible: 'foo',
        name: 'D1',
        model: 'M',
      );

      mgr.statsByScene['a'] = DeviceStatistics(1, 2);
      deviceMgr.allDeviceEvents.fire(DeviceBoundEvent(boundDevice));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(scenesProvider).scenes.first.activeDeviceCount, equals(2));

      mgr.statsByScene['a'] = DeviceStatistics(1, 1);
      deviceMgr.allDeviceEvents.fire(DeviceRemovedEvent(boundDevice));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(scenesProvider).scenes.first.activeDeviceCount, equals(1));
    });

    test('moving device between scenes causes statistics reload', () async {
      final now = DateTime.now();
      final scenes = [
        SceneEntity(id: 'a', name: 'A', isCurrent: true, lastAccessTime: now),
        SceneEntity(id: 'b', name: 'B', isCurrent: false, lastAccessTime: now),
      ];
      final mgr = StubSceneManager(scenes);
      mgr.statsByScene['a'] = DeviceStatistics(1, 1);
      mgr.statsByScene['b'] = DeviceStatistics(0, 0);
      final deviceMgr = _StubDeviceManager();

      final container = makeContainer(sceneManager: mgr, deviceManager: deviceMgr);
      addTearDown(container.dispose);

      await container.read(scenesProvider.notifier).initialize();
      expect(container.read(scenesProvider).scenes.first.activeDeviceCount, equals(1));
      expect(container.read(scenesProvider).scenes.last.activeDeviceCount, equals(0));

      final oldDevice = DeviceEntity(
        id: 'd2',
        address: Uri.parse('coap://localhost'),
        fingerprint: 'fp2',
        sceneID: 'a',
        driverID: 'drv',
        compatible: 'foo',
        name: 'D2',
        model: 'M',
      );
      final movedDevice = DeviceEntity(
        id: 'd2',
        address: Uri.parse('coap://localhost'),
        fingerprint: 'fp2',
        sceneID: 'b',
        driverID: 'drv',
        compatible: 'foo',
        name: 'D2',
        model: 'M',
      );

      mgr.statsByScene['a'] = DeviceStatistics(1, 0);
      mgr.statsByScene['b'] = DeviceStatistics(1, 1);
      deviceMgr.allDeviceEvents.fire(DeviceEntityUpdatedEvent(oldDevice, movedDevice));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(scenesProvider).scenes.first.activeDeviceCount, equals(0));
      expect(container.read(scenesProvider).scenes.last.activeDeviceCount, equals(1));
    });

    test('preserving order does not move newly selected scene to front', () async {
      final now = DateTime.now();
      final scenes = [
        SceneEntity(id: 'a', name: 'A', isCurrent: false, lastAccessTime: now.subtract(const Duration(days: 2))),
        SceneEntity(id: 'b', name: 'B', isCurrent: true, lastAccessTime: now.subtract(const Duration(days: 1))),
        SceneEntity(id: 'c', name: 'C', isCurrent: false, lastAccessTime: now),
      ];
      final mgr = StubSceneManager(scenes);
      final bus = EventBus();
      final container = makeContainer(sceneManager: mgr, eventBus: bus);
      addTearDown(container.dispose);

      await container.read(scenesProvider.notifier).initialize();
      final initialOrder = container.read(scenesProvider).scenes.map((s) => s.id).toList();

      // Simulate a current-scene-changed event as the real manager would fire.
      await mgr.changeCurrent('c');
      bus.fire(
        CurrentSceneChangedEvent(
          SceneEntity(id: 'b', name: 'B', isCurrent: false, lastAccessTime: now.subtract(const Duration(days: 1))),
          mgr.current,
        ),
      );

      // isSelected updates but order must stay the same.
      final afterSelect = container.read(scenesProvider).scenes.map((s) => s.id).toList();
      expect(afterSelect, equals(initialOrder));
      expect(container.read(scenesProvider).scenes.first.id, equals('b'));
      expect(container.read(scenesProvider).scenes[1].id, equals('c'));

      // reload(preserveOrder: true) must also keep the existing order.
      await container.read(scenesProvider.notifier).reload(preserveOrder: true);
      final afterReload = container.read(scenesProvider).scenes.map((s) => s.id).toList();
      expect(afterReload, equals(afterSelect));
    });
  });
}

WotThing _buildThing({required String id, required List<String> types, bool? on, bool? online}) {
  final thing = WotThing(id: id, title: id, type: types, description: 'test thing');
  if (on != null) {
    thing.addProperty(
      WotProperty<bool>(
        thing: thing,
        name: 'on',
        value: WotValue<bool>(initialValue: on),
        metadata: WotPropertyMetadata(type: 'boolean'),
      ),
    );
  }
  if (online != null) {
    thing.addProperty(
      WotProperty<bool>(
        thing: thing,
        name: 'online',
        value: WotValue<bool>(initialValue: online),
        metadata: WotPropertyMetadata(type: 'boolean', readOnly: true),
      ),
    );
  }
  return thing;
}

// ---------------------------------------------------------------------------
// StubDeviceManager subclass alias
// ---------------------------------------------------------------------------

class _StubDeviceManager extends StubDeviceManager {}
