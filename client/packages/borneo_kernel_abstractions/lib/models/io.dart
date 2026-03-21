import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';

enum IOCommandPriority { low, normal, high }

class IORequest {
  final Future<dynamic> Function() task;
  final Completer<dynamic> completer;
  final IOCommandPriority priority;
  final CancellationToken? cancel;

  IORequest(this.task, this.completer, this.priority, {this.cancel});
}

class IORequestQueue {
  final List<IORequest> _queue = [];
  bool _isProcessing = false;
  bool _disposed = false;
  IORequest? _currentItem;

  void dispose() {
    _disposed = true;
    if (_currentItem != null && !_currentItem!.completer.isCompleted) {
      _currentItem!.completer.completeError(Exception('Queue disposed'));
    }
    for (final item in _queue) {
      if (!item.completer.isCompleted) {
        item.completer.completeError(Exception('Queue disposed'));
      }
    }
    _queue.clear();
  }

  Future<T> submit<T>(
    Future<T> Function() task, {
    IOCommandPriority priority = IOCommandPriority.normal,
    CancellationToken? cancel,
  }) {
    if (_disposed) {
      throw StateError('IORequestQueue has been disposed');
    }
    final completer = Completer<T>();
    final item = IORequest(task, completer, priority, cancel: cancel);

    int index = _queue.length;
    for (int i = 0; i < _queue.length; i++) {
      if (_queue[i].priority.index < priority.index) {
        index = i;
        break;
      }
    }
    _queue.insert(index, item);

    if (!_isProcessing) {
      _processQueue();
    }

    return completer.future;
  }

  Future<T>? trySubmit<T>(
    Future<T> Function() task, {
    IOCommandPriority priority = IOCommandPriority.normal,
    CancellationToken? cancel,
  }) {
    if (_disposed) {
      throw StateError('IORequestQueue has been disposed');
    }

    if (!isIdle) {
      return null;
    }

    return submit(task, priority: priority, cancel: cancel);
  }

  void _processQueue() async {
    if (_queue.isEmpty || _disposed) {
      _isProcessing = false;
      return;
    }

    _isProcessing = true;

    while (_queue.isNotEmpty && !_disposed) {
      _currentItem = _queue.removeAt(0);
      final item = _currentItem!;
      try {
        final result = await item.task();
        if (!item.completer.isCompleted) {
          if (item.cancel?.isCancelled ?? false) {
            item.completer.completeError(CancelledException());
          } else {
            item.completer.complete(result);
          }
        }
      } catch (e) {
        if (!item.completer.isCompleted) {
          item.completer.completeError(e);
        }
      } finally {
        _currentItem = null;
      }
    }

    _isProcessing = false;
  }

  int get length => _queue.length;

  bool get isIdle => !_isProcessing && _queue.isEmpty && _currentItem == null;
}
