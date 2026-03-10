import 'package:borneo_app/core/services/clock.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/base_lyfi_device_view_model.dart';
import 'package:borneo_common/io/net/rssi.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';

enum AcclimationValidationField { startDate, duration, startStrength }

class AcclimationViewModel extends BaseLyfiDeviceViewModel {
  final IClock clock;
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
    updateEnabled(value);
  }

  AcclimationViewModel({
    required super.deviceManager,
    required super.globalEventBus,
    required super.notification,
    required super.wotThing,
    required super.gt,
    required this.clock,
    super.logger,
  });

  @override
  Future<void> onInitialize() async {
    await super.onInitialize();
    _origSettings = await super.lyfiDeviceApi.getAcclimation(super.boundDevice!.device);

    _startTimestamp = _origSettings.startTimestamp;
    _enabled = _origSettings.enabled;
    _days = _origSettings.days.toDouble();
    _startPercent = _origSettings.startPercent.toDouble();
  }

  void updateEnabled(bool newValue) {
    _enabled = newValue;
    if (newValue) {
      if (_startTimestamp.year < 2025) {
        _startTimestamp = clock.utcNow();
      }
    }
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
    return isOnline && !isBusy && isChanged;
  }

  bool get hasStartDateError => _enabled && !_isStartTimestampValid;

  bool get hasDurationError => _enabled && !_isDaysValid;

  bool get hasStartPercentError => _enabled && !_isStartPercentValid;

  bool validate() {
    if (!_enabled) {
      return true;
    }
    return _isStartTimestampValid && _isDaysValid && _isStartPercentValid;
  }

  String? get validationErrorMessage {
    final field = firstInvalidField;
    if (field == null) {
      return null;
    }

    switch (field) {
      case AcclimationValidationField.startDate:
        return gt.translate('Start date is invalid.');
      case AcclimationValidationField.duration:
        return gt.translate('Duration must be between 5 and 100 days.');
      case AcclimationValidationField.startStrength:
        return gt.translate('Start strength must be between 10% and 90%.');
    }
  }

  AcclimationValidationField? get firstInvalidField {
    if (!_enabled) {
      return null;
    }
    if (!_isStartTimestampValid) {
      return AcclimationValidationField.startDate;
    }
    if (!_isDaysValid) {
      return AcclimationValidationField.duration;
    }
    if (!_isStartPercentValid) {
      return AcclimationValidationField.startStrength;
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

    try {
      await super.lyfiThing.performActionAndWait('setAcclimation', {
        'enabled': _enabled,
        'startTimestamp': (_startTimestamp.millisecondsSinceEpoch / 1000).round(),
        'startPercent': _startPercent.round(),
        'days': _days.round(),
      });

      _isChanged = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      notifyAppError(gt.translate('Failed to update acclimation settings.'), error: e, stackTrace: st);
      return false;
    }
  }

  bool get _isStartTimestampValid => _startTimestamp.isUtc && _startTimestamp.isAfter(DateTime(2025, 1, 1).toUtc());

  bool get _isDaysValid => _days >= 5 && _days <= 100;

  bool get _isStartPercentValid => _startPercent >= 10 && _startPercent <= 90;

  @override
  RssiLevel? get rssiLevel => null;
}
