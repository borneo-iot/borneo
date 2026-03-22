// Dart port of src/thing.ts

import 'package:cancellation_token/cancellation_token.dart';

import 'property.dart';
import 'event.dart';
import 'action.dart';
import 'types.dart';
import 'exceptions.dart';

/// A Web Thing.
class WotThing {
  final String id;
  final String title;
  final List<String> type;
  final String context;
  final String description;
  final Map<String, WotProperty> _properties = {};
  final Map<String, _AvailableAction> _availableActions = {};
  final Map<String, _AvailableEvent> _availableEvents = {};
  final Map<String, List<WotAction>> _actions = {};
  final List<WotEvent> _events = [];
  final Set<WotSubscriber> _subscribers = {};
  String _hrefPrefix = '';
  String? _uiHref;

  /// Initialize the object.
  ///
  /// [id] The thing's unique ID - must be a URI
  /// [title] The thing's title
  /// [type] The thing's type(s)
  /// [description] Description of the thing
  WotThing({required this.id, required this.title, required this.type, required this.description})
    : context = 'https://webthings.io/schemas';

  /// Return the thing state as a Thing Description.
  Map<String, dynamic> asThingDescription() {
    final thing = <String, dynamic>{
      'id': id,
      'title': title,
      '@context': context,
      '@type': type,
      'properties': getPropertyDescriptions(),
      'actions': <String, dynamic>{},
      'events': <String, dynamic>{},
      'links': [
        {'rel': 'properties', 'href': '$_hrefPrefix/properties'},
        {'rel': 'actions', 'href': '$_hrefPrefix/actions'},
        {'rel': 'events', 'href': '$_hrefPrefix/events'},
      ],
    };
    for (final name in _availableActions.keys) {
      final metadata = _availableActions[name]!.metadata;
      thing['actions'][name] = <String, dynamic>{
        if (metadata.type != null) 'type': metadata.type,
        if (metadata.atType != null) '@type': metadata.atType,
        if (metadata.title != null) 'title': metadata.title,
        if (metadata.description != null) 'description': metadata.description,
        if (metadata.input != null) 'input': metadata.input,
        if (metadata.output != null) 'output': metadata.output,
        'links': [
          {'rel': 'action', 'href': '$_hrefPrefix/actions/$name'},
        ],
      };
    }
    for (final name in _availableEvents.keys) {
      final metadata = _availableEvents[name]!.metadata;
      thing['events'][name] = <String, dynamic>{
        if (metadata.type != null) 'type': metadata.type,
        if (metadata.atType != null) '@type': metadata.atType,
        if (metadata.unit != null) 'unit': metadata.unit,
        if (metadata.title != null) 'title': metadata.title,
        if (metadata.description != null) 'description': metadata.description,
        if (metadata.minimum != null) 'minimum': metadata.minimum,
        if (metadata.maximum != null) 'maximum': metadata.maximum,
        if (metadata.multipleOf != null) 'multipleOf': metadata.multipleOf,
        if (metadata.enumValues != null) 'enum': metadata.enumValues,
        'links': [
          {'rel': 'event', 'href': '$_hrefPrefix/events/$name'},
        ],
      };
    }
    if (_uiHref != null) {
      (thing['links'] as List).add(<String, String>{'rel': 'alternate', 'mediaType': 'text/html', 'href': _uiHref!});
    }

    if (description.isNotEmpty) {
      thing['description'] = description;
    }

    return thing;
  }

  Future<void> sync({CancellationToken? cancelToken}) async {
    // Do nothing
  }

  // ---------------------------------------------------------------------------
  // Active / Inactive state machine
  // ---------------------------------------------------------------------------

  /// Whether this Thing is currently *active* (i.e. belongs to the currently
  /// selected scene).
  ///
  /// Active Things are allowed to poll the physical device periodically.
  /// Inactive Things retain their last-known property values but do not
  /// initiate any network requests.
  bool _isActive = false;
  bool get isActive => _isActive;

  /// Transition this Thing to the *active* state.
  ///
  /// Calls [onActivated] exactly once per activation.  Safe to call when
  /// already active (no-op).
  void activate() {
    if (!_isActive) {
      _isActive = true;
      onActivated();
    }
  }

  /// Transition this Thing to the *inactive* state.
  ///
  /// Calls [onDeactivated] exactly once per deactivation.  Safe to call when
  /// already inactive (no-op).
  void deactivate() {
    if (_isActive) {
      _isActive = false;
      onDeactivated();
    }
  }

  /// Called when this Thing transitions from inactive → active.
  ///
  /// Subclasses should override to restart periodic timers, trigger an
  /// initial [sync], etc.
  void onActivated() {}

  /// Called when this Thing transitions from active → inactive.
  ///
  /// Subclasses should override to cancel periodic timers while keeping
  /// property values intact.
  void onDeactivated() {}

  /// Get this thing's href.
  String get href {
    if (_hrefPrefix.isNotEmpty) {
      return _hrefPrefix;
    }
    return '/';
  }

  /// Get this thing's UI href.
  String? get uiHref => _uiHref;

  /// Set the prefix of any hrefs associated with this thing.
  void setHrefPrefix(String prefix) {
    _hrefPrefix = prefix;

    for (final property in _properties.values) {
      property.setHrefPrefix(prefix);
    }

    for (final actionName in _actions.keys) {
      for (final action in _actions[actionName]!) {
        action.setHrefPrefix(prefix);
      }
    }
  }

  /// Set the href of this thing's custom UI.
  void setUiHref(String href) {
    _uiHref = href;
  }

  /// Get the thing's properties as an object.
  Map<String, Map<String, dynamic>> getPropertyDescriptions() {
    final descriptions = <String, Map<String, dynamic>>{};
    for (final name in _properties.keys) {
      descriptions[name] = _properties[name]!.asPropertyDescription();
    }
    return descriptions;
  }

  /// Get the thing's actions as an array.
  ///
  /// [actionName] Optional action name to get descriptions for
  List<Map<String, dynamic>> getActionDescriptions([String? actionName]) {
    final descriptions = <Map<String, dynamic>>[];

    if (actionName == null) {
      for (final name in _actions.keys) {
        for (final action in _actions[name]!) {
          descriptions.add(action.asActionDescription());
        }
      }
    } else if (_actions.containsKey(actionName)) {
      for (final action in _actions[actionName]!) {
        descriptions.add(action.asActionDescription());
      }
    }

    return descriptions;
  }

  /// Get the thing's events as an array.
  ///
  /// [eventName] Optional event name to get descriptions for
  List<Map<String, dynamic>> getEventDescriptions([String? eventName]) {
    if (eventName == null) {
      return _events.map((e) => e.asEventDescription()).toList();
    } else {
      return _events.where((e) => e.name == eventName).map((e) => e.asEventDescription()).toList();
    }
  }

  /// Add a property to this thing.
  void addProperty(WotProperty property) {
    property.setHrefPrefix(_hrefPrefix);
    _properties[property.name] = property;
  }

  /// Remove a property from this thing.
  void removeProperty(WotProperty property) {
    _properties.remove(property.name);
  }

  /// Find a property by name.
  ///
  /// Returns Property if found, else null
  WotProperty? findProperty(String propertyName) {
    return _properties[propertyName];
  }

  /// Get a property's value.
  ///
  /// Returns current property value if found, else null
  T? getProperty<T>(String propertyName) {
    final prop = findProperty(propertyName);
    final value = prop?.getValue();
    return value is T ? value : null;
  }

  /// Get a mapping of all properties and their values.
  ///
  /// Returns a map of propertyName -> value.
  Map<String, dynamic> getProperties() {
    final props = <String, dynamic>{};
    for (final name in _properties.keys) {
      props[name] = _properties[name]!.getValue();
    }
    return props;
  }

  /// Determine whether or not this thing has a given property.
  bool hasProperty(String propertyName) {
    return _properties.containsKey(propertyName);
  }

  /// Set a property value.
  void setProperty(String propertyName, dynamic value) {
    final prop = findProperty(propertyName);
    prop?.setValue(value);
  }

  /// Set a property value and wait for the write to complete.
  Future<void> setPropertyAsync(String propertyName, dynamic value) async {
    final prop = findProperty(propertyName);
    if (prop == null) {
      return;
    }

    await prop.setValueAsync(value);
  }

  /// Get an action.
  ///
  /// Returns the requested action if found, else null
  WotAction? getAction(String actionName, String actionId) {
    if (!_actions.containsKey(actionName)) {
      return null;
    }

    for (final action in _actions[actionName]!) {
      if (action.id == actionId) {
        return action;
      }
    }

    return null;
  }

  /// Add a new event and notify subscribers.
  void addEvent(WotEvent event) {
    _events.add(event);
    eventNotify(event);
  }

  /// Add an available event.
  ///
  /// [name] Name of the event
  /// [metadata] Event metadata, i.e. type, description, etc.
  void addAvailableEvent(String name, [WotEventMetadata? metadata]) {
    metadata ??= WotEventMetadata();
    _availableEvents[name] = _AvailableEvent(metadata: metadata, subscribers: <WotSubscriber>{});
  }

  /// Perform an action on the thing.
  ///
  /// Returns the action that was created.
  WotAction? performAction(String actionName, [dynamic input]) {
    if (this is WotActionGuard) {
      final guard = this as WotActionGuard;
      if (!guard.canPerformAction(actionName)) {
        throw InvalidOperationException(message: guard.getActionGuardError(actionName) ?? 'Action is not allowed');
      }
    }
    if (!_availableActions.containsKey(actionName)) {
      return null;
    }

    final actionType = _availableActions[actionName]!;

    // TODO: Add JSON schema validation for input
    // This would require adding a JSON schema validation library

    final action = actionType.factory(this, input);
    action.setHrefPrefix(_hrefPrefix);
    actionNotify(action);
    _actions[actionName]!.add(action);
    return action;
  }

  /// Perform an action on the thing and wait until it finishes.
  ///
  /// Returns the action that was created, or null if the action does not exist.
  Future<WotAction?> performActionAndWait(String actionName, [dynamic input]) async {
    final action = performAction(actionName, input);
    if (action == null) {
      return null;
    }

    await action.invoke();
    return action;
  }

  /// Remove an existing action.
  ///
  /// Returns boolean indicating the presence of the action.
  bool removeAction(String actionName, String actionId) {
    final action = getAction(actionName, actionId);
    if (action == null) {
      return false;
    }

    action.cancel();
    final actions = _actions[actionName]!;
    actions.removeWhere((a) => a.id == actionId);
    return true;
  }

  /// Add an available action.
  ///
  /// [name] Name of the action
  /// [metadata] Action metadata, i.e. type, description, etc.
  /// [factory] Factory function to create action instances
  void addAvailableAction(
    String name,
    WotActionMetadata? metadata,
    WotAction Function(WotThing thing, dynamic input) factory,
  ) {
    metadata ??= WotActionMetadata();
    _availableActions[name] = _AvailableAction(metadata: metadata, factory: factory);
    _actions[name] = [];
  }

  /// Add a new websocket subscriber.
  void addSubscriber(WotSubscriber ws) {
    _subscribers.add(ws);
  }

  /// Remove a websocket subscriber.
  void removeSubscriber(WotSubscriber ws) {
    _subscribers.remove(ws);
    for (final name in _availableEvents.keys) {
      removeEventSubscriber(name, ws);
    }
  }

  /// Add a new websocket subscriber to an event.
  void addEventSubscriber(String name, WotSubscriber ws) {
    if (_availableEvents.containsKey(name)) {
      _availableEvents[name]!.subscribers.add(ws);
    }
  }

  /// Remove a websocket subscriber from an event.
  void removeEventSubscriber(String name, WotSubscriber ws) {
    if (_availableEvents.containsKey(name)) {
      _availableEvents[name]!.subscribers.remove(ws);
    }
  }

  /// Notify all subscribers of a property change.
  void propertyNotify(WotProperty property) {
    final message = WotMessage(messageType: WotMessageType.propertyStatus, data: {property.name: property.getValue()});

    for (final subscriber in _subscribers) {
      try {
        subscriber(message);
      } catch (e) {
        // do nothing
      }
    }
  }

  /// Notify all subscribers of an action status change.
  void actionNotify(WotAction action) {
    final message = WotMessage(messageType: WotMessageType.actionStatus, data: action.asActionDescription());

    for (final subscriber in _subscribers) {
      try {
        subscriber(message);
      } catch (e) {
        // do nothing
      }
    }
  }

  /// Notify all subscribers of an event.
  void eventNotify(WotEvent event) {
    if (!_availableEvents.containsKey(event.name)) {
      return;
    }

    final message = WotMessage(messageType: WotMessageType.event, data: event.asEventDescription());

    for (final subscriber in _availableEvents[event.name]!.subscribers) {
      try {
        subscriber(message);
      } catch (e) {
        // do nothing
      }
    }
  }

  void dispose() {
    // Dispose all properties
    for (final property in _properties.values) {
      property.dispose();
    }
    _properties.clear();

    // Clear other collections
    _availableActions.clear();
    _availableEvents.clear();
    _actions.clear();
    _events.clear();
    _subscribers.clear();
  }
}

class _AvailableAction {
  final WotActionMetadata metadata;
  final WotAction Function(WotThing thing, dynamic input) factory;

  _AvailableAction({required this.metadata, required this.factory});
}

class _AvailableEvent {
  final WotEventMetadata metadata;
  final Set<WotSubscriber> subscribers;

  _AvailableEvent({required this.metadata, required this.subscribers});
}

class WotActionMetadata {
  final String? type;
  final String? atType;
  final String? title;
  final String? description;
  final Map<String, dynamic>? input;
  final Map<String, dynamic>? output;
  final List<WotLink>? links;

  WotActionMetadata({this.type, this.atType, this.title, this.description, this.input, this.output, this.links});
}
