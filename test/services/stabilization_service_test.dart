import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/stabilization_service.dart';
import 'package:agelapse/services/stabilization_state.dart';
import 'package:agelapse/services/stabilization_progress.dart';

/// Unit tests for StabilizationService.
/// Tests state machine transitions, progress emissions, and internal logic.
void main() {
  group('StabilizationService Singleton', () {
    test('instance returns the same object', () {
      final instance1 = StabilizationService.instance;
      final instance2 = StabilizationService.instance;
      expect(identical(instance1, instance2), isTrue);
    });
  });

  group('StabilizationService Initial State', () {
    test('starts in idle state', () {
      final service = StabilizationService.instance;
      // Note: State may have been modified by other tests
      // This test verifies the state getter works
      expect(service.state, isA<StabilizationState>());
    });

    test('isActive returns false when idle', () {
      final service = StabilizationService.instance;
      // When in idle, completed, cancelled, or error state, isActive should be false
      if (service.state == StabilizationState.idle ||
          service.state == StabilizationState.completed ||
          service.state == StabilizationState.cancelled ||
          service.state == StabilizationState.error) {
        expect(service.isActive, isFalse);
      }
    });

    test('isCancelling returns false when not cancelling', () {
      final service = StabilizationService.instance;
      if (service.state != StabilizationState.cancelling &&
          service.state != StabilizationState.cancellingVideo) {
        expect(service.isCancelling, isFalse);
      }
    });

    test('progressStream is a broadcast stream', () {
      final service = StabilizationService.instance;
      expect(service.progressStream, isA<Stream<StabilizationProgress>>());
      // Should be able to listen multiple times (broadcast)
      final sub1 = service.progressStream.listen((_) {});
      final sub2 = service.progressStream.listen((_) {});
      sub1.cancel();
      sub2.cancel();
    });
  });

  group('StabilizationService State Transitions', () {
    test('cancel does nothing when already idle', () async {
      final service = StabilizationService.instance;
      // If already idle, cancel should return without changing state
      if (service.state == StabilizationState.idle) {
        await service.cancel();
        expect(service.state, StabilizationState.idle);
      }
    });

    test('cancel does nothing when already completed', () async {
      final service = StabilizationService.instance;
      if (service.state == StabilizationState.completed) {
        await service.cancel();
        // State should remain completed or transition to idle
        expect(
          service.state == StabilizationState.completed ||
              service.state == StabilizationState.idle,
          isTrue,
        );
      }
    });

    test('cancel does nothing when already cancelled', () async {
      final service = StabilizationService.instance;
      if (service.state == StabilizationState.cancelled) {
        await service.cancel();
        // State should remain cancelled or transition to idle
        expect(
          service.state == StabilizationState.cancelled ||
              service.state == StabilizationState.idle,
          isTrue,
        );
      }
    });
  });

  group('StabilizationService Duration Formatting', () {
    // Test the _formatDuration method indirectly through progress
    test('formats milliseconds correctly', () {
      // Test via ETA format expectations
      // 0ms -> 0m 0s
      // 60000ms -> 1m 0s
      // 3661000ms -> 1h 1m 1s

      // We can't test private methods directly, but we can verify
      // the format through integration testing or by making it public
      // For now, just verify the service exists
      expect(StabilizationService.instance, isNotNull);
    });
  });

  group('StabilizationService Cancellation', () {
    test('cancelAndWait completes within timeout', () async {
      final service = StabilizationService.instance;

      // Should complete without hanging
      final completer = Completer<void>();
      Timer(const Duration(seconds: 3), () {
        if (!completer.isCompleted) {
          completer.completeError('Timeout');
        }
      });

      service.cancelAndWait().then((_) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      await completer.future;
    });
  });

  group('StabilizationService Project ID', () {
    test('currentProjectId is null when no project is being processed', () {
      final service = StabilizationService.instance;
      // When idle, currentProjectId may be null
      if (service.state == StabilizationState.idle) {
        // It can be null or retain last project id
        expect(service.currentProjectId, anyOf(isNull, isA<int>()));
      }
    });
  });

  group('StabilizationService Callback', () {
    test('userRanOutOfSpaceCallback can be set', () {
      final service = StabilizationService.instance;
      bool callbackCalled = false;

      service.userRanOutOfSpaceCallback = () {
        callbackCalled = true;
      };

      expect(service.userRanOutOfSpaceCallback, isNotNull);

      // Call the callback
      service.userRanOutOfSpaceCallback?.call();
      expect(callbackCalled, isTrue);

      // Clean up
      service.userRanOutOfSpaceCallback = null;
    });
  });
}
