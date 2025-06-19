import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/ieditor.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/lyfi_view_model.dart';
import 'package:borneo_common/async/async_rate_limiter.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:flutter/material.dart';

abstract class BaseEditorViewModel extends ChangeNotifier implements IEditor {
  final AsyncRateLimiter<Future Function()> _colorChangeRateLimiter = AsyncRateLimiter(
    interval: localDimmingTrackingInterval,
  );
  AsyncRateLimiter<Future Function()> get colorChangeRateLimiter => _colorChangeRateLimiter;

  final List<ValueNotifier<int>> _channels;
  final List<int> blackColor;
  final LyfiViewModel parent;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool get isOnline => parent.isOnline;
  bool get isBusy => parent.isBusy.value;

  bool _isChanged = false;

  @override
  bool get isChanged => _isChanged;

  set isChanged(bool newValue) => _isChanged = newValue;

  @override
  List<ValueNotifier<int>> get channels => _channels;

  ILyfiDeviceApi get deviceApi => parent.boundDevice!.driver as ILyfiDeviceApi;

  BaseEditorViewModel(this.parent)
    : _channels = List.generate(parent.lyfiDeviceInfo.channelCount, growable: false, (index) => ValueNotifier(0)),
      blackColor = List.filled(parent.lyfiDeviceInfo.channelCount, 0, growable: false);

  @override
  Future<void> initialize({CancellationToken? cancelToken}) async {
    try {
      await onInitialize(cancelToken: cancelToken);
      await syncDimmingColor(false);
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> onInitialize({CancellationToken? cancelToken});

  @override
  void dispose() {
    colorChangeRateLimiter.dispose();
    super.dispose();
  }

  @override
  int get availableChannelCount => deviceInfo.channelCount;

  @override
  LyfiDeviceInfo get deviceInfo => parent.lyfiDeviceInfo;

  Future<void> syncDimmingColor(bool isLimited) async {
    final color = _channels.map((x) => x.value).toList(growable: false);
    if (isLimited) {
      _colorChangeRateLimiter.add(() => deviceApi.setColor(parent.boundDevice!.device, color));
    } else {
      await deviceApi.setColor(parent.boundDevice!.device, color);
    }
  }
}
