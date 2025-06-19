import 'package:borneo_app/devices/borneo/lyfi/view_models/base_lyfi_device_view_model.dart';
import 'package:borneo_common/io/net/rssi.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:cancellation_token/cancellation_token.dart';

class AcclimationViewModel extends BaseLyfiDeviceViewModel {
  late final AcclimationSettings _origSettings;

  late DateTime _startTimestamp;
  DateTime get startTimestamp => _startTimestamp;

  late double _days;
  double get days => _days;

  bool _enabled = false;
  bool get enabled => _enabled;

  late double _startPercent;
  double get startPercent => _startPercent;

  bool _isChanged = false;
  bool get isChanged => _isChanged;
  void setChanged() {
    _isChanged = true;
  }

  Future<void> setEanbled(bool value) async {
    _enabled = value;
    setChanged();
    notifyListeners();
  }

  AcclimationViewModel({required super.deviceID, required super.deviceManager, required super.globalEventBus});

  @override
  Future<void> onInitialize() async {
    _origSettings = await super.lyfiDeviceApi.getAcclimation(super.boundDevice!.device);

    _startTimestamp = _origSettings.startTimestamp;
    _enabled = _origSettings.enabled;
    _days = _origSettings.days.toDouble();
    _startPercent = _origSettings.startPercent.toDouble();
  }

  void updateEnabled(bool newValue) {
    _enabled = newValue;
    setChanged();
    notifyListeners();
  }

  void updateDays(double newValue) {
    _days = newValue;
    setChanged();
    notifyListeners();
  }

  void updateStartPercent(double newValue) {
    _startPercent = newValue;
    setChanged();
    notifyListeners();
  }

  void updateStartTimestamp(DateTime newLocal) {
    _startTimestamp = newLocal.toUtc();
    setChanged();
    notifyListeners();
  }

  bool get canSubmit {
    return isOnline && !isBusy.value && validate() && isChanged;
  }

  bool validate() {
    return _startTimestamp.isUtc &&
        _startTimestamp.isAfter(DateTime(2025, 1, 1).toUtc()) &&
        _days >= 5 &&
        _days <= 100 &&
        _startPercent >= 10 &&
        _startPercent <= 90;
  }

  Future<void> submitToDevice() async {
    assert(isOnline && validate());

    final acc = AcclimationSettings(
      enabled: _enabled,
      startTimestamp: _startTimestamp,
      startPercent: _startPercent.round(),
      days: _days.round(),
    );

    super.lyfiDeviceApi.setAcclimation(super.boundDevice!.device, acc);
    _isChanged = false;
  }

  @override
  Future<void> refreshStatus({CancellationToken? cancelToken}) async {}

  @override
  RssiLevel? get rssiLevel => null;
}
