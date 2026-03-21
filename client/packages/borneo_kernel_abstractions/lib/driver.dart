import 'package:borneo_common/borneo_common.dart';
import 'package:borneo_common/exceptions.dart';
import 'package:borneo_kernel_abstractions/device.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:logger/logger.dart';

import 'models/io.dart';

abstract class Driver implements IDisposable {
  final Logger? logger;
  const Driver({this.logger});

  Future<bool> probe(Device dev, {CancellationToken? cancelToken});

  Future<bool> remove(Device dev, {CancellationToken? cancelToken});

  Future<bool> heartbeat(Device dev, {CancellationToken? cancelToken});

  Future<T> withBusyCheck<T>(Device dev, Future<T> Function() action, {CancellationToken? cancelToken}) async {
    if (dev.driverData.isBusy) {
      throw InvalidOperationException(message: "Device is busy");
    }
    return await dev.driverData.lock.synchronized(() async {
      try {
        return await action();
      } catch (error, stackTrace) {
        logger?.e('Busy-check driver action failed for device ${dev.id}', error: error, stackTrace: stackTrace);
        rethrow;
      }
    });
  }

  Future<T> withQueue<T>(
    Device dev,
    Future<T> Function() action, {
    CancellationToken? cancelToken,
    IOCommandPriority priority = IOCommandPriority.normal,
  }) async {
    return await dev.driverData.queue.submit(
      () async {
        if (dev.driverData.isBusy) {
          throw InvalidOperationException(message: "Device is busy");
        }
        try {
          return await action();
        } catch (error, stackTrace) {
          logger?.e('Queued driver action failed for device ${dev.id}', error: error, stackTrace: stackTrace);
          rethrow;
        }
      },
      priority: priority,
      cancel: cancelToken,
    );
  }
}
