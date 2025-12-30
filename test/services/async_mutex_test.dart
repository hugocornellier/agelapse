import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/async_mutex.dart';

/// Unit tests for AsyncMutex.
/// Tests locking behavior, acquire/release, and protect method.
void main() {
  group('AsyncMutex Construction', () {
    test('AsyncMutex can be instantiated', () {
      final mutex = AsyncMutex();
      expect(mutex, isNotNull);
      expect(mutex, isA<AsyncMutex>());
    });

    test('newly created mutex is not locked', () {
      final mutex = AsyncMutex();
      expect(mutex.isLocked, isFalse);
    });
  });

  group('AsyncMutex isLocked Property', () {
    test('isLocked is false initially', () {
      final mutex = AsyncMutex();
      expect(mutex.isLocked, isFalse);
    });

    test('isLocked is true after acquire', () async {
      final mutex = AsyncMutex();
      await mutex.acquire();
      expect(mutex.isLocked, isTrue);
    });

    test('isLocked is false after acquire and release', () async {
      final mutex = AsyncMutex();
      await mutex.acquire();
      mutex.release();
      expect(mutex.isLocked, isFalse);
    });
  });

  group('AsyncMutex acquire/release', () {
    test('acquire completes immediately when unlocked', () async {
      final mutex = AsyncMutex();
      // Should complete without hanging
      await mutex.acquire();
      expect(mutex.isLocked, isTrue);
      mutex.release();
    });

    test('release when not locked does not throw', () {
      final mutex = AsyncMutex();
      // Should not throw
      expect(() => mutex.release(), returnsNormally);
    });

    test('multiple releases do not throw', () async {
      final mutex = AsyncMutex();
      await mutex.acquire();
      mutex.release();
      // Additional releases should not throw
      expect(() => mutex.release(), returnsNormally);
      expect(() => mutex.release(), returnsNormally);
    });

    test('sequential acquire/release works correctly', () async {
      final mutex = AsyncMutex();

      await mutex.acquire();
      expect(mutex.isLocked, isTrue);
      mutex.release();
      expect(mutex.isLocked, isFalse);

      await mutex.acquire();
      expect(mutex.isLocked, isTrue);
      mutex.release();
      expect(mutex.isLocked, isFalse);
    });
  });

  group('AsyncMutex protect', () {
    test('protect executes function and returns result', () async {
      final mutex = AsyncMutex();
      final result = await mutex.protect(() async => 42);
      expect(result, 42);
    });

    test('protect releases lock after successful execution', () async {
      final mutex = AsyncMutex();
      await mutex.protect(() async => 'test');
      expect(mutex.isLocked, isFalse);
    });

    test('protect releases lock after exception', () async {
      final mutex = AsyncMutex();

      try {
        await mutex.protect(() async {
          throw Exception('test error');
        });
      } catch (_) {
        // Expected
      }

      expect(mutex.isLocked, isFalse);
    });

    test('protect propagates exceptions', () async {
      final mutex = AsyncMutex();

      expect(
        () => mutex.protect(() async {
          throw Exception('test error');
        }),
        throwsException,
      );
    });

    test('protect works with different return types', () async {
      final mutex = AsyncMutex();

      final intResult = await mutex.protect(() async => 123);
      expect(intResult, isA<int>());

      final stringResult = await mutex.protect(() async => 'hello');
      expect(stringResult, isA<String>());

      final listResult = await mutex.protect(() async => [1, 2, 3]);
      expect(listResult, isA<List<int>>());

      final mapResult = await mutex.protect(() async => {'key': 'value'});
      expect(mapResult, isA<Map<String, String>>());
    });

    test('protect with void function', () async {
      final mutex = AsyncMutex();
      var executed = false;

      await mutex.protect(() async {
        executed = true;
      });

      expect(executed, isTrue);
      expect(mutex.isLocked, isFalse);
    });
  });

  group('AsyncMutex Serialization', () {
    test('second acquire waits for first release', () async {
      final mutex = AsyncMutex();
      final executionOrder = <int>[];

      await mutex.acquire();
      executionOrder.add(1);

      // Start second acquire (will wait)
      final secondAcquire = mutex.acquire().then((_) {
        executionOrder.add(3);
      });

      // Give time for second acquire to start waiting
      await Future.delayed(Duration(milliseconds: 10));
      executionOrder.add(2);
      mutex.release();

      await secondAcquire;
      mutex.release();

      expect(executionOrder, [1, 2, 3]);
    });

    test('protect serializes concurrent calls', () async {
      final mutex = AsyncMutex();
      final results = <int>[];

      final futures = [
        mutex.protect(() async {
          await Future.delayed(Duration(milliseconds: 20));
          results.add(1);
          return 1;
        }),
        mutex.protect(() async {
          results.add(2);
          return 2;
        }),
        mutex.protect(() async {
          results.add(3);
          return 3;
        }),
      ];

      await Future.wait(futures);

      // Results should be in order due to serialization
      expect(results, [1, 2, 3]);
    });
  });

  group('AsyncMutex Edge Cases', () {
    test('immediate release without acquire is safe', () {
      final mutex = AsyncMutex();
      expect(() => mutex.release(), returnsNormally);
      expect(mutex.isLocked, isFalse);
    });

    test('multiple sequential protects work correctly', () async {
      final mutex = AsyncMutex();

      for (int i = 0; i < 10; i++) {
        final result = await mutex.protect(() async => i);
        expect(result, i);
        expect(mutex.isLocked, isFalse);
      }
    });
  });
}
