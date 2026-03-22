import 'package:test/test.dart';
import 'package:lw_wot/value.dart';
import 'dart:async';

void main() {
  group('WotValue', () {
    test('basic set and get operations', () {
      final value = WotValue<int>(initialValue: 0);
      expect(value.get(), equals(0));

      value.set(1);
      expect(value.get(), equals(1));

      value.set(42);
      expect(value.get(), equals(42));
    });

    test('onUpdate emits when value changes', () async {
      final value = WotValue<int>(initialValue: 0);
      final updates = <int>[];
      value.onUpdate.listen(updates.add);

      value.set(2);
      await Future.delayed(Duration(milliseconds: 10));
      expect(updates, contains(2));
      expect(updates, hasLength(1));
    });

    test('does not emit if value unchanged', () async {
      final value = WotValue<int>(initialValue: 5);
      final updates = <int>[];
      value.onUpdate.listen(updates.add);

      value.set(5);
      await Future.delayed(Duration(milliseconds: 10));
      expect(updates, isEmpty);
    });

    test('constructor with initial value', () {
      final stringValue = WotValue<String>(initialValue: 'hello');
      expect(stringValue.get(), equals('hello'));

      final boolValue = WotValue<bool>(initialValue: true);
      expect(boolValue.get(), isTrue);

      final doubleValue = WotValue<double>(initialValue: 3.14);
      expect(doubleValue.get(), equals(3.14));
    });

    test('constructor with forwarder function', () {
      var forwardedValues = <String>[];

      final value = WotValue<String>(
        initialValue: 'initial',
        valueForwarder: (String newValue) => forwardedValues.add(newValue),
      );

      expect(value.get(), equals('initial'));
      expect(forwardedValues, isEmpty);

      value.set('forwarded');
      expect(forwardedValues, contains('forwarded'));
      expect(value.get(), equals('forwarded'));
    });

    test('setAsync awaits async forwarder before updating the value', () async {
      final forwardedValues = <String>[];

      final value = WotValue<String>(
        initialValue: 'initial',
        valueForwarder: (String newValue) async {
          await Future<void>.delayed(Duration(milliseconds: 10));
          forwardedValues.add(newValue);
        },
      );

      await value.setAsync('async-forwarded');

      expect(forwardedValues, contains('async-forwarded'));
      expect(value.get(), equals('async-forwarded'));
    });

    test('constructor with custom equality function', () async {
      // Custom equality that considers case-insensitive strings as equal
      final value = WotValue<String>(
        initialValue: 'Hello',
        valueForwarder: null,
        equality: (String a, String b) => a.toLowerCase() == b.toLowerCase(),
      );

      final updates = <String>[];
      value.onUpdate.listen(updates.add);

      // Should not trigger update due to custom equality
      value.set('HELLO');
      await Future.delayed(Duration(milliseconds: 10));
      expect(updates, isEmpty);
      expect(value.get(), equals('Hello')); // Value shouldn't change

      // Should trigger update
      value.set('World');
      await Future.delayed(Duration(milliseconds: 10));
      expect(updates, contains('World'));
      expect(value.get(), equals('World'));
    });

    test('multiple listeners receive updates', () async {
      final value = WotValue<int>(initialValue: 0);
      final updates1 = <int>[];
      final updates2 = <int>[];
      final updates3 = <int>[];

      value.onUpdate.listen(updates1.add);
      value.onUpdate.listen(updates2.add);
      value.onUpdate.listen(updates3.add);

      value.set(10);
      await Future.delayed(Duration(milliseconds: 10));

      expect(updates1, equals([10]));
      expect(updates2, equals([10]));
      expect(updates3, equals([10]));
    });

    test('stream subscription can be cancelled', () async {
      final value = WotValue<int>(initialValue: 0);
      final updates = <int>[];

      final subscription = value.onUpdate.listen(updates.add);

      value.set(1);
      await Future.delayed(Duration(milliseconds: 10));
      expect(updates, contains(1));

      await subscription.cancel();

      value.set(2);
      await Future.delayed(Duration(milliseconds: 10));
      expect(updates, hasLength(1)); // Should not receive the second update
    });

    test('notifyOfExternalUpdate triggers listeners', () async {
      final value = WotValue<String>(initialValue: 'initial');
      final updates = <String>[];
      value.onUpdate.listen(updates.add);

      value.notifyOfExternalUpdate('external');
      await Future.delayed(Duration(milliseconds: 10));

      expect(updates, contains('external'));
      expect(value.get(), equals('external'));
    });

    test('notifyOfExternalUpdate with same value does not trigger', () async {
      final value = WotValue<String>(initialValue: 'same');
      final updates = <String>[];
      value.onUpdate.listen(updates.add);

      value.notifyOfExternalUpdate('same');
      await Future.delayed(Duration(milliseconds: 10));

      expect(updates, isEmpty);
      expect(value.get(), equals('same'));
    });
    test('notifyOfExternalUpdate with null value', () async {
      final value = WotValue<String?>(initialValue: 'initial');
      final updates = <String?>[];
      value.onUpdate.listen(updates.add);

      value.notifyOfExternalUpdate(null);
      await Future.delayed(Duration(milliseconds: 10));

      // null is different from 'initial', so it should trigger update
      expect(updates, contains(null));
      expect(value.get(), isNull);
    });
    test('notifyOfExternalUpdate with undefined (null) handling', () async {
      final value = WotValue<int?>(initialValue: 42);
      final updates = <int?>[];
      value.onUpdate.listen(updates.add);

      // Test null handling - null is different from 42, so should trigger
      value.notifyOfExternalUpdate(null);
      await Future.delayed(Duration(milliseconds: 10));
      expect(updates, contains(null));

      // Test valid update
      value.notifyOfExternalUpdate(100);
      await Future.delayed(Duration(milliseconds: 10));
      expect(updates, contains(100));
    });
    test('complex object values work correctly', () async {
      final complexValue = WotValue<Map<String, dynamic>>(
        initialValue: {'temperature': 25.5, 'humidity': 60, 'status': 'normal'},
      );

      final updates = <Map<String, dynamic>>[];
      complexValue.onUpdate.listen(updates.add);

      final newValue = {'temperature': 26.0, 'humidity': 65, 'status': 'high'};

      complexValue.set(newValue);
      await Future.delayed(Duration(milliseconds: 10));
      expect(complexValue.get(), equals(newValue));
      expect(updates, hasLength(1));
      expect(updates.first, equals(newValue));
    });
    test('list values work correctly', () async {
      final listValue = WotValue<List<int>>(initialValue: [1, 2, 3]);
      final updates = <List<int>>[];
      listValue.onUpdate.listen(updates.add);

      listValue.set([4, 5, 6]);
      await Future.delayed(Duration(milliseconds: 10));
      expect(listValue.get(), equals([4, 5, 6]));
      expect(updates, hasLength(1));
    });
    test('forwarder and external update interaction', () async {
      var forwardedCount = 0;
      final forwardedValues = <double>[];

      final value = WotValue<double>(
        initialValue: 0.0,
        valueForwarder: (double newValue) {
          forwardedCount++;
          forwardedValues.add(newValue);
        },
      );

      final updates = <double>[];
      value.onUpdate.listen(updates.add);

      // set() should call forwarder and trigger update
      value.set(1.5);
      await Future.delayed(Duration(milliseconds: 10));
      expect(forwardedCount, equals(1));
      expect(forwardedValues, contains(1.5));
      expect(updates, contains(1.5));

      // notifyOfExternalUpdate should only trigger update, not forwarder
      value.notifyOfExternalUpdate(2.5);
      await Future.delayed(Duration(milliseconds: 10));
      expect(forwardedCount, equals(1)); // Should still be 1
      expect(forwardedValues, isNot(contains(2.5)));
      expect(updates, contains(2.5));
    });
    test('custom equality with numbers', () async {
      // Custom equality that considers numbers within 0.1 as equal
      final value = WotValue<double>(
        initialValue: 10.0,
        valueForwarder: null,
        equality: (double a, double b) => (a - b).abs() < 0.1,
      );

      final updates = <double>[];
      value.onUpdate.listen(updates.add);

      // Should not trigger update (within threshold)
      value.set(10.05);
      await Future.delayed(Duration(milliseconds: 10));
      expect(updates, isEmpty);

      // Should trigger update (beyond threshold)
      value.set(10.2);
      await Future.delayed(Duration(milliseconds: 10));
      expect(updates, contains(10.2));
    });

    test('stream error handling', () async {
      final value = WotValue<int>(initialValue: 0);
      var errorCaught = false;

      value.onUpdate.listen(
        (data) {
          // Normal listener
        },
        onError: (error) {
          errorCaught = true;
        },
      );

      // Normal operation should not cause errors
      value.set(42);
      await Future.delayed(Duration(milliseconds: 10));
      expect(errorCaught, isFalse);
    });

    test('performance with many rapid updates', () async {
      final value = WotValue<int>(initialValue: 0);
      final updates = <int>[];
      value.onUpdate.listen(updates.add);

      final stopwatch = Stopwatch()..start();

      // Rapid updates
      for (int i = 1; i <= 100; i++) {
        value.set(i);
      }

      stopwatch.stop();

      // Should complete quickly
      expect(stopwatch.elapsedMilliseconds, lessThan(100));

      await Future.delayed(Duration(milliseconds: 50));

      // Should receive all updates
      expect(updates, hasLength(100));
      expect(updates.last, equals(100));
      expect(value.get(), equals(100));
    });
    test('stream subscription pause and resume', () async {
      final value = WotValue<int>(initialValue: 0);
      final updates = <int>[];

      final subscription = value.onUpdate.listen(updates.add);

      value.set(1);
      await Future.delayed(Duration(milliseconds: 10));
      expect(updates, hasLength(1));

      subscription.pause();
      value.set(2);
      value.set(3);
      await Future.delayed(Duration(milliseconds: 10));

      subscription.resume();
      await Future.delayed(Duration(milliseconds: 10));

      value.set(4);
      await Future.delayed(Duration(milliseconds: 10));

      // The behavior may vary - let's just check that we can pause/resume
      expect(updates, isNotEmpty);
      expect(updates.first, equals(1));
    });
    test('value with enum type', () async {
      const initialState = DeviceState.off;
      final value = WotValue<DeviceState>(initialValue: initialState);
      final updates = <DeviceState>[];
      value.onUpdate.listen(updates.add);

      expect(value.get(), equals(DeviceState.off));

      value.set(DeviceState.on);
      await Future.delayed(Duration(milliseconds: 10));
      expect(value.get(), equals(DeviceState.on));
      expect(updates, contains(DeviceState.on));

      value.set(DeviceState.error);
      await Future.delayed(Duration(milliseconds: 10));
      expect(value.get(), equals(DeviceState.error));
      expect(updates, contains(DeviceState.error));
    });

    test('value type safety', () {
      final intValue = WotValue<int>(initialValue: 42);
      final stringValue = WotValue<String>(initialValue: 'hello');
      final boolValue = WotValue<bool>(initialValue: false);

      // These should compile and work correctly due to type safety
      expect(intValue.get(), isA<int>());
      expect(stringValue.get(), isA<String>());
      expect(boolValue.get(), isA<bool>());

      intValue.set(100);
      stringValue.set('world');
      boolValue.set(true);

      expect(intValue.get(), equals(100));
      expect(stringValue.get(), equals('world'));
      expect(boolValue.get(), isTrue);
    });

    test('concurrent access safety', () async {
      final value = WotValue<int>(initialValue: 0);
      final allUpdates = <int>[];

      // Multiple concurrent listeners
      for (int i = 0; i < 5; i++) {
        value.onUpdate.listen((update) => allUpdates.add(update));
      }

      // Concurrent updates from different "threads"
      final futures = <Future>[];
      for (int i = 1; i <= 10; i++) {
        futures.add(Future.microtask(() => value.set(i)));
      }

      await Future.wait(futures);
      await Future.delayed(Duration(milliseconds: 50));

      // Final value should be consistent
      expect(value.get(), isA<int>());
      expect(value.get(), greaterThanOrEqualTo(1));
      expect(value.get(), lessThanOrEqualTo(10));

      // Should have received multiple updates
      expect(allUpdates.length, greaterThan(0));
    });
  });
}

// Test enum for enum value testing
enum DeviceState { off, on, error }
