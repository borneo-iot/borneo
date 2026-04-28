import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:borneo_app/devices/borneo/lyfi/core/wot.dart';
import 'package:borneo_app/devices/borneo/view_models/base_borneo_summary_device_view_model.dart';
import 'package:borneo_app/devices/view_models/abstract_device_summary_view_model.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:flutter/material.dart';
import 'package:lw_wot/wot.dart';

class LyfiSummaryDeviceViewModel extends BaseBorneoSummaryDeviceViewModel {
  // replace ValueNotifiers with simple nullable fields; UI uses Selector
  LyfiState? ledState;
  LyfiMode? ledMode;
  List<int>? channelBrightness;
  LyfiDeviceInfo? lyfiDeviceInfo;

  LyfiSummaryDeviceViewModel(
    super.deviceEntity,
    super.deviceManager,
    super.globalEventBus, {
    required super.gt,
    super.logger,
  });

  @override
  void dispose() {
    if (!isDisposed) {
      wotThing?.removeSubscriber(_onStateChanged);
      wotThing?.removeSubscriber(_onModeChanged);
      wotThing?.removeSubscriber(_onColorChanged);
      wotThing?.removeSubscriber(_onDeviceInfoChanged);
      // plain fields don't require disposal
      super.dispose();
    }
  }

  @override
  void updateFrom(AbstractDeviceSummaryViewModel other) {
    super.updateFrom(other);
    if (other is! LyfiSummaryDeviceViewModel) {
      return;
    }

    ledState = other.ledState;
    ledMode = other.ledMode;
    channelBrightness = other.channelBrightness == null ? null : List<int>.from(other.channelBrightness!);
    lyfiDeviceInfo = other.lyfiDeviceInfo;
  }

  void _onStateChanged(WotMessage msg) {
    if (isDisposed) {
      return;
    }
    final stateValue = wotThing?.getProperty(LyfiKnownProperties.kState);
    if (stateValue != null) {
      final state = LyfiState.fromString(stateValue as String);
      _applyOrDefer(() {
        if (ledState != state) {
          ledState = state;
          notifyListeners();
        }
      });
    }
  }

  void _onModeChanged(WotMessage msg) {
    if (isDisposed) {
      return;
    }
    final modeValue = wotThing?.getProperty(LyfiKnownProperties.kMode);
    if (modeValue != null) {
      final mode = LyfiMode.fromString(modeValue as String);
      _applyOrDefer(() {
        if (ledMode != mode) {
          ledMode = mode;
          notifyListeners();
        }
      });
    }
  }

  void _onColorChanged(WotMessage msg) {
    if (isDisposed) {
      return;
    }
    final color = wotThing?.getProperty<List<int>>('color');
    if (color != null) {
      _applyOrDefer(() {
        final newList = List<int>.from(color);
        if (channelBrightness == null || !listEquals(channelBrightness, newList)) {
          channelBrightness = newList;
          notifyListeners();
        }
      });
    }
  }

  void _onDeviceInfoChanged(WotMessage msg) {
    if (isDisposed) {
      return;
    }
    final info = wotThing?.getProperty<LyfiDeviceInfo>('lyfiDeviceInfo');
    if (info != null) {
      _applyOrDefer(() {
        if (lyfiDeviceInfo != info) {
          lyfiDeviceInfo = info;
          notifyListeners();
        }
      });
    }
  }

  @override
  void onWotThingChanged(WotThing? oldThing, WotThing? newThing) {
    super.onWotThingChanged(oldThing, newThing);
    oldThing?.removeSubscriber(_onStateChanged);
    oldThing?.removeSubscriber(_onModeChanged);
    oldThing?.removeSubscriber(_onColorChanged);
    oldThing?.removeSubscriber(_onDeviceInfoChanged);
    newThing?.addSubscriber(_onStateChanged);
    newThing?.addSubscriber(_onModeChanged);
    newThing?.addSubscriber(_onColorChanged);
    newThing?.addSubscriber(_onDeviceInfoChanged);
    _syncFromThing();
  }

  void _syncFromThing() {
    if (isDisposed) {
      return;
    }

    LyfiState? newState;
    LyfiMode? newMode;
    List<int>? newColor;
    LyfiDeviceInfo? newInfo;

    final stateValue = wotThing?.getProperty(LyfiKnownProperties.kState);
    if (stateValue != null) {
      newState = LyfiState.fromString(stateValue as String);
    }

    final modeValue = wotThing?.getProperty(LyfiKnownProperties.kMode);
    if (modeValue != null) {
      newMode = LyfiMode.fromString(modeValue as String);
    }

    final color = wotThing?.getProperty<List<int>>('color');
    if (color != null) {
      newColor = List<int>.from(color);
    }

    final info = wotThing?.getProperty<LyfiDeviceInfo>('lyfiDeviceInfo');
    if (info != null) {
      newInfo = info;
    }

    if (newState != null || newMode != null || newColor != null || newInfo != null) {
      _applyOrDefer(() {
        bool changed = false;
        if (newState != null && ledState != newState) {
          ledState = newState;
          changed = true;
        }
        if (newMode != null && ledMode != newMode) {
          ledMode = newMode;
          changed = true;
        }
        if (newColor != null && (channelBrightness == null || !listEquals(channelBrightness, newColor))) {
          channelBrightness = newColor;
          changed = true;
        }
        if (newInfo != null && lyfiDeviceInfo != newInfo) {
          lyfiDeviceInfo = newInfo;
          changed = true;
        }
        if (changed) notifyListeners();
      });
    }
  }

  void _applyOrDefer(VoidCallback callback) {
    if (isDisposed) {
      return;
    }

    final schedulerPhase = WidgetsBinding.instance.schedulerPhase;
    final shouldDefer =
        schedulerPhase == SchedulerPhase.transientCallbacks ||
        schedulerPhase == SchedulerPhase.midFrameMicrotasks ||
        schedulerPhase == SchedulerPhase.persistentCallbacks;

    if (shouldDefer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isDisposed) {
          callback();
        }
      });
      return;
    }

    callback();
  }
}
