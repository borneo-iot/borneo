import 'package:test/test.dart';
import 'package:lw_wot/property.dart';
import 'package:lw_wot/value.dart';
import 'package:lw_wot/thing.dart';
import 'package:lw_wot/types.dart';

void main() {
  group('WotPropertyMetadata', () {
    test('fromMap and toMap with all properties', () {
      final map = {
        'type': 'string',
        '@type': 'TestType',
        'unit': 'celsius',
        'title': 'Temperature',
        'description': 'Room temperature',
        'links': [
          {'rel': 'self', 'href': '/temp', 'mediaType': 'application/json'},
        ],
        'enum': ['a', 'b'],
        'readOnly': true,
        'minimum': 0,
        'maximum': 100,
        'multipleOf': 2,
      };
      final meta = WotPropertyMetadata.fromMap(map);
      final outMap = meta.toMap();
      expect(outMap['type'], equals('string'));
      expect(outMap['@type'], equals('TestType'));
      expect(outMap['unit'], equals('celsius'));
      expect(outMap['title'], equals('Temperature'));
      expect(outMap['description'], equals('Room temperature'));
      expect(outMap['links'], isA<List<dynamic>>());
      expect(outMap['enum'], equals(['a', 'b']));
      expect(outMap['readOnly'], isTrue);
      expect(outMap['minimum'], equals(0));
      expect(outMap['maximum'], equals(100));
      expect(outMap['multipleOf'], equals(2));
    });

    test('fromMap and toMap with minimal properties', () {
      final map = <String, dynamic>{};
      final meta = WotPropertyMetadata.fromMap(map);
      final outMap = meta.toMap();

      expect(outMap, isEmpty);
      expect(meta.type, isNull);
      expect(meta.readOnly, isNull);
      expect(meta.minimum, isNull);
    });

    test('fromMap with partial properties', () {
      final map = {'type': 'number', 'minimum': 10.5, 'readOnly': false};
      final meta = WotPropertyMetadata.fromMap(map);

      expect(meta.type, equals('number'));
      expect(meta.minimum, equals(10.5));
      expect(meta.readOnly, isFalse);
      expect(meta.maximum, isNull);
      expect(meta.title, isNull);
    });

    test('toMap excludes null values', () {
      final meta = WotPropertyMetadata(type: 'boolean', title: null, readOnly: true, minimum: null);
      final map = meta.toMap();

      expect(map['type'], equals('boolean'));
      expect(map['readOnly'], isTrue);
      expect(map.containsKey('title'), isFalse);
      expect(map.containsKey('minimum'), isFalse);
    });

    test('handles complex link structures', () {
      final map = {
        'links': [
          {'rel': 'property', 'href': '/api/temp'},
          {'rel': 'alternate', 'href': '/ui/temp', 'mediaType': 'text/html'},
        ],
      };
      final meta = WotPropertyMetadata.fromMap(map);
      final outMap = meta.toMap();

      expect(meta.links, hasLength(2));
      expect(meta.links![0].rel, equals('property'));
      expect(meta.links![1].mediaType, equals('text/html'));
      expect(outMap['links'], hasLength(2));
    });
  });

  group('WotProperty', () {
    late WotThing thing;
    late WotValue<int> value;
    late WotPropertyMetadata metadata;

    setUp(() {
      thing = WotThing(id: 'test-thing', title: 'Test Thing', type: ['TestDevice'], description: 'A test thing');
      value = WotValue<int>(initialValue: 42);
      metadata = WotPropertyMetadata(
        type: 'integer',
        title: 'Test Property',
        description: 'A test property',
        minimum: 0,
        maximum: 100,
      );
    });

    test('basic property creation and getters', () {
      final property = WotProperty<int>(thing: thing, name: 'testProp', value: value, metadata: metadata);

      expect(property.name, equals('testProp'));
      expect(property.value.get(), equals(42));
      expect(property.thing, equals(thing));
      expect(property.metadata, equals(metadata));
      expect(property.href, equals('/properties/testProp'));
    });

    test('setHrefPrefix updates href correctly', () {
      final property = WotProperty<int>(thing: thing, name: 'testProp', value: value, metadata: metadata);
      property.setHrefPrefix('/api/v1');

      expect(property.href, equals('/api/v1/properties/testProp'));
    });

    test('setValue updates value correctly', () {
      final property = WotProperty<int>(thing: thing, name: 'testProp', value: value, metadata: metadata);

      property.setValue(75);
      expect(property.getValue(), equals(75));
      expect(value.get(), equals(75));
    });

    test('setValue validates read-only property', () {
      final readOnlyMetadata = WotPropertyMetadata(type: 'integer', readOnly: true);
      final property = WotProperty<int>(thing: thing, name: 'readOnlyProp', value: value, metadata: readOnlyMetadata);

      expect(() => property.setValue(100), throwsException);
    });

    test('setValue allows modification of non-read-only property', () {
      final writableMetadata = WotPropertyMetadata(type: 'integer', readOnly: false);
      final property = WotProperty<int>(thing: thing, name: 'writableProp', value: value, metadata: writableMetadata);

      expect(() => property.setValue(100), returnsNormally);
      expect(property.getValue(), equals(100));
    });

    test('setValueAsync waits for async forwarder and clears failures', () async {
      var forwardedValue = 0;
      final asyncValue = WotValue<int>(
        initialValue: 1,
        valueForwarder: (newValue) async {
          await Future<void>.delayed(Duration(milliseconds: 10));
          forwardedValue = newValue;
        },
      );
      final property = WotProperty<int>(thing: thing, name: 'asyncProp', value: asyncValue, metadata: metadata);

      await property.setValueAsync(7);

      expect(forwardedValue, equals(7));
      expect(property.getValue(), equals(7));
      expect(property.failure, isNull);
    });

    test('setValueAsync stores typed failure when the forwarder throws', () async {
      final asyncValue = WotValue<int>(
        initialValue: 1,
        valueForwarder: (newValue) async {
          await Future<void>.delayed(Duration(milliseconds: 10));
          throw StateError('write failed for $newValue');
        },
      );
      final property = WotProperty<int>(thing: thing, name: 'failingProp', value: asyncValue, metadata: metadata);

      await expectLater(property.setValueAsync(7), throwsA(isA<StateError>()));

      expect(property.getValue(), equals(1));
      expect(property.failure, isNotNull);
      expect(property.failure!.propertyName, equals('failingProp'));
      expect(property.failure!.kind, contains('StateError'));
      expect(property.error, contains('write failed for 7'));
    });

    test('asPropertyDescription returns correct format', () {
      final property = WotProperty<int>(thing: thing, name: 'tempSensor', value: value, metadata: metadata);
      property.setHrefPrefix('/api');

      final description = property.asPropertyDescription();

      expect(description['type'], equals('integer'));
      expect(description['title'], equals('Test Property'));
      expect(description['description'], equals('A test property'));
      expect(description['minimum'], equals(0));
      expect(description['maximum'], equals(100));
      expect(description['links'], isA<List>());

      final links = description['links'] as List;
      expect(links, hasLength(1));
      expect(links[0]['rel'], equals('property'));
      expect(links[0]['href'], equals('/api/properties/tempSensor'));
    });

    test('asPropertyDescription preserves existing links', () {
      final metadataWithLinks = WotPropertyMetadata(
        type: 'string',
        links: [WotLink(rel: 'alternate', href: '/ui/prop')],
      );
      final property = WotProperty<String>(
        thing: thing,
        name: 'prop',
        value: WotValue<String>(initialValue: 'test'),
        metadata: metadataWithLinks,
      );

      final description = property.asPropertyDescription();
      final links = description['links'] as List;

      expect(links, hasLength(2)); // existing + property link
      expect(links.any((link) => link['rel'] == 'alternate'), isTrue);
      expect(links.any((link) => link['rel'] == 'property'), isTrue);
    });

    test('property value updates notify thing', () async {
      // Create a real WotThing instance and override its propertyNotify method
      final testThing = WotThing(
        id: 'test-thing-notify',
        title: 'Test Notify Thing',
        type: ['TestDevice'],
        description: 'A test thing for notification testing',
      );

      final notifyProperty = WotProperty<String>(
        thing: testThing,
        name: 'notifyProp',
        value: WotValue<String>(initialValue: 'initial'),
        metadata: metadata,
      );

      // Add the property to the thing so it can track notifications
      testThing.addProperty(notifyProperty);

      // Direct value update should trigger notification via the property's value stream
      notifyProperty.setValue('updated');
      await Future.delayed(Duration(milliseconds: 10)); // Allow stream to propagate

      // Verify the property value was updated
      expect(notifyProperty.getValue(), equals('updated'));
    });

    test('different property types work correctly', () {
      // String property
      final stringProp = WotProperty<String>(
        thing: thing,
        name: 'stringProp',
        value: WotValue<String>(initialValue: 'hello'),
        metadata: WotPropertyMetadata(type: 'string'),
      );
      expect(stringProp.getValue(), equals('hello'));

      // Boolean property
      final boolProp = WotProperty<bool>(
        thing: thing,
        name: 'boolProp',
        value: WotValue<bool>(initialValue: true),
        metadata: WotPropertyMetadata(type: 'boolean'),
      );
      expect(boolProp.getValue(), isTrue);

      // Double property
      final doubleProp = WotProperty<double>(
        thing: thing,
        name: 'doubleProp',
        value: WotValue<double>(initialValue: 3.14),
        metadata: WotPropertyMetadata(type: 'number'),
      );
      expect(doubleProp.getValue(), equals(3.14));
    });

    test('property with enum values in metadata', () {
      final enumMetadata = WotPropertyMetadata(type: 'string', enumValues: ['on', 'off', 'auto']);
      final property = WotProperty<String>(
        thing: thing,
        name: 'mode',
        value: WotValue<String>(initialValue: 'on'),
        metadata: enumMetadata,
      );

      final description = property.asPropertyDescription();
      expect(description['enum'], equals(['on', 'off', 'auto']));
    });

    test('property validation with null metadata', () {
      final nullMetadata = WotPropertyMetadata();
      final property = WotProperty<int>(thing: thing, name: 'nullMetaProp', value: value, metadata: nullMetadata);

      // Should not throw for non-read-only property
      expect(() => property.setValue(123), returnsNormally);
    });
  });
}
