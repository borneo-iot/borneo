import 'dart:async';

import 'package:borneo_kernel_abstractions/events.dart';
import 'package:lw_wot/wot.dart';

abstract class BorneoThing extends WotThing {
  bool get isOffline => !(super.getProperty<bool>('online') ?? false);

  BorneoThing({required super.id, required super.title, required super.type, required super.description}) {
    // Online property - indicates connection status
    final onlineProperty = WotProperty<bool>(
      thing: this,
      name: 'online',
      value: WotValue<bool>(
        initialValue: false,
        valueForwarder: (_) => throw UnsupportedError('Online status is read-only'),
      ),
      metadata: WotPropertyMetadata(
        type: 'boolean',
        title: 'Online',
        description: 'Device connection status',
        readOnly: true,
      ),
    );
    addProperty(onlineProperty);
  }
}

/// Generic WotProperty that handles event subscription and value mapping
class ObservableWotProperty<T, E> extends WotProperty<T> {
  final DeviceEventBus deviceEvents;
  final String eventName;
  final T Function(E event) mapper;
  final bool subscribe;
  StreamSubscription? _eventSubscription;

  ObservableWotProperty({
    required super.thing,
    required this.deviceEvents,
    required super.name,
    required super.value,
    required super.metadata,
    required this.eventName,
    required this.mapper,
    this.subscribe = true,
  }) {
    if (subscribe) {
      subscribeToEvents();
    }
  }

  void subscribeToEvents() {
    _eventSubscription = deviceEvents.on<E>().listen((event) {
      final newValue = mapper(event);
      value.notifyOfExternalUpdate(newValue);
      thing.addEvent(WotEvent(thing: thing, name: eventName, data: newValue));
    });
  }

  void unsubscribeFromEvents() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  @override
  void dispose() {
    unsubscribeFromEvents();
    super.dispose();
  }
}
