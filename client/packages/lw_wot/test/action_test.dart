import 'package:test/test.dart';
import 'package:lw_wot/action.dart';
import 'package:lw_wot/thing.dart';
import 'package:lw_wot/types.dart';

class TestAction extends WotAction<Map<String, dynamic>> {
  bool _performed = false;
  bool _cancelled = false;
  String? _errorMessage;

  TestAction({required super.id, required super.thing, required super.name, required super.input});

  bool get wasPerformed => _performed;
  bool get wasCancelled => _cancelled;
  String? get errorMessage => _errorMessage;

  @override
  Future<void> performAction() async {
    await Future.delayed(Duration(milliseconds: 10));
    if (input['shouldFail'] == true) {
      _errorMessage = 'Test error';
      throw Exception(_errorMessage);
    }
    _performed = true;
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    await Future.delayed(Duration(milliseconds: 5));
  }
}

void main() {
  group('WotAction', () {
    late WotThing thing;

    setUp(() {
      thing = WotThing(id: 'test-thing-id', title: 'Test Thing', type: ['TestDevice'], description: 'A test thing');
    });

    test('basic properties', () {
      final action = WotAction<String>(id: 'aid', thing: thing, name: 'aname', input: 'input');
      expect(action.id, equals('aid'));
      expect(action.name, equals('aname'));
      expect(action.status, equals('created'));
      expect(action.href, contains('aname'));
      expect(action.input, equals('input'));
      expect(action.thing, equals(thing));
      expect(action.timeRequested, isNotNull);
      expect(action.timeCompleted, isNull);
    });

    test('setHrefPrefix updates href correctly', () {
      final action = WotAction<String>(id: 'aid', thing: thing, name: 'aname', input: 'input');
      action.setHrefPrefix('/prefix');
      expect(action.hrefPrefix, equals('/prefix'));
      expect(action.href, equals('/prefix/actions/aname/aid'));
    });

    test('asActionDescription returns correct format', () {
      final action = WotAction<Map<String, dynamic>>(
        id: 'action-123',
        thing: thing,
        name: 'testAction',
        input: {'param': 'value'},
      );
      action.setHrefPrefix('/api/v1');

      final description = action.asActionDescription();

      expect(description, isA<Map<String, dynamic>>());
      expect(description['testAction'], isNotNull);
      expect(description['testAction']['href'], equals('/api/v1/actions/testAction/action-123'));
      expect(description['testAction']['status'], equals('created'));
      expect(description['testAction']['timeRequested'], isNotNull);
      expect(description['testAction']['input'], equals({'param': 'value'}));
      expect(description['testAction']['timeCompleted'], isNull);
    });

    test('asActionDescription with null input', () {
      final action = WotAction<String?>(id: 'action-null', thing: thing, name: 'nullAction', input: null);
      final description = action.asActionDescription();

      expect(description['nullAction']['input'], isNull);
    });

    test('finishWithError stores strong typed failure and keeps string error for compatibility', () {
      final action = WotAction<String>(id: 'error-action', thing: thing, name: 'errorAction', input: 'input');
      final stackTrace = StackTrace.current;

      action.finishWithError(StateError('broken state'), stackTrace);

      expect(action.status, equals('error'));
      expect(action.error, contains('broken state'));
      expect(action.failure, isNotNull);
      expect(action.failure!.kind, equals('StateError'));
      expect(action.failure!.message, contains('broken state'));
      expect(action.failure!.stackTrace, isNotNull);

      final description = action.asActionDescription();
      expect(description['errorAction']['error'], contains('broken state'));
      expect(description['errorAction']['failure']['kind'], equals('StateError'));
      expect(description['errorAction']['failure']['message'], contains('broken state'));
    });

    test('finish clears previous failure details', () {
      final action = WotAction<String>(id: 'clear-action', thing: thing, name: 'clearAction', input: 'input');

      action.finishWithError(Exception('first failure'));
      expect(action.failure, isNotNull);

      action.finish();

      expect(action.status, equals('completed'));
      expect(action.error, isNull);
      expect(action.failure, isNull);
    });

    test('action lifecycle - successful execution', () async {
      final action = TestAction(
        id: 'success-action',
        thing: thing,
        name: 'successAction',
        input: {'shouldFail': false},
      );

      expect(action.status, equals('created'));
      expect(action.wasPerformed, isFalse);

      action.start();
      expect(action.status, equals('pending'));

      // Wait for action to complete
      await Future.delayed(Duration(milliseconds: 50));

      expect(action.status, equals('completed'));
      expect(action.wasPerformed, isTrue);
      expect(action.timeCompleted, isNotNull);
    });

    test('action lifecycle - failed execution', () async {
      final action = TestAction(id: 'fail-action', thing: thing, name: 'failAction', input: {'shouldFail': true});

      action.start();
      expect(action.status, equals('pending'));

      // Wait for action to fail and finish
      await Future.delayed(Duration(milliseconds: 50));

      expect(action.status, equals('error'));
      expect(action.wasPerformed, isFalse);
      expect(action.error, contains('Test error'));
      expect(action.failure, isNotNull);
      expect(action.failure!.kind, contains('Exception'));
      expect(action.timeCompleted, isNotNull);
    });

    test('action cancellation', () async {
      final action = TestAction(id: 'cancel-action', thing: thing, name: 'cancelAction', input: {});

      await action.cancel();
      expect(action.wasCancelled, isTrue);
    });

    test('multiple actions with same name but different IDs', () {
      final action1 = WotAction<int>(id: 'id1', thing: thing, name: 'sameName', input: 42);
      final action2 = WotAction<int>(id: 'id2', thing: thing, name: 'sameName', input: 24);

      expect(action1.id, equals('id1'));
      expect(action2.id, equals('id2'));
      expect(action1.name, equals(action2.name));
      expect(action1.input, equals(42));
      expect(action2.input, equals(24));
    });

    test('action with complex input types', () {
      final complexInput = {
        'temperature': 25.5,
        'enabled': true,
        'schedule': [
          {'time': '08:00', 'action': 'on'},
          {'time': '22:00', 'action': 'off'},
        ],
        'metadata': {'user': 'test-user', 'priority': 'high'},
      };

      final action = WotAction<Map<String, dynamic>>(
        id: 'complex-action',
        thing: thing,
        name: 'complexAction',
        input: complexInput,
      );

      expect(action.input, equals(complexInput));

      final description = action.asActionDescription();
      expect(description['complexAction']['input'], equals(complexInput));
    });

    test('action status progression', () {
      final action = WotAction<String>(id: 'status-test', thing: thing, name: 'statusTest', input: 'test');

      // Initial state
      expect(action.status, equals('created'));

      // Manual status changes
      action.start();
      expect(action.status, equals('pending'));

      action.finish();
      expect(action.status, equals('completed'));
      expect(action.timeCompleted, isNotNull);
    });
  });

  group('WotActionMetadata', () {
    test('creates metadata with all properties', () {
      final metadata = WotActionMetadata(
        type: 'action',
        atType: 'ToggleAction',
        title: 'Toggle Device',
        description: 'Toggles the device state',
        input: {
          'type': 'object',
          'properties': {
            'enable': {'type': 'boolean'},
          },
        },
        output: {
          'type': 'object',
          'properties': {
            'success': {'type': 'boolean'},
          },
        },
        links: [WotLink(rel: 'action', href: '/toggle')],
      );

      expect(metadata.type, equals('action'));
      expect(metadata.atType, equals('ToggleAction'));
      expect(metadata.title, equals('Toggle Device'));
      expect(metadata.description, equals('Toggles the device state'));
      expect(metadata.input, isNotNull);
      expect(metadata.output, isNotNull);
      expect(metadata.links, hasLength(1));
    });

    test('creates metadata with minimal properties', () {
      final metadata = WotActionMetadata();

      expect(metadata.type, isNull);
      expect(metadata.atType, isNull);
      expect(metadata.title, isNull);
      expect(metadata.description, isNull);
      expect(metadata.input, isNull);
      expect(metadata.output, isNull);
      expect(metadata.links, isNull);
    });
  });
}
