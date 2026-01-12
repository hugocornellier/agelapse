import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/cancellation_token.dart';

void main() {
  group('CancelledException', () {
    test('toString returns message when provided', () {
      const exception = CancelledException('Custom message');
      expect(exception.toString(), 'Custom message');
    });

    test('toString returns default message when no message provided', () {
      const exception = CancelledException();
      expect(exception.toString(), 'Operation was cancelled');
    });

    test('message property returns the message', () {
      const exception = CancelledException('Test');
      expect(exception.message, 'Test');
    });

    test('message property is null when not provided', () {
      const exception = CancelledException();
      expect(exception.message, isNull);
    });
  });

  group('CancellationToken', () {
    late CancellationToken token;

    setUp(() {
      token = CancellationToken();
    });

    group('initial state', () {
      test('isCancelled is false initially', () {
        expect(token.isCancelled, isFalse);
      });
    });

    group('cancel()', () {
      test('sets isCancelled to true', () {
        token.cancel();
        expect(token.isCancelled, isTrue);
      });

      test('calling cancel multiple times has no additional effect', () {
        token.cancel();
        token.cancel();
        token.cancel();
        expect(token.isCancelled, isTrue);
      });

      test('notifies all registered listeners', () {
        var listener1Called = false;
        var listener2Called = false;

        token.addListener(() => listener1Called = true);
        token.addListener(() => listener2Called = true);

        token.cancel();

        expect(listener1Called, isTrue);
        expect(listener2Called, isTrue);
      });

      test(
        'listeners are only called once even with multiple cancel calls',
        () {
          var callCount = 0;
          token.addListener(() => callCount++);

          token.cancel();
          token.cancel();

          expect(callCount, 1);
        },
      );

      test('ignores errors in listeners', () {
        token.addListener(() => throw Exception('Listener error'));
        token.addListener(() {}); // This should still be called

        // Should not throw
        expect(() => token.cancel(), returnsNormally);
        expect(token.isCancelled, isTrue);
      });
    });

    group('addListener()', () {
      test('adds listener that gets called on cancel', () {
        var called = false;
        token.addListener(() => called = true);

        expect(called, isFalse);
        token.cancel();
        expect(called, isTrue);
      });

      test('calls listener immediately if already cancelled', () {
        token.cancel();

        var called = false;
        token.addListener(() => called = true);

        expect(called, isTrue);
      });

      test('can add multiple listeners', () {
        final calls = <int>[];
        token.addListener(() => calls.add(1));
        token.addListener(() => calls.add(2));
        token.addListener(() => calls.add(3));

        token.cancel();

        expect(calls, [1, 2, 3]);
      });
    });

    group('removeListener()', () {
      test('removes listener so it is not called on cancel', () {
        var called = false;
        void listener() => called = true;

        token.addListener(listener);
        token.removeListener(listener);

        token.cancel();

        expect(called, isFalse);
      });

      test('only removes the specified listener', () {
        var called1 = false;
        var called2 = false;
        void listener1() => called1 = true;
        void listener2() => called2 = true;

        token.addListener(listener1);
        token.addListener(listener2);
        token.removeListener(listener1);

        token.cancel();

        expect(called1, isFalse);
        expect(called2, isTrue);
      });

      test('does nothing if listener was not added', () {
        // Should not throw
        expect(() => token.removeListener(() {}), returnsNormally);
      });
    });

    group('throwIfCancelled()', () {
      test('does not throw when not cancelled', () {
        expect(() => token.throwIfCancelled(), returnsNormally);
      });

      test('throws CancelledException when cancelled', () {
        token.cancel();
        expect(
          () => token.throwIfCancelled(),
          throwsA(isA<CancelledException>()),
        );
      });

      test('throws with custom message when provided', () {
        token.cancel();
        expect(
          () => token.throwIfCancelled('Custom cancel message'),
          throwsA(
            isA<CancelledException>().having(
              (e) => e.message,
              'message',
              'Custom cancel message',
            ),
          ),
        );
      });

      test('throws with default message when no message provided', () {
        token.cancel();
        try {
          token.throwIfCancelled();
          fail('Expected CancelledException');
        } on CancelledException catch (e) {
          expect(e.toString(), 'Operation was cancelled');
        }
      });
    });

    group('reset()', () {
      test('sets isCancelled back to false', () {
        token.cancel();
        expect(token.isCancelled, isTrue);

        token.reset();
        expect(token.isCancelled, isFalse);
      });

      test('allows cancel to work again after reset', () {
        token.cancel();
        token.reset();

        var called = false;
        token.addListener(() => called = true);

        token.cancel();
        expect(called, isTrue);
      });

      test('throwIfCancelled does not throw after reset', () {
        token.cancel();
        token.reset();
        expect(() => token.throwIfCancelled(), returnsNormally);
      });
    });

    group('integration scenarios', () {
      test('typical usage pattern works correctly', () async {
        final results = <String>[];
        var shouldCancel = false;

        Future<void> longRunningTask(CancellationToken token) async {
          for (var i = 0; i < 5; i++) {
            token.throwIfCancelled();
            results.add('Step $i');
            await Future.delayed(Duration.zero);
            if (shouldCancel) {
              token.cancel();
            }
          }
        }

        // Run without cancellation
        await longRunningTask(token);
        expect(results, ['Step 0', 'Step 1', 'Step 2', 'Step 3', 'Step 4']);

        // Run with cancellation
        results.clear();
        token.reset();
        shouldCancel = true;

        try {
          await longRunningTask(token);
          fail('Expected CancelledException');
        } on CancelledException {
          // Expected
        }

        expect(results, ['Step 0']); // Only first step completed
      });
    });
  });
}
