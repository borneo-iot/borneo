import 'package:borneo_kernel_abstractions/events.dart';
import 'package:borneo_common/utils/disposable.dart';
import 'package:synchronized/synchronized.dart';

import '../device.dart';
import 'io.dart';

abstract class DriverData extends IDisposable {
  bool _isDisposed = false;
  final _lock = Lock();
  final IORequestQueue _queue = IORequestQueue();

  final Device device;
  final DeviceEventBus deviceEvents = DeviceEventBus();
  bool get isBusy => _lock.locked;
  Lock get lock => _lock;
  IORequestQueue get queue => _queue;

  DriverData(this.device);

  @override
  void dispose() {
    if (!_isDisposed) {
      _queue.dispose();
      deviceEvents.destroy();
      _isDisposed = true;
    }
  }
}
