import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/base_editor_view_model.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../easy_setup_view_model.dart';

String _formatDuration(Duration duration) {
  final buffer = StringBuffer();

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);

  if (hours < 10) {
    buffer.write('0');
  }
  buffer.write(hours);
  buffer.write(':');

  if (minutes < 10) {
    buffer.write('0');
  }
  buffer.write(minutes);

  return buffer.toString();
}

class ScheduleEntryViewModel extends ChangeNotifier {
  final Duration _instant;
  final List<int> _channels = [];

  Duration get instant => _instant;
  String get instantText => _formatDuration(_instant);
  List<int> get channels => _channels;

  ScheduleEntryViewModel(ScheduledInstant model) : _instant = model.instant {
    _channels.addAll(model.color);
  }

  ScheduledInstant toModel() => ScheduledInstant(instant: _instant, color: _channels);
}

class ScheduleEditorViewModel extends BaseEditorViewModel {
  static const Duration defaultInstantSpan = Duration(minutes: 30);
  static const int maxEntries = 48;

  final EasySetupViewModel easySetupViewModel;

  int? _currentEntryIndex;

  final List<ScheduleEntryViewModel> _entries = [];

  bool get isEmpty => _entries.isEmpty;
  bool get isNotEmpty => _entries.isNotEmpty;

  List<ScheduleEntryViewModel> get entries => _entries;
  bool get isPreviewMode => parent.state == LyfiState.preview;

  @override
  bool get canEdit => parent.isOnline && !parent.isSuspectedOffline && parent.isOn && parent.mode == LyfiMode.scheduled;

  bool get canChangeColor => canEdit && currentEntry != null;

  ScheduleEntryViewModel? get currentEntry => _currentEntryIndex != null ? _entries[_currentEntryIndex!] : null;

  ILyfiDeviceApi get _deviceApi => parent.boundDevice!.driver as ILyfiDeviceApi;

  ScheduleEditorViewModel(super.parent, super.lyfiThing) : easySetupViewModel = EasySetupViewModel();

  @override
  Future<void> onInitialize({CancellationToken? cancelToken}) async {
    if (parent.boundDevice == null) {
      throw StateError('Device is not bound.');
    }

    final cachedInstants = parent.scheduledInstants;
    _entries.addAll(cachedInstants.map((x) => ScheduleEntryViewModel(x)));

    if (cachedInstants.isNotEmpty) {
      var currentEntryIndex = cachedInstants.indexWhere((x) => !x.isZero);
      if (currentEntryIndex < 0) {
        currentEntryIndex = 0;
      }
      _setCurrentEntry(currentEntryIndex);
    }

    await syncDimmingColor(false, cancelToken: cancelToken);
  }

  void _setCurrentEntry(int? index) {
    if (index != null) {
      _currentEntryIndex = index;
      for (int channelIndex = 0; channelIndex < channels.length; channelIndex++) {
        channels[channelIndex].value = currentEntry!.channels[channelIndex];
      }
    } else {
      for (final ch in channels) {
        ch.value = 0;
      }
      _currentEntryIndex = null;
    }
  }

  Future<void> setCurrentEntryAndSyncDimmingColor(int index) async {
    _setCurrentEntry(index);
    await syncDimmingColor(false);
    notifyListeners();
  }

  bool get canPrevInstant =>
      isInitialized && !isPreviewMode && _entries.length > 1 && _currentEntryIndex != null && _currentEntryIndex! > 0;

  Future<void> prevInstant() async {
    if (_currentEntryIndex == null) {
      return;
    }

    if (_currentEntryIndex! > 0) {
      await setCurrentEntryAndSyncDimmingColor(_currentEntryIndex! - 1);
    }
  }

  bool get canNextInstant =>
      isInitialized &&
      !isPreviewMode &&
      _entries.length > 1 &&
      _currentEntryIndex != null &&
      _currentEntryIndex! < _entries.length - 1;

  Future<void> nextInstant() async {
    if (_currentEntryIndex == null) {
      return;
    }

    if (_currentEntryIndex! < _entries.length - 1) {
      await setCurrentEntryAndSyncDimmingColor(_currentEntryIndex! + 1);
    }
  }

  bool get canRemoveCurrentInstant => isInitialized && _entries.isNotEmpty && _currentEntryIndex != null;

  void removeCurrentInstant() {
    if (_currentEntryIndex == null) {
      return;
    }

    int removed = _currentEntryIndex!;
    _entries.removeAt(_currentEntryIndex!);
    isChanged = true;

    if (_entries.isNotEmpty) {
      if (removed >= 1) {
        setCurrentEntryAndSyncDimmingColor(removed - 1);
      } else {
        setCurrentEntryAndSyncDimmingColor(0);
      }
    } else {
      _setCurrentEntry(null);
      notifyListeners();
    }
  }

  bool get canClearInstants => isInitialized && _entries.isNotEmpty;

  void clearEntries({bool notify = true}) {
    if (_entries.isEmpty) {
      return;
    }

    _setCurrentEntry(null);
    for (var x in _entries) {
      x.dispose();
    }
    _entries.clear();
    if (notify) {
      notifyListeners();
    }
  }

  bool get canAddInstant => isInitialized && _entries.length < maxEntries;

  Future<void> addInstant(Duration instant) async {
    if (_entries.length >= maxEntries) return;
    final normalized = _normalizeAddInstant(instant);
    if (normalized == null) {
      return;
    }
    int insertPos = _findInstantInsertPosition(normalized);
    if (_currentEntryIndex != null) {
      _insertInstant(insertPos, normalized, _entries[_currentEntryIndex!].channels);
    } else {
      _insertInstant(insertPos, normalized, List<int>.filled(deviceInfo.channelCount, 0, growable: false));
    }
    await setCurrentEntryAndSyncDimmingColor(insertPos);
  }

  Duration? _normalizeAddInstant(Duration instant) {
    final normalizedHours = instant.inHours % 24;
    final normalizedMinutes = instant.inMinutes % 60;
    final normalized = Duration(hours: normalizedHours, minutes: normalizedMinutes);
    if (_currentEntryIndex == null) {
      return normalized;
    }
    final current = _entries[_currentEntryIndex!].instant;
    final currentDay = current.inHours ~/ 24;
    final currentHour = current.inHours % 24;
    var targetHours = currentDay * 24 + normalizedHours;
    if (currentDay == 0 && normalizedHours <= currentHour) {
      targetHours += 24;
    }
    final result = Duration(hours: targetHours, minutes: normalizedMinutes);
    if (result.inHours >= 48) {
      return null;
    }
    return result;
  }

  int _findInstantInsertPosition(Duration instant) {
    int insertPos = 0;
    for (insertPos = 0; insertPos < entries.length; insertPos++) {
      if (entries[insertPos].instant > instant) {
        break;
      }
    }
    return insertPos;
  }

  ScheduleEntryViewModel _insertInstant(int insertPos, Duration instant, List<int> channels) {
    final entry = ScheduleEntryViewModel(ScheduledInstant(instant: instant, color: channels));
    _entries.insert(insertPos, entry);
    isChanged = true;
    return entry;
  }

  ScheduleEntryViewModel _appendInstant(Duration instant, List<int> channels) {
    final entry = ScheduleEntryViewModel(ScheduledInstant(instant: instant, color: channels));

    _entries.add(entry);
    isChanged = true;
    return entry;
  }

  @override
  Future<void> updateChannelValue(int index, int value) async {
    if (index >= 0 && index < channels.length && value != channels[index].value) {
      channels[index].value = value;
      currentEntry?.channels[index] = value;
      await super.syncDimmingColor(true);
      super.isChanged = true;
      super.notifyListeners();
    }
  }

  void togglePreviewMode() async {
    if (isPreviewMode) {
      if (parent.isSuspectedOffline || parent.boundDevice == null) {
        return;
      }
      await parent.executeLyfiCommand(() => _deviceApi.switchState(parent.boundDevice!.device, LyfiState.dimming));
    } else {
      if (parent.isSuspectedOffline || parent.boundDevice == null) {
        return;
      }
      await parent.executeLyfiCommand(() => _deviceApi.switchState(parent.boundDevice!.device, LyfiState.preview));
    }
    notifyListeners();
  }

  @override
  Future<void> save({CancellationToken? cancelToken}) async {
    if (parent.isSuspectedOffline || parent.boundDevice == null) {
      return;
    }
    final toSave = _entries.map((x) => x.toModel()).toList(growable: false);
    await lyfiThing.performActionAndWait('setSchedule', toSave).asCancellable(cancelToken);
  }

  void resetChannelValues() {}

  Future<void> loadCurve(Iterable<ScheduledInstant> instants) async {
    clearEntries(notify: false);
    for (final i in instants) {
      _appendInstant(i.instant, i.color);
    }
    if (instants.length > 1) {
      await setCurrentEntryAndSyncDimmingColor(1);
    } else if (instants.isNotEmpty) {
      await setCurrentEntryAndSyncDimmingColor(0);
    }
  }

  Future<void> easySetupEnter() async {
    // Initialize Easy Setup fields from current editor values instead of
    // clearing the schedule immediately. This ensures the Easy Setup UI
    // reads the current brightness sliders and sensible times.
    if (currentEntry != null) {
      final inst = currentEntry!.instant;
      final start = Duration(hours: inst.inHours % 24, minutes: inst.inMinutes % 60);
      easySetupViewModel.startTime.value = start;
      final defaultSpan = defaultEndTime - defaultStartTime;
      final proposedEnd = start + defaultSpan;
      easySetupViewModel.endTime.value = Duration(hours: proposedEnd.inHours % 24, minutes: proposedEnd.inMinutes % 60);
    } else {
      easySetupViewModel.startTime.value = defaultStartTime;
      easySetupViewModel.endTime.value = defaultEndTime;
    }

    // Also copy current channel slider values into the EasySetupViewModel so
    // the Easy Setup UI operates on a temporary set of channel values.
    easySetupViewModel.initChannelsFromList(channels.map((c) => c.value).toList());

    // Do not clear entries here; Apply in the Easy Setup screen will commit.
  }

  Future<void> easySetupFinish() async {
    final easyInstants = easySetupViewModel.build(this);
    final effectiveChannelValues = easySetupViewModel.channelValues.isNotEmpty
        ? easySetupViewModel.channelValues
        : channels.map((x) => x.value).toList();
    if (effectiveChannelValues.any((v) => v > 0)) {
      await loadCurve(easyInstants);
    }
  }
}
