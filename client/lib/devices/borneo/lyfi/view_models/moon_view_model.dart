import 'package:borneo_app/devices/borneo/lyfi/view_models/base_lyfi_device_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/editor/moon_editor_view_model.dart';
import 'package:borneo_common/io/net/rssi.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';

class MoonViewModel extends BaseLyfiDeviceViewModel {
  late final MoonConfig _origConfig;

  bool _enabled = false;
  bool get enabled => _enabled;

  bool _isChanged = false;
  bool get isChanged => _isChanged;
  void setChanged() {
    _isChanged = true;
  }

  late final MoonEditorViewModel _editor;
  MoonEditorViewModel get editor => _editor;

  bool get canEdit => editor.canEdit;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    setChanged();
    notifyListeners();
  }

  MoonViewModel({
    required super.deviceManager,
    required super.globalEventBus,
    required super.notification,
    required super.wotThing,
    required super.gt,
    super.logger,
  }) {
    _editor = MoonEditorViewModel(this);
  }

  @override
  Future<void> onInitialize() async {
    await super.onInitialize();
    _origConfig = await super.lyfiDeviceApi.getMoonConfig(super.boundDevice!.device);

    _enabled = _origConfig.enabled;
    await _editor.initialize();
  }

  bool get canSubmit {
    return isOnline && !isBusy && validate() && (isChanged || _editor.isChanged);
  }

  bool validate() {
    return true; // No specific validation for moon config
  }

  Future<void> submitToDevice() async {
    assert(isOnline && validate());

    final config = MoonConfig(enabled: _enabled, color: _editor.channels.map((x) => x.value).toList());

    await super.lyfiThing.performActionAndWait('setMoonConfig', config);
    _isChanged = false;
    _editor.isChanged = false;
  }

  @override
  RssiLevel? get rssiLevel => null;
}
