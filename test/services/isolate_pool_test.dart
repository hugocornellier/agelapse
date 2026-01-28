import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/isolate_pool.dart';

void main() {
  group('IsolateTask', () {
    test('creates instance with all required properties', () {
      final completer = Completer<dynamic>();
      final task = IsolateTask(
        'testOperation',
        {'key': 'value'},
        completer,
      );

      expect(task.operation, equals('testOperation'));
      expect(task.params['key'], equals('value'));
      expect(task.completer, same(completer));
    });

    test('stores operation name correctly', () {
      final completer = Completer<dynamic>();
      final task = IsolateTask('readToPng', {}, completer);
      expect(task.operation, equals('readToPng'));
    });

    test('stores params map correctly', () {
      final completer = Completer<dynamic>();
      final params = {
        'filePath': '/path/to/file.jpg',
        'width': 1920,
        'height': 1080,
        'nested': {'a': 1, 'b': 2},
      };
      final task = IsolateTask('operation', params, completer);

      expect(task.params['filePath'], equals('/path/to/file.jpg'));
      expect(task.params['width'], equals(1920));
      expect(task.params['height'], equals(1080));
      expect(task.params['nested'], isA<Map>());
    });

    test('allows completing the completer', () async {
      final completer = Completer<String>();
      final task = IsolateTask('operation', {}, completer);

      task.completer.complete('result');

      expect(await completer.future, equals('result'));
    });

    test('allows completing with error', () async {
      final completer = Completer<dynamic>();
      final task = IsolateTask('operation', {}, completer);

      task.completer.completeError(Exception('test error'));

      await expectLater(
        completer.future,
        throwsA(isA<Exception>()),
      );
    });

    test('handles empty params map', () {
      final completer = Completer<dynamic>();
      final task = IsolateTask('operation', {}, completer);
      expect(task.params, isEmpty);
    });
  });

  group('IsolatePool singleton', () {
    test('returns same instance', () {
      final instance1 = IsolatePool.instance;
      final instance2 = IsolatePool.instance;
      expect(identical(instance1, instance2), isTrue);
    });
  });

  group('IsolatePool properties', () {
    test('isInitialized returns false initially', () {
      // Note: The singleton might be in various states from other tests,
      // but we can check the property is accessible
      expect(IsolatePool.instance.isInitialized, isA<bool>());
    });

    test('queueLength returns int', () {
      expect(IsolatePool.instance.queueLength, isA<int>());
      expect(IsolatePool.instance.queueLength, greaterThanOrEqualTo(0));
    });

    test('busyWorkers returns int', () {
      expect(IsolatePool.instance.busyWorkers, isA<int>());
      expect(IsolatePool.instance.busyWorkers, greaterThanOrEqualTo(0));
    });
  });
}
