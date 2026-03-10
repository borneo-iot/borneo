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
    final hasLocation = super.lyfiThing.getProperty<GeoLocation?>('location') != null;
    final tz = super.lyfiThing.getProperty<String?>('timezone');
    return _editor.channels.isNotEmpty &&
        _editor.channels.any((x) => x.value > 0) &&
        hasLocation &&
        tz != null &&
        tz.isNotEmpty;
  }

  String? get validationErrorMessage {
    if (_editor.channels.isEmpty || !_editor.channels.any((x) => x.value > 0)) {
      return gt.translate('Unable to update Moon mode: configure at least one channel with brightness greater than 0.');
    }

    final hasLocation = super.lyfiThing.getProperty<GeoLocation?>('location') != null;
    if (!hasLocation) {
      return gt.translate('Unable to update Moon mode: the location is not set.');
    }

    final tz = super.lyfiThing.getProperty<String?>('timezone');
    if (tz == null || tz.isEmpty) {
      return gt.translate('Unable to update Moon mode: the timezone is not set.');
    }

    return null;
  }

  Future<bool> submitToDevice() async {
    if (!isOnline) {
      notifyAppError(gt.translate('Device is offline. Please retry after reconnection.'));
      return false;
    }

    final validationMessage = validationErrorMessage;
    if (validationMessage != null) {
      notifyAppError(validationMessage);
      notifyListeners();
      return false;
    }

    final config = MoonConfig(enabled: _enabled, color: _editor.channels.map((x) => x.value).toList());

    try {
      await super.lyfiThing.performActionAndWait('setMoonConfig', config);
      _isChanged = false;
      _editor.isChanged = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      notifyAppError(gt.translate('Failed to update moon settings.'), error: e, stackTrace: st);
      return false;
    }
  }

  @override
  RssiLevel? get rssiLevel => null;
}
