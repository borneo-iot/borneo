// Dart port of src/action.ts
// High-level Action base class implementation.

import 'utils.dart' as utils;
import 'thing.dart';
import 'types.dart';

class WotActionFailure {
  final String kind;
  final String message;
  final String timestamp;
  final String? stackTrace;

  WotActionFailure({required this.kind, required this.message, this.stackTrace, String? timestamp})
    : timestamp = timestamp ?? utils.timestamp();

  factory WotActionFailure.fromError(Object error, [StackTrace? stackTrace]) {
    return WotActionFailure(
      kind: error.runtimeType.toString(),
      message: error.toString(),
      stackTrace: stackTrace?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'kind': kind, 'message': message, 'timestamp': timestamp, if (stackTrace != null) 'stackTrace': stackTrace};
  }
}

class WotAction<InputType> {
  final String id;
  final WotThing thing;
  final String name;
  final InputType input;
  String hrefPrefix = '';
  late final String _href;
  String status = 'created';
  final String timeRequested;
  String? timeCompleted;
  String? error;
  WotActionFailure? failure;

  WotAction({required this.id, required this.thing, required this.name, required this.input})
    : timeRequested = utils.timestamp() {
    _href = '/actions/$name/$id';
    timeCompleted = null;
  }
  Map<String, dynamic> asActionDescription() {
    final description = <String, dynamic>{
      name: <String, dynamic>{'href': href, 'timeRequested': timeRequested, 'status': status},
    };

    if (input != null) {
      (description[name] as Map<String, dynamic>)['input'] = input;
    }

    if (timeCompleted != null) {
      (description[name] as Map<String, dynamic>)['timeCompleted'] = timeCompleted;
    }

    if (error != null) {
      (description[name] as Map<String, dynamic>)['error'] = error;
    }

    if (failure != null) {
      (description[name] as Map<String, dynamic>)['failure'] = failure!.toMap();
    }

    return description;
  }

  void setHrefPrefix(String prefix) {
    hrefPrefix = prefix;
  }

  String get href => hrefPrefix + _href;

  void start() {
    status = 'pending';
    thing.actionNotify(this);
    performAction().then((_) => finish(), onError: (e, st) => finishWithError(e, st));
  }

  Future<void> performAction() async {}
  Future<void> cancel() async {}

  void finish() {
    status = 'completed';
    timeCompleted = utils.timestamp();
    error = null;
    failure = null;
    thing.actionNotify(this);
  }

  void finishWithError(Object e, [StackTrace? stackTrace]) {
    status = 'error';
    failure = WotActionFailure.fromError(e, stackTrace);
    error = failure!.message;
    timeCompleted = utils.timestamp();
    thing.actionNotify(this);
  }

  Future<void> invoke() async {
    status = 'pending';
    thing.actionNotify(this);
    try {
      await performAction();
      finish();
    } catch (e, st) {
      finishWithError(e, st);
      rethrow;
    }
  }
}

class ActionMetadata {
  final String? title;
  final String? description;
  final List<WotLink>? links;
  final Map<String, dynamic>? input;
  ActionMetadata({this.title, this.description, this.links, this.input});
}

class ActionDescription<InputType> {
  final String href;
  final String timeRequested;
  final String status;
  final InputType? input;
  final String? timeCompleted;
  final String? error;
  final WotActionFailure? failure;
  ActionDescription({
    required this.href,
    required this.timeRequested,
    required this.status,
    this.input,
    this.timeCompleted,
    this.error,
    this.failure,
  });
}
