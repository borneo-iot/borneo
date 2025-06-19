import 'package:async_queue/async_queue.dart';
import 'package:borneo_app/core/events/app_events.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

abstract class BaseViewModel extends ChangeNotifier {
  final Logger? logger;
  bool _isDisposed = false;
  final taskQueue = AsyncQueue.autoStart(allowDuplicate: true);
  final CancellationToken taskQueueCancelToken = CancellationToken();
  final ValueNotifier<bool> isBusy = ValueNotifier<bool>(false);

  bool get isDisposed => _isDisposed;

  BaseViewModel({this.logger});
  @override
  void dispose() {
    if (!_isDisposed) {
      taskQueueCancelToken.cancel();
      taskQueue.stop();
      taskQueue.close();
      isBusy.dispose();
      super.dispose();
      _isDisposed = true;
    }
  }

  void setBusy(bool value) {
    assertNotDisposed(this);
    isBusy.value = value;
  }

  @override
  void notifyListeners() {
    assertNotDisposed(this);
    super.notifyListeners();
  }

  void enqueueJob(Future<void> Function() job, {int retryTime = 1, bool reportError = true}) {
    assertNotDisposed(this);
    taskQueue.addJob(retryTime: retryTime, (args) async {
      try {
        await job().asCancellable(taskQueueCancelToken);
      } on CancelledException catch (e, stackTrace) {
        logger?.w('A job has been cancelled.', error: e, stackTrace: stackTrace);
      } catch (e, stackTrace) {
        if (reportError) {
          notifyAppError(e.toString(), error: e, stackTrace: stackTrace);
        } else {
          rethrow;
        }
      }
    });
  }

  void enqueueUIJob(Future<void> Function() job, {int retryTime = 1, bool notify = true}) {
    assertNotDisposed(this);

    taskQueue.addJob((args) async {
      if (isBusy.value) {
        return;
      }
      isBusy.value = true;
      // notifyListeners();
      try {
        return await job().asCancellable(taskQueueCancelToken);
      } on CancelledException catch (e, stackTrace) {
        logger?.w('A job has been cancelled.', error: e, stackTrace: stackTrace);
      } catch (e, stackTrace) {
        logger?.e('$e', error: e, stackTrace: stackTrace);
        notifyAppError('$e', error: e, stackTrace: stackTrace);
      } finally {
        if (!isDisposed) {
          isBusy.value = false;
          if (notify) {
            notifyListeners();
          }
        }
      }
    }, retryTime: retryTime);
  }

  void notifyAppError(String message, {Object? error, StackTrace? stackTrace});

  static bool assertNotDisposed(BaseViewModel vm) {
    assert(() {
      if (vm._isDisposed) {
        throw FlutterError(
          'A ${vm.runtimeType} was used after being disposed.\n'
          'Once you have called dispose() on a ${vm.runtimeType}, it '
          'can no longer be used.',
        );
      }
      return true;
    }());
    return true;
  }
}

mixin ViewModelEventBusMixin on BaseViewModel {
  late final EventBus globalEventBus;

  @override
  void notifyAppError(String message, {Object? error, StackTrace? stackTrace}) {
    globalEventBus.fire(AppErrorEvent(message, error: error, stackTrace: stackTrace));
  }
}

mixin ViewModelInitFutureMixin on BaseViewModel {
  Future<void>? _initFuture;
  Future<void>? get initFuture {
    if ((this as dynamic).isInitialized == true) {
      return null;
    }
    return _initFuture ??= (this as dynamic).initialize();
  }
}
