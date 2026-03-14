import 'dart:async';
import 'dart:io';
import 'package:borneo_app/core/events/app_events.dart';
import 'package:borneo_app/core/services/local_service.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/base_lyfi_device_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/settings_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/sun_editor_view_model.dart';
import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';
import 'package:intl/intl.dart';

import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/manual_editor_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/schedule_editor_view_model.dart';

import 'editor/ieditor.dart';

enum EditorStatus { idle, loading, ready, error }

@immutable
class EditorState {
  final LyfiMode mode;
  final EditorStatus status;
  final IEditor? editor;
  final Object? error;

  const EditorState({required this.mode, required this.status, required this.editor, this.error});

  EditorState copyWith({
    LyfiMode? mode,
    EditorStatus? status,
    IEditor? editor,
    Object? error,
    bool clearError = false,
  }) {
    return EditorState(
      mode: mode ?? this.mode,
      status: status ?? this.status,
      editor: editor ?? this.editor,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class LyfiViewModel extends BaseLyfiDeviceViewModel {
  static const initializationTimeout = Duration(seconds: 5);
  static const Duration _commandTimeout = Duration(seconds: 3);
  static const Duration _rapidProbeTimeout = Duration(seconds: 1);
  static const Duration _rapidProbeInterval = Duration(milliseconds: 600);
  static const int _rapidProbeAttempts = 3;
  static const int tempMax = 105;
  static final int tempSetpoint = 45;

  static final DateFormat deviceDateFormat = DateFormat('yyyy-MM-dd HH:mm');

  bool _isDisposed = false;

  final ILocaleService localeService;
  Future<void>? _rapidProbeTask;

  Duration _temporaryDuration = Duration.zero;
  Duration get temporaryDuration => _temporaryDuration;

  Duration _temporaryRemaining = Duration.zero;
  Duration get temporaryRemaining => _temporaryRemaining;

  Duration get commandTimeout => _commandTimeout;

  bool get canLockOrUnlock => !isBusy && !isSuspectedOffline && isOn;
  bool get canUnlock =>
      !isBusy &&
      super.isOnline &&
      !isSuspectedOffline &&
      isOn &&
      isLocked &&
      (super.state == LyfiState.normal || super.state == LyfiState.temporary);

  bool get canChangeSettings =>
      !isBusy &&
      super.isOnline &&
      !isSuspectedOffline &&
      isLocked &&
      (super.state == LyfiState.normal || super.state == LyfiState.temporary);

  bool get canTimedOn => !isBusy && !isSuspectedOffline && (!isOn || super.mode == LyfiMode.scheduled);

  EditorState _editorState = const EditorState(mode: LyfiMode.manual, status: EditorStatus.idle, editor: null);
  EditorState get editorState => _editorState;
  final ScheduleTable scheduledInstants = [];
  final ScheduleTable sunInstants = [];
  final ScheduleTable moonInstants = [];

  int? get currentTempRaw => _currentTemperature;
  int? get currentTemp => _currentTemperature == null
      ? null
      : localeService.convertTemperatureValue(_currentTemperature!.toDouble()).toInt();

  String get temperatureUnitText => localeService.temperatureUnitText;

  bool get isMoonTime => currentMoonBrightness > 0;

  double _getCurrentBrightness(List<ScheduledInstant> instants, Duration currentTime) {
    if (instants.isEmpty) return 0.0;
    for (int i = 0; i < instants.length - 1; i++) {
      final start = instants[i];
      final end = instants[i + 1];
      if (currentTime >= start.instant &&
          currentTime <= end.instant &&
          start.color.isNotEmpty &&
          end.color.isNotEmpty) {
        final startBrightness = start.color[0].toDouble();
        final endBrightness = end.color[0].toDouble();
        final total = end.instant - start.instant;
        final elapsed = currentTime - start.instant;
        final ratio = elapsed.inMilliseconds / total.inMilliseconds;
        return startBrightness + (endBrightness - startBrightness) * ratio;
      }
    }
    return 0.0;
  }

  double get currentMoonBrightness {
    final now = DateTime.now();
    final today = Duration(hours: now.hour, minutes: now.minute, seconds: now.second);
    return _getCurrentBrightness(moonInstants, today);
  }

  double get currentSunBrightness {
    final now = DateTime.now();
    final today = Duration(hours: now.hour, minutes: now.minute, seconds: now.second);
    return _getCurrentBrightness(sunInstants, today) / 100.0; // assuming color[0] is 0-100
  }

  String? get nextMoonTime {
    if (moonInstants.isEmpty) return null;
    final sorted = moonInstants.toList()..sort((a, b) => a.instant.compareTo(b.instant));
    final first = sorted.first;
    final duration = first.instant;
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }

  // LyFi device status and info
  double? _fanPowerRatio = 0.0;
  double? get fanPowerRatio => _fanPowerRatio;

  FanMode? _fanMode;
  FanMode? get fanMode => _fanMode;

  StreamSubscription<String>? _fanModeSubscription;

  StreamSubscription<int>? _fanPowerSubscription;

  int? _currentTemperature;
  StreamSubscription<int?>? _temperatureSubscription;

  /// fired when the global temperature unit preference changes. we simply
  /// forward the notification so any widgets that depend on
  /// `temperatureUnitText` or `currentTemp` will rebuild via
  /// `ChangeNotifier` notifications.
  StreamSubscription<AppTemperatureUnitChangedEvent>? _temperatureUnitSub;

  StreamSubscription<double?>? _voltageSubscription;
  StreamSubscription<double?>? _currentSubscription;
  StreamSubscription<double?>? _powerSubscription;
  StreamSubscription<Duration>? _temporaryDurationSubscription;
  StreamSubscription<Duration>? _temporaryRemainingSubscription;
  StreamSubscription<List<int>>? _colorSubscription;

  StreamSubscription<String>? _stateSubscription;
  StreamSubscription<String>? _modeSubscription;
  StreamSubscription<ScheduleTable>? _sunScheduleSubscription;
  StreamSubscription<ScheduleTable>? _moonScheduleSubscription;

  double _overallBrightness = 0;
  double get overallBrightness => _overallBrightness;

  final List<ValueNotifier<int>> _channels = [];
  List<ValueNotifier<int>> get channels => _channels;

  bool get canChangeMoonSettings => !isBusy && isOnline && isOn && !isSuspectedOffline && isLocked;
  bool get canChangeAcclimationSettings => !isBusy && isOnline && isOn && !isSuspectedOffline && isLocked;

  LyfiViewModel({
    required super.deviceManager,
    required super.globalEventBus,
    required super.notification,
    required super.wotThing,
    required this.localeService,
    required super.gt,
    super.logger,
  });

  Future<void> updateChannelValue(int index, int value) async {
    if (index >= 0 && index < _channels.length) {
      _channels[index].value = value;
    }
  }

  Future<T> executeLyfiCommand<T>(
    Future<T> Function() action, {
    Duration? timeout,
    bool resetSuspectedOnSuccess = true,
  }) {
    return runDeviceCommand(
      action,
      timeout: timeout ?? _commandTimeout,
      resetSuspectedOnSuccess: resetSuspectedOnSuccess,
    );
  }

  @override
  void onDeviceSuspectedOffline() {
    super.onDeviceSuspectedOffline();
    if (_rapidProbeTask != null || boundDevice == null || isDisposed) {
      return;
    }
    _rapidProbeTask = _runRapidProbe().whenComplete(() {
      _rapidProbeTask = null;
    });
  }

  Future<void> _runRapidProbe() async {
    for (var attempt = 0; attempt < _rapidProbeAttempts; attempt++) {
      if (isDisposed || boundDevice == null || !super.isOnline) {
        return;
      }

      try {
        await super.lyfiDeviceApi.getLyfiStatus(boundDevice!.device).timeout(_rapidProbeTimeout);
        super.clearSuspectedOffline();
        return;
      } on TimeoutException {
        // continue to next attempt
      } on SocketException catch (e, stackTrace) {
        logger?.w('Lyfi rapid probe socket error: $e', error: e, stackTrace: stackTrace);
      } on IOException catch (e, stackTrace) {
        logger?.w('Lyfi rapid probe IO error: $e', error: e, stackTrace: stackTrace);
      } catch (e, stackTrace) {
        logger?.w('Lyfi rapid probe unexpected error: $e', error: e, stackTrace: stackTrace);
      }

      if (attempt < _rapidProbeAttempts - 1) {
        await Future.delayed(_rapidProbeInterval);
      }
    }
    // All probe attempts exhausted without success. Trigger a reconnect so
    // the UI shows a countdown and the user can see/retry the reconnect,
    // rather than being stuck indefinitely in the "Connection unstable" overlay
    // with no interactive controls.
    logger?.w('Lyfi rapid probe: all $_rapidProbeAttempts attempts failed; triggering reconnect');
    if (!isDisposed && !isReconnecting) {
      unawaited(reconnect());
    }
  }

  @override
  Future<void> onInitialize() async {
    await super.onInitialize();

    // listen for unit change so we can refresh any formatted values
    _temperatureUnitSub = globalEventBus.on<AppTemperatureUnitChangedEvent>().listen((event) {
      notifyListeners();
    });

    _fanPowerSubscription =
        super.lyfiThing.findProperty('fanPower')?.value.onUpdate.listen((_) {
              final power = super.lyfiThing.getProperty<int>('fanPower');
              _fanPowerRatio = power?.toDouble();
              notifyListeners();
            })
            as StreamSubscription<int>?;

    _temperatureSubscription =
        super.lyfiThing.findProperty('temperature')?.value.onUpdate.listen((value) {
              _currentTemperature = value;
              notifyListeners();
            })
            as StreamSubscription<int?>?;

    _fanModeSubscription =
        super.lyfiThing.findProperty('fanMode')?.value.onUpdate.listen((value) {
              _fanMode = FanMode.values.firstWhere((e) => e.name == value);
              notifyListeners();
            })
            as StreamSubscription<String>?;

    _voltageSubscription =
        super.lyfiThing.findProperty('voltage')?.value.onUpdate.listen((value) {
              super.currentVoltage.value = value;
            })
            as StreamSubscription<double?>?;

    _currentSubscription =
        super.lyfiThing.findProperty('current')?.value.onUpdate.listen((value) {
              currentCurrent.value = value;
            })
            as StreamSubscription<double?>?;

    _powerSubscription =
        super.lyfiThing.findProperty('power')?.value.onUpdate.listen((value) {
              currentWatts.value = value;
            })
            as StreamSubscription<double?>?;

    _colorSubscription =
        super.lyfiThing.findProperty('color')?.value.onUpdate.listen((value) {
              _applyColorUpdate(value);
            })
            as StreamSubscription<List<int>>?;

    _temporaryDurationSubscription =
        super.lyfiThing.findProperty('temporaryDuration')?.value.onUpdate.listen((value) {
              _temporaryDuration = value;
              notifyListeners();
            })
            as StreamSubscription<Duration>?;

    _temporaryRemainingSubscription =
        super.lyfiThing.findProperty('temporaryRemaining')?.value.onUpdate.listen((value) {
              _temporaryRemaining = value;
              notifyListeners();
            })
            as StreamSubscription<Duration>?;

    _stateSubscription =
        super.lyfiThing.findProperty('state')?.value.onUpdate.listen((value) => _onStateChanged(value))
            as StreamSubscription<String>?;

    _modeSubscription =
        super.lyfiThing.findProperty('mode')?.value.onUpdate.listen((value) => _onModeChanged(value))
            as StreamSubscription<String>?;

    _sunScheduleSubscription =
        super.lyfiThing.findProperty('sunSchedule')?.value.onUpdate.listen((value) {
              sunInstants
                ..clear()
                ..addAll(value);
              notifyListeners();
            })
            as StreamSubscription<ScheduleTable>?;

    _moonScheduleSubscription =
        super.lyfiThing.findProperty('moonSchedule')?.value.onUpdate.listen((value) {
              moonInstants
                ..clear()
                ..addAll(value);
              notifyListeners();
            })
            as StreamSubscription<ScheduleTable>?;

    // Set initial values
    _fanPowerRatio = super.lyfiThing.getProperty<int>('fanPower')?.toDouble();
    _currentTemperature = super.lyfiThing.getProperty<int?>('temperature');
    _fanMode = FanMode.values.firstWhere((e) => e.name == super.lyfiThing.getProperty<String>('fanMode'));
    super.currentVoltage.value = super.lyfiThing.getProperty<double?>('voltage');
    currentCurrent.value = super.lyfiThing.getProperty<double?>('current');
    currentWatts.value = super.lyfiThing.getProperty<double?>('power');
    _temporaryDuration = super.lyfiThing.getProperty<Duration>('temporaryDuration')!;
    _temporaryRemaining = super.lyfiThing.getProperty<Duration>('temporaryRemaining')!;

    //_channels.length * lyfiBrightnessMax.toDouble();
    _initializeChannels();

    _editorState = _editorState.copyWith(mode: super.mode);

    moonInstants
      ..clear()
      ..addAll(super.lyfiThing.getProperty<ScheduleTable>('moonSchedule')!);

    _syncScheduleTables(mode: super.mode, force: true);

    // Update schedule
    // final schedule = await _deviceApi.getSchedule(boundDevice.device);
    if (!super.isLocked) {
      await _toggleEditor(super.mode);
    }
  }

  @override
  void dispose() {
    //
    if (!_isDisposed) {
      _temperatureUnitSub?.cancel();
      _fanModeSubscription?.cancel();
      _fanPowerSubscription?.cancel();
      _temperatureSubscription?.cancel();
      _voltageSubscription?.cancel();
      _currentSubscription?.cancel();
      _powerSubscription?.cancel();
      _temporaryDurationSubscription?.cancel();
      _temporaryRemainingSubscription?.cancel();
      _colorSubscription?.cancel();
      _stateSubscription?.cancel();
      _modeSubscription?.cancel();
      _sunScheduleSubscription?.cancel();
      _moonScheduleSubscription?.cancel();
      for (final cvn in _channels) {
        cvn.dispose();
      }
      if (super.isOnline && !super.isLocked && !isSuspectedOffline) {
        try {
          if (super.state != LyfiState.normal) {
            super.setState(LyfiState.normal);
          }
        } catch (e, stackTrace) {
          logger?.e('Failed to setMode of the device(${super.deviceEntity})', error: e, stackTrace: stackTrace);
        }
      }
      /*
    for (final ch in _channels) {
      ch.dispose();
    }
    */
      if (_editorState.editor != null) {
        _editorState.editor!.dispose();
        _editorState = _editorState.copyWith(editor: null, status: EditorStatus.idle, clearError: true);
      }
      super.dispose();
      _isDisposed = true;
    }
  }

  @override
  Future<void> onDeviceBound() async {
    super.onDeviceBound();

    if (boundDevice == null) {
      return;
    }

    _editorState = _editorState.copyWith(mode: super.mode);

    _syncScheduleTables(mode: super.mode, force: true);

    _initializeChannels();

    // Update schedule
    if (!super.isLocked) {
      await _toggleEditor(super.mode);
    }
  }

  @override
  void onDeviceRemoved() {
    super.onDeviceRemoved();

    _rapidProbeTask = null;
  }

  @override
  void onDeviceDeleted() {
    super.onDeviceDeleted();

    for (final cvn in _channels) {
      cvn.dispose();
    }
    _channels.clear();

    _overallBrightness = 0.0;
    _fanPowerRatio = 0.0;
    _fanMode = null;

    if (_editorState.editor != null) {
      _editorState.editor!.dispose();
      _editorState = _editorState.copyWith(editor: null, status: EditorStatus.idle, clearError: true);
    }
  }

  void _syncScheduleTables({required LyfiMode mode, bool force = false}) {
    if (!super.isOnline || isSuspectedOffline || boundDevice == null) {
      return;
    }

    switch (mode) {
      case LyfiMode.scheduled:
        if (force || scheduledInstants.isEmpty) {
          scheduledInstants
            ..clear()
            ..addAll(lyfiThing.getProperty<List<ScheduledInstant>>('schedule')!);
        }
        break;

      case LyfiMode.sun:
        if (force || sunInstants.isEmpty) {
          sunInstants
            ..clear()
            ..addAll(lyfiThing.getProperty<List<ScheduledInstant>>('sunSchedule')!);
        }
        break;

      default:
        break;
    }
  }

  void switchPowerOnOff(bool onOff) {
    if (isSuspectedOffline) {
      notifyAppError(gt.translate('Device is offline. Please retry after reconnection.'));
      return;
    }
    super.lyfiThing.findProperty('on')?.setValue(onOff);
  }

  bool get canSwitchTemporaryState =>
      !isBusy &&
      !isSuspectedOffline &&
      isOnline &&
      super.isOn &&
      (super.mode == LyfiMode.scheduled || super.mode == LyfiMode.sun) &&
      (super.state == LyfiState.temporary || super.state == LyfiState.normal);

  void switchTemporaryState() {
    try {
      if (!(super.state == LyfiState.normal || super.state == LyfiState.temporary)) {
        throw StateError(gt.translate('Bad device state'));
      }
      // Turn the temp mode on
      if (super.state == LyfiState.normal) {
        super.setState(LyfiState.temporary);
      } else {
        // Restore running mode
        super.setState(LyfiState.normal);
      }
    } catch (e, st) {
      notifyAppError(gt.translate('Failed to switch to temporary state'));
      logger?.e(e.toString(), error: e, stackTrace: st);
    }
  }

  bool get canSwitchDiscoState =>
      !isSuspectedOffline &&
      isOnline &&
      !isBusy &&
      super.isOn &&
      (super.state == LyfiState.temporary || super.state == LyfiState.normal);

  void switchDiscoState() async {
    // Turn the disco mode on
    if (super.state == LyfiState.normal || super.state == LyfiState.temporary) {
      super.setState(LyfiState.disco);
    } else {
      // Restore running mode
      super.setState(LyfiState.normal);
    }
  }

  void _scheduleEditorDispose(IEditor editor) {
    Future.delayed(const Duration(milliseconds: 350), () {
      if (_isDisposed) {
        return;
      }
      if (_editorState.editor == editor) {
        return;
      }
      try {
        editor.dispose();
      } catch (e, stackTrace) {
        logger?.w('Editor dispose delayed failed: $e', error: e, stackTrace: stackTrace);
      }
    });
  }

  Future<void> _onStateChanged(String value) async {
    final newState = LyfiState.fromString(value);
    if (newState == LyfiState.dimming) {
      await _toggleEditor(super.mode);
    } else if (newState == LyfiState.normal) {
      // Editor disposal only - saving is handled in toggleLock
      final previousEditor = _editorState.editor;
      _editorState = _editorState.copyWith(status: EditorStatus.idle, editor: null, clearError: true);
      if (previousEditor != null) {
        _scheduleEditorDispose(previousEditor);
      }
    }
    notifyListeners();
  }

  Future<void> toggleLock(bool newIsLocked) async {
    if (isSuspectedOffline) {
      return;
    }

    if (newIsLocked) {
      // Exiting edit mode - save changes first, then switch to normal state
      final editor = _editorState.editor;
      if (editor != null && editor.isChanged) {
        try {
          await editor.save();
          if (editor is ScheduleEditorViewModel) {
            _syncScheduleTables(mode: LyfiMode.scheduled, force: true);
          } else if (editor is SunEditorViewModel) {
            _syncScheduleTables(mode: LyfiMode.sun, force: true);
          }
        } catch (e, stackTrace) {
          notifyAppError(gt.translate('Failed to save changes. Please try again.'), error: e, stackTrace: stackTrace);
          return; // Prevent state change if save fails
        }
      }
      super.setState(LyfiState.normal);
    } else {
      // Entering edit mode - wait for state to change to dimming before creating editor
      super.setState(LyfiState.dimming);
    }
  }

  void switchMode(LyfiMode mode) async {
    await _switchMode(mode);
  }

  Future<void> _switchMode(LyfiMode newMode) async {
    if (!isOnline || isSuspectedOffline) {
      notifyAppError(gt.translate('Device is offline. Please retry after reconnection.'));
      return;
    }

    if (isLocked || isBusy) {
      return;
    }

    try {
      isBusy = true;
      notifyListeners();

      if (newMode == LyfiMode.sun) {
        if (borneoDeviceStatus?.timezone.isEmpty ?? true) {
          notifyAppError(gt.translate("Unable to switch to Sun Simulation mode: the timezone is not set."));
          return;
        }
        final location = super.lyfiThing.getProperty<GeoLocation?>('location');
        if (location == null) {
          notifyAppError(gt.translate("Unable to switch to Sun Simulation mode: the location is not set."));
          return;
        }
      }
      super.setMode(newMode);
    } catch (e, st) {
      notifyAppError(gt.translate('Failed to switch mode'), error: e, stackTrace: st);
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> _onModeChanged(String value) async {
    final newMode = LyfiMode.fromString(value);

    if (_editorState.mode == newMode && _editorState.status != EditorStatus.error) {
      notifyListeners();
      return;
    }

    if (isLocked || super.state != LyfiState.dimming) {
      _editorState = _editorState.copyWith(mode: newMode);
      notifyListeners();
      return;
    }

    await _toggleEditor(newMode);
  }

  Future<void> _toggleEditor(LyfiMode newMode) async {
    final previousEditor = _editorState.editor;
    _editorState = _editorState.copyWith(mode: newMode, status: EditorStatus.loading, editor: null, clearError: true);
    notifyListeners();

    _syncScheduleTables(mode: newMode);

    IEditor newEditor;
    switch (newMode) {
      case LyfiMode.manual:
        newEditor = ManualEditorViewModel(this, super.lyfiThing);
        break;

      case LyfiMode.scheduled:
        newEditor = ScheduleEditorViewModel(this, super.lyfiThing);
        break;

      case LyfiMode.sun:
        newEditor = SunEditorViewModel(this, super.lyfiThing);
        break;
    }

    try {
      await newEditor.initialize();
      _editorState = _editorState.copyWith(status: EditorStatus.ready, editor: newEditor, clearError: true);
    } catch (e, stackTrace) {
      logger?.e('Failed to initialize editor for mode $newMode', error: e, stackTrace: stackTrace);
      newEditor.dispose();
      _editorState = _editorState.copyWith(status: EditorStatus.error, editor: null, error: e);
    } finally {
      notifyListeners();
    }

    if (previousEditor != null) {
      _scheduleEditorDispose(previousEditor);
    }
    // Do not notify here; callers decide after refresh/creation to notify.
  }

  bool get isDimmingReady => !isLocked && super.state == LyfiState.dimming && _editorState.status == EditorStatus.ready;

  /// Returns a Future that completes when the view model is ready for Dimming editing
  /// (unlocked, state==dimming, editor initialized). No timers/polling are used; it resolves
  /// on the next notifyListeners that satisfies the predicate.
  Future<void> onDimmingReady() async {
    if (isDimmingReady) return;
    final completer = Completer<void>();
    late VoidCallback listener;
    listener = () {
      if (isDimmingReady && !completer.isCompleted) {
        removeListener(listener);
        completer.complete();
      }
    };
    addListener(listener);
    return completer.future;
  }

  Future<SettingsViewModel> loadSettings(final GettextLocalizations gt) async {
    if (isBusy || !super.isOnline || isSuspectedOffline || boundDevice == null) {
      throw StateError(gt.translate('Device is not reachable at the moment.'));
    }
    try {
      isBusy = true;
      notifyListeners();
      final vm = SettingsViewModel(
        deviceManager: deviceManager,
        globalEventBus: globalEventBus,
        notification: notification,
        wotThing: wotThing,
        address: deviceEntity.address,
        borneoStatus: borneoDeviceStatus!,
        borneoInfo: super.lyfiThing.getProperty<GeneralBorneoDeviceInfo>('generalDeviceInfo')!,
        ledInfo: lyfiDeviceInfo,
        ledStatus: lyfiDeviceStatus!,
        powerBehavior: super.lyfiThing.getProperty<PowerBehavior>('powerBehavior')!,
        gt: gt,
        logger: super.logger,
      );
      await vm.initialize();
      return vm;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  void _initializeChannels() {
    if (_channels.isNotEmpty) {
      for (final ch in _channels) {
        ch.dispose();
      }
      _channels.clear();
    }
    double ob = 0;
    final currentColor = lyfiThing.getProperty<List<int>>('color')!;
    final metaChannels = lyfiThing.getProperty<LyfiDeviceInfo>('lyfiDeviceInfo')!;
    for (int i = 0; i < currentColor.length; i++) {
      _channels.add(ValueNotifier<int>(currentColor[i]));
      ob += metaChannels.channels[i].factor * _channels[i].value / kLyfiBrightnessMax;
    }
    _overallBrightness = ob;
  }

  void _applyColorUpdate(List<int> color) {
    final metaChannels = lyfiThing.getProperty<LyfiDeviceInfo>('lyfiDeviceInfo');
    if (metaChannels == null || _channels.length != color.length || metaChannels.channels.length != color.length) {
      _initializeChannels();
      notifyListeners();
      return;
    }

    double ob = 0;
    for (int i = 0; i < color.length; i++) {
      _channels[i].value = color[i];
      ob += metaChannels.channels[i].factor * color[i] / kLyfiBrightnessMax;
    }
    _overallBrightness = ob;
    notifyListeners();
  }
}
