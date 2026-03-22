// Dart port of src/value.ts

import 'dart:async';

typedef WotForwarder<T> = FutureOr<void> Function(T value);

class WotValue<T> {
  T _lastValue;
  final WotForwarder<T>? _valueForwarder;
  final StreamController<T> _controller = StreamController<T>.broadcast();
  final bool Function(T a, T b)? _equality;
  bool _isDisposed = false;

  WotValue({required T initialValue, WotForwarder<T>? valueForwarder, bool Function(T a, T b)? equality})
    : _lastValue = initialValue,
      _valueForwarder = valueForwarder,
      _equality = equality;
  void set(T value) {
    if (_isDisposed) {
      return;
    }

    final forwarder = _valueForwarder;
    if (forwarder != null) {
      final result = forwarder(value);
      if (result is Future) {
        unawaited(result.then((_) => notifyOfExternalUpdate(value)));
        return;
      }
    }
    notifyOfExternalUpdate(value);
  }

  Future<void> setAsync(T value) async {
    if (_isDisposed) {
      return;
    }

    final forwarder = _valueForwarder;
    if (forwarder != null) {
      await Future.sync(() => forwarder(value));
    }
    notifyOfExternalUpdate(value);
  }

  T get() => _lastValue;

  void notifyOfExternalUpdate(T value) {
    if (_isDisposed) {
      return;
    }

    bool isChanged;
    if (_equality != null) {
      isChanged = !_equality(value, _lastValue);
    } else {
      isChanged = value != _lastValue;
    }
    if (isChanged) {
      _lastValue = value;
      _controller.add(value);
    }
  }

  Stream<T> get onUpdate => _controller.stream;

  /// Dispose the WotValue and close the stream controller to prevent memory leaks.
  /// After calling dispose, this WotValue instance should not be used anymore.
  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      _controller.close();
    }
  }

  /// Check if this WotValue has been disposed
  bool get isDisposed => _isDisposed;
}
