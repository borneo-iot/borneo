import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/base_editor_view_model.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:cancellation_token/cancellation_token.dart';

class ManualEditorViewModel extends BaseEditorViewModel {
  @override
  bool get canEdit => parent.isOnline && !parent.isSuspectedOffline && parent.isOn && parent.mode == LyfiMode.manual;

  bool get canChangeColor => canEdit;

  ManualEditorViewModel(super.parent, super.lyfiThing, {required super.gt});

  @override
  Future<void> onInitialize({CancellationToken? cancelToken}) async {
    if (parent.boundDevice == null) {
      throw StateError('Device is not bound.');
    }

    final manualColor = super.lyfiThing.getProperty<List<int>>('manualColor')!;

    // Ensure we are in the correct state and mode before proceeding
    if (parent.state != LyfiState.dimming) {
      throw StateError(
        'ManualEditorViewModel requires parent state to be dimming, but current state is ${parent.state}',
      );
    }
    assert(parent.mode == LyfiMode.manual);

    for (int i = 0; i < parent.lyfiDeviceInfo.channels.length; i++) {
      channels[i].value = manualColor[i];
    }
    await syncDimmingColor(false, cancelToken: cancelToken);
  }

  @override
  Future<void> updateChannelValue(int index, int value) async {
    if (index >= 0 && index < super.channels.length && value != super.channels[index].value) {
      super.channels[index].value = value;
      channels[index].value = value;
      await super.syncDimmingColor(true);
      super.isChanged = true;
    }
  }

  @override
  Future<void> save({CancellationToken? cancelToken}) async {
    //do nothing
  }
}
