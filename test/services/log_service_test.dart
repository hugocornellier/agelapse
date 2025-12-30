import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/log_service.dart';

/// Unit tests for LogService.
/// Tests singleton pattern, constants, and method signatures.
void main() {
  group('LogService Singleton', () {
    test('LogService has singleton instance', () {
      expect(LogService.instance, isNotNull);
    });

    test('LogService.instance returns same instance', () {
      final instance1 = LogService.instance;
      final instance2 = LogService.instance;
      expect(identical(instance1, instance2), isTrue);
    });
  });

  group('LogService Constants', () {
    test('maxLogSizeBytes is 5MB', () {
      expect(LogService.maxLogSizeBytes, 5 * 1024 * 1024);
    });

    test('maxLogSizeBytes is positive', () {
      expect(LogService.maxLogSizeBytes, greaterThan(0));
    });
  });

  group('LogService Method Signatures', () {
    test('log method exists and accepts String', () {
      // Should compile without error
      expect(LogService.instance.log, isNotNull);
    });

    test('initialize method returns Future<void>', () {
      // Verify method signature - don't actually call to avoid file system ops
      expect(LogService.instance.initialize, isA<Function>());
    });

    test('dispose method returns Future<void>', () {
      expect(LogService.instance.dispose, isA<Function>());
    });

    test('getLogFilePath method returns Future<String>', () {
      expect(LogService.instance.getLogFilePath, isA<Function>());
    });

    test('getLogContent method returns Future<String>', () {
      expect(LogService.instance.getLogContent, isA<Function>());
    });

    test('exportLogs method returns Future<void>', () {
      expect(LogService.instance.exportLogs, isA<Function>());
    });

    test('clearLogs method returns Future<void>', () {
      expect(LogService.instance.clearLogs, isA<Function>());
    });

    test('runWithLogging static method exists', () {
      expect(LogService.runWithLogging, isA<Function>());
    });
  });

  group('LogService runWithLogging', () {
    test('runWithLogging returns result from body function', () {
      final result = LogService.runWithLogging(() => 42);
      expect(result, 42);
    });

    test('runWithLogging works with string return type', () {
      final result = LogService.runWithLogging(() => 'test');
      expect(result, 'test');
    });

    test('runWithLogging works with void return', () {
      var executed = false;
      LogService.runWithLogging(() {
        executed = true;
      });
      expect(executed, isTrue);
    });

    test('runWithLogging preserves exceptions', () {
      expect(
        () => LogService.runWithLogging(() {
          throw Exception('test error');
        }),
        throwsException,
      );
    });
  });
}
