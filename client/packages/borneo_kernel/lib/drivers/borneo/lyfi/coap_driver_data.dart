import 'dart:async';

import 'package:borneo_common/io/net/coap_client.dart';
import 'package:borneo_kernel/drivers/borneo/coap_driver_data.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/events.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';

class LyfiCoapDriverData extends BorneoCoapDriverData {
  bool _disposed = false;

  StreamSubscription? _modeChangedSub;
  StreamSubscription? _stateChangedSub;

  LyfiCoapDriverData(super.device, super.coap, super.probeCoap, {required super.supportedResourcePaths});

  @override
  void load() {
    super.load();

    _modeChangedSub = coap
        .observeCbor<int>(LyfiPaths.mode)
        .listen((mode) => super.deviceEvents.fire(LyfiModeChangedEvent(device, mode: LyfiMode.values[mode])));

    _stateChangedSub = coap
        .observeCbor<int>(LyfiPaths.state)
        .listen((state) => super.deviceEvents.fire(LyfiStateChangedEvent(device, state: LyfiState.values[state])));
  }

  @override
  void dispose() {
    if (!_disposed) {
      _modeChangedSub?.cancel();
      _stateChangedSub?.cancel();

      super.dispose();
      _disposed = true;
    }
  }
}
