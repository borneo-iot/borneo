import 'package:borneo_app/core/events/app_events.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

abstract class BaseViewModel extends ChangeNotifier {
  final Logger? logger;
  bool _isDisposed = false;
  bool isBusy = false;

  bool get isDisposed => _isDisposed;

  BaseViewModel({this.logger});

  @override
  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      super.dispose();
    }
  }

  void setBusy(bool value, {bool notify = true}) {
    assertNotDisposed(this);
    isBusy = value;
    if (notify) {
      notifyListeners();
    }
  }

  @override
  void notifyListeners() {
    assertNotDisposed(this);
    super.notifyListeners();
  }

  void notifyAppError(String message, {Object? error, StackTrace? stackTrace, bool allowDuplicates = false});

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
  void notifyAppError(String message, {Object? error, StackTrace? stackTrace, bool allowDuplicates = false}) {
    globalEventBus.fire(AppErrorEvent(message, error: error, stackTrace: stackTrace, allowDuplicates: allowDuplicates));
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
