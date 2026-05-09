import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/ieditor.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/lyfi_view_model.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:borneo_wot/borneo/lyfi/wot_thing.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:flutter_debounce_throttle/flutter_debounce_throttle.dart' show ThrottleDebouncer;
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';

abstract class BaseEditorViewModel extends ChangeNotifier implements IEditor {
  final ThrottleDebouncer _colorChangeRateLimiter = ThrottleDebouncer(duration: kLocalDimmingTrackingInterval);
  ThrottleDebouncer get colorChangeRateLimiter => _colorChangeRateLimiter;

  bool _isDisposed = false;
  final GettextLocalizations gt;

  final List<ValueNotifier<int>> _channels;
  final List<int> blackColor;
  final LyfiViewModel parent;
  final LyfiThing lyfiThing;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool get isOnline => parent.isOnline && !parent.isSuspectedOffline;
  bool get isBusy => parent.isBusy;
  bool get isDisposed => _isDisposed;

  bool _isChanged = false;

  @override
  bool get isChanged => _isChanged;

  set isChanged(bool newValue) => _isChanged = newValue;

  @override
  List<ValueNotifier<int>> get channels => _channels;

  BaseEditorViewModel(this.parent, this.lyfiThing, {required this.gt})
    : _channels = List.generate(parent.lyfiDeviceInfo.channelCount, growable: false, (index) => ValueNotifier(0)),
      blackColor = List.filled(parent.lyfiDeviceInfo.channelCount, 0, growable: false);

  @override
  Future<void> initialize({CancellationToken? cancelToken}) async {
    try {
      await onInitialize(cancelToken: cancelToken);
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> onInitialize({CancellationToken? cancelToken});

  @override
  void dispose() {
    if (!_isDisposed) {
      colorChangeRateLimiter.dispose();
      _isDisposed = true;
      super.dispose();
    }
  }

  @override
  int get availableChannelCount => deviceInfo.channelCount;

  @override
  LyfiDeviceInfo get deviceInfo => parent.lyfiDeviceInfo;

  Future<void> syncDimmingColor(bool isLimited, {CancellationToken? cancelToken}) async {
    final color = _channels.map((x) => x.value).toList(growable: false);
    if (isLimited) {
      _colorChangeRateLimiter.call(() {
        if (parent.isSuspectedOffline || parent.boundDevice == null) {
          return;
        }
        if (!parent.boundDevice!.device.driverData.isBusy) {
          lyfiThing.setProperty('color', color);
        }
      });
    } else {
      if (parent.isSuspectedOffline || parent.boundDevice == null) {
        return;
      }
      lyfiThing.setProperty('color', color);
    }
  }
}
