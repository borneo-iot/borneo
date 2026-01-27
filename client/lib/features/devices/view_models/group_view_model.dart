import 'package:borneo_app/core/services/clock.dart';
import 'package:borneo_app/devices/view_models/abstract_device_summary_view_model.dart';
import 'package:borneo_app/features/devices/models/device_group_entity.dart';

import '../../../shared/view_models/base_view_model.dart';

class GroupViewModel extends BaseViewModel {
  List<AbstractDeviceSummaryViewModel> _devices = [];
  final IClock clock;
  late int _lastModified;

  String get id => model.id;
  String get name => model.name;
  List<AbstractDeviceSummaryViewModel> get devices => _devices;
  bool get isDummy => model.isDummy;
  int get lastModified => _lastModified;

  DeviceGroupEntity model;

  bool get isEmpty => _devices.isEmpty;

  GroupViewModel(this.model, {required this.clock}) {
    _lastModified = this.clock.now().millisecondsSinceEpoch;
  }

  void _updateModified() {
    _lastModified = this.clock.now().millisecondsSinceEpoch;
  }

  void addDevice(AbstractDeviceSummaryViewModel device) {
    _devices = [..._devices, device];
    _updateModified();
    notifyListeners();
  }

  void insertDevice(int index, AbstractDeviceSummaryViewModel device) {
    _devices = [..._devices];
    _devices.insert(index, device);
    _updateModified();
    notifyListeners();
  }

  void removeDevice(AbstractDeviceSummaryViewModel device) {
    _devices = _devices.where((d) => d != device).toList();
    _updateModified();
    notifyListeners();
  }

  void removeDeviceById(String deviceId) {
    final originalLength = _devices.length;
    _devices = _devices.where((d) => d.deviceEntity.id != deviceId).toList();
    if (originalLength != _devices.length) {
      _updateModified();
      notifyListeners();
    }
  }

  void clearDevices() {
    for (final device in _devices) {
      if (!device.isDisposed) {
        device.dispose();
      }
    }
    _devices = [];
    _updateModified();
    notifyListeners();
  }

  @override
  void dispose() {
    if (!isDisposed) {
      clearDevices();
      super.dispose();
    }
  }

  @override
  void notifyAppError(String message, {Object? error, StackTrace? stackTrace, bool allowDuplicates = false}) {
    // TODO
  }
}
