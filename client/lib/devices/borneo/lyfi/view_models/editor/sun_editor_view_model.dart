import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/base_editor_view_model.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/api.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:cancellation_token/cancellation_token.dart';

class SunEditorViewModel extends BaseEditorViewModel {
  ILyfiDeviceApi get _deviceApi => parent.boundDevice!.driver as ILyfiDeviceApi;

  @override
  bool get canEdit => parent.isOnline && !parent.isSuspectedOffline && parent.isOn && parent.mode == LyfiMode.sun;

  bool get canChangeColor => canEdit;

  @override
  LyfiDeviceInfo get deviceInfo => parent.lyfiDeviceInfo;

  ScheduleTable _sunInstants = const [];
  ScheduleTable get sunInstants => _sunInstants;

  List<SunCurveItem> _sunCurve = const [];

  SunEditorViewModel(super.parent, super.lyfiThing, {required super.gt});

  @override
  Future<void> onInitialize({CancellationToken? cancelToken}) async {
    // Ensure we are in the correct state and mode before proceeding
    if (parent.state != LyfiState.dimming) {
      throw StateError('SunEditorViewModel requires parent state to be dimming, but current state is ${parent.state}');
    }
    assert(parent.mode == LyfiMode.sun);

    if (parent.boundDevice == null) {
      throw StateError(gt.translate('Device is not bound.'));
    }

    final sunColor = super.lyfiThing.getProperty<List<int>>('sunColor')!;
    for (int i = 0; i < parent.lyfiDeviceInfo.channels.length; i++) {
      channels[i].value = sunColor[i];
    }
    await super.syncDimmingColor(true, cancelToken: cancelToken);

    final instants = await parent.executeLyfiCommand(
      () => _deviceApi.getSunSchedule(parent.boundDevice!.device, cancelToken: cancelToken),
    );
    _sunInstants = instants;

    _sunCurve = super.lyfiThing.getProperty<List<SunCurveItem>>('sunCurve')!;
    if (_sunCurve.isEmpty || _sunCurve.length != _sunInstants.length) {
      _sunCurve = await parent.executeLyfiCommand(
        () => _deviceApi.getSunCurve(parent.boundDevice!.device, cancelToken: cancelToken),
      );
      parent.lyfiThing.findProperty('sunCurve')?.value.notifyOfExternalUpdate(_sunCurve);
    }

    if (_sunCurve.isEmpty) {
      throw StateError(gt.translate('Sun curve data is unavailable.'));
    }
  }

  @override
  Future<void> updateChannelValue(int index, int value) async {
    if (index >= 0 && index < channels.length && value != channels[index].value) {
      if (_sunCurve.length < _sunInstants.length) {
        throw StateError(gt.translate('Sun curve data is incomplete.'));
      }
      channels[index].value = value;
      await super.syncDimmingColor(true);
      super.isChanged = true;
      for (var i = 0; i < _sunInstants.length; i++) {
        _sunInstants[i].color[index] = (value * _sunCurve[i].brightness).round();
      }
    }
    super.notifyListeners();
  }

  @override
  Future<void> save({CancellationToken? cancelToken}) async {
    if (parent.isSuspectedOffline || parent.boundDevice == null) {
      return;
    }

    final sunColor = channels.map((x) => x.value).toList(growable: false);
    final sunSchedule = _sunInstants
        .map((entry) => ScheduledInstant(instant: entry.instant, color: List<int>.from(entry.color)))
        .toList(growable: false);

    parent.lyfiThing.findProperty('sunColor')?.value.notifyOfExternalUpdate(sunColor);
    parent.lyfiThing.findProperty('sunSchedule')?.value.notifyOfExternalUpdate(sunSchedule);
  }
}
