import 'package:borneo_app/core/services/clock.dart';
import 'package:borneo_app/devices/view_models/abstract_device_summary_view_model.dart';
import 'package:borneo_app/features/devices/models/device_group_entity.dart';

import '../../../shared/view_models/base_view_model.dart';

/// An immutable snapshot of a [GroupViewModel] used by [Selector] widgets.
///
/// Implementing [operator ==] and [hashCode] lets the [Selector]'s
/// [shouldRebuild] callback determine whether the list of group snapshots has
/// actually changed, preventing unnecessary rebuilds of the outer widget tree
/// when [GroupedDevicesViewModel.notifyListeners()] fires.
class GroupSnapshot {
  final String id;
  final String name;
  final int deviceCount;
  final int lastModified;
  final bool isDummy;

  const GroupSnapshot({
    required this.id,
    required this.name,
    required this.deviceCount,
    required this.lastModified,
    required this.isDummy,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupSnapshot &&
          id == other.id &&
          name == other.name &&
          deviceCount == other.deviceCount &&
          lastModified == other.lastModified &&
          isDummy == other.isDummy;

  @override
  int get hashCode => Object.hash(id, name, deviceCount, lastModified, isDummy);
}

class GroupViewModel extends BaseViewModel with ViewModelEventBusMixin {
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

  GroupViewModel(this.model, {required this.clock, required super.gt}) {
    _lastModified = this.clock.now().millisecondsSinceEpoch;
  }

  void _updateModified() {
    _lastModified = this.clock.now().millisecondsSinceEpoch;
  }

  void addOrUpdateDevice(AbstractDeviceSummaryViewModel device) {
    final existingIndex = _devices.indexWhere((d) => d.deviceEntity.id == device.deviceEntity.id);
    if (existingIndex == -1) {
      // New device VM: take ownership and manage its lifecycle.
      _devices = [..._devices, device];
    } else {
      // Existing VM present -> perform in-place update to preserve identity.
      final existing = _devices[existingIndex];

      // Merge state from the incoming (temporary) VM into the existing VM.
      // Subclasses can override `updateFrom` to merge ValueNotifier state etc.
      existing.updateFrom(device);

      // The passed-in `device` was only a carrier/temporary instance created by
      // the factory; dispose it immediately since `existing` remains authoritative.
      if (!device.isDisposed) {
        device.dispose();
      }
    }
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
    if (!isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    if (!isDisposed) {
      // Inline device cleanup instead of calling clearDevices() to avoid
      // firing notifyListeners() after the VM has started tearing down.
      // clearDevices() checks isDisposed, but that flag is only set to true by
      // super.dispose(), so calling clearDevices() here would still trigger
      // listeners with an empty _devices list.
      for (final device in _devices) {
        if (!device.isDisposed) {
          device.dispose();
        }
      }
      _devices = [];
      super.dispose();
    }
  }
}
