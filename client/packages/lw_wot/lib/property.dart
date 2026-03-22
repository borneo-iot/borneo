// Dart port of src/property.ts

import 'dart:async';

import 'thing.dart';

import 'types.dart';
import 'value.dart';

class WotPropertyFailure {
  final String propertyName;
  final String kind;
  final String message;
  final String timestamp;
  final String? stackTrace;

  WotPropertyFailure({
    required this.propertyName,
    required this.kind,
    required this.message,
    this.stackTrace,
    String? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc().toIso8601String();

  factory WotPropertyFailure.fromError(String propertyName, Object error, [StackTrace? stackTrace]) {
    return WotPropertyFailure(
      propertyName: propertyName,
      kind: error.runtimeType.toString(),
      message: error.toString(),
      stackTrace: stackTrace?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'propertyName': propertyName,
      'kind': kind,
      'message': message,
      'timestamp': timestamp,
      if (stackTrace != null) 'stackTrace': stackTrace,
    };
  }
}

class WotPropertyMetadata {
  final String? type;
  final String? atType;
  final String? unit;
  final String? title;
  final String? description;
  final List<WotLink>? links;
  final List<dynamic>? enumValues;
  final bool? readOnly;
  final num? minimum;
  final num? maximum;
  final num? multipleOf;

  WotPropertyMetadata({
    this.type,
    this.atType,
    this.unit,
    this.title,
    this.description,
    this.links,
    this.enumValues,
    this.readOnly,
    this.minimum,
    this.maximum,
    this.multipleOf,
  });

  factory WotPropertyMetadata.fromMap(Map<String, dynamic> map) {
    return WotPropertyMetadata(
      type: map['type'],
      atType: map['@type'],
      unit: map['unit'],
      title: map['title'],
      description: map['description'],
      links: map['links'] != null
          ? List<WotLink>.from(
              map['links'].map((l) => WotLink(rel: l['rel'], href: l['href'], mediaType: l['mediaType'])),
            )
          : null,
      enumValues: map['enum'],
      readOnly: map['readOnly'],
      minimum: map['minimum'],
      maximum: map['maximum'],
      multipleOf: map['multipleOf'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (type != null) 'type': type,
      if (atType != null) '@type': atType,
      if (unit != null) 'unit': unit,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (links != null) 'links': links!.map((l) => {'rel': l.rel, 'href': l.href, 'mediaType': l.mediaType}).toList(),
      if (enumValues != null) 'enum': enumValues,
      if (readOnly != null) 'readOnly': readOnly,
      if (minimum != null) 'minimum': minimum,
      if (maximum != null) 'maximum': maximum,
      if (multipleOf != null) 'multipleOf': multipleOf,
    };
  }
}

abstract class WotWriteGuard {
  bool canWriteProperty(String propertyName);
  String? getWriteGuardError(String propertyName);
}

abstract class WotActionGuard {
  bool canPerformAction(String actionName);
  String? getActionGuardError(String actionName);
}

class WotProperty<T> {
  final String name;
  final WotValue<T> value;
  final WotPropertyMetadata metadata;
  WotPropertyFailure? failure;
  String hrefPrefix = '';
  late final String _href;
  final WotThing thing;

  WotProperty({required this.thing, required this.name, required this.value, required this.metadata}) {
    _href = '/properties/$name';
    value.onUpdate.listen((_) {
      failure = null;
      thing.propertyNotify(this);
    });
  }

  void setHrefPrefix(String prefix) {
    hrefPrefix = prefix;
  }

  String get href => hrefPrefix + _href;
  T getValue() => value.get();
  void setValue(T newValue) {
    try {
      validateValue(newValue);
      value.set(newValue);
      failure = null;
    } catch (e, st) {
      failure = WotPropertyFailure.fromError(name, e, st);
      rethrow;
    }
  }

  Future<void> setValueAsync(T newValue) async {
    try {
      validateValue(newValue);
      await value.setAsync(newValue);
      failure = null;
    } catch (e, st) {
      failure = WotPropertyFailure.fromError(name, e, st);
      rethrow;
    }
  }

  void validateValue(T v) {
    if (metadata.readOnly == true) {
      throw Exception('Read-only property');
    }
    if (thing is WotWriteGuard) {
      final guard = thing as WotWriteGuard;
      if (!guard.canWriteProperty(name)) {
        throw Exception(guard.getWriteGuardError(name) ?? 'Property is not writable');
      }
    }
  }

  Map<String, dynamic> asPropertyDescription() {
    final desc = Map<String, dynamic>.from(metadata.toMap());
    desc['links'] = (desc['links'] ?? [])..add({'rel': 'property', 'href': href});
    return desc;
  }

  String? get error => failure?.message;

  bool get hasError => failure != null;

  /// Dispose the property and its internal value to prevent memory leaks.
  /// After calling dispose, this property should not be used anymore.
  void dispose() {
    value.dispose();
  }
}
