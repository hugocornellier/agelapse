import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/stabilization_state.dart';

void main() {
  group('StabilizationState', () {
    test('has all expected values', () {
      expect(StabilizationState.values, hasLength(9));
      expect(
        StabilizationState.values,
        containsAll([
          StabilizationState.idle,
          StabilizationState.preparing,
          StabilizationState.stabilizing,
          StabilizationState.cancelling,
          StabilizationState.compilingVideo,
          StabilizationState.cancellingVideo,
          StabilizationState.completed,
          StabilizationState.cancelled,
          StabilizationState.error,
        ]),
      );
    });
  });

  group('StabilizationStateExtension', () {
    group('isActive', () {
      test('returns true for preparing', () {
        expect(StabilizationState.preparing.isActive, isTrue);
      });

      test('returns true for stabilizing', () {
        expect(StabilizationState.stabilizing.isActive, isTrue);
      });

      test('returns true for compilingVideo', () {
        expect(StabilizationState.compilingVideo.isActive, isTrue);
      });

      test('returns false for idle', () {
        expect(StabilizationState.idle.isActive, isFalse);
      });

      test('returns false for cancelling', () {
        expect(StabilizationState.cancelling.isActive, isFalse);
      });

      test('returns false for cancellingVideo', () {
        expect(StabilizationState.cancellingVideo.isActive, isFalse);
      });

      test('returns false for completed', () {
        expect(StabilizationState.completed.isActive, isFalse);
      });

      test('returns false for cancelled', () {
        expect(StabilizationState.cancelled.isActive, isFalse);
      });

      test('returns false for error', () {
        expect(StabilizationState.error.isActive, isFalse);
      });
    });

    group('isCancelling', () {
      test('returns true for cancelling', () {
        expect(StabilizationState.cancelling.isCancelling, isTrue);
      });

      test('returns true for cancellingVideo', () {
        expect(StabilizationState.cancellingVideo.isCancelling, isTrue);
      });

      test('returns false for idle', () {
        expect(StabilizationState.idle.isCancelling, isFalse);
      });

      test('returns false for preparing', () {
        expect(StabilizationState.preparing.isCancelling, isFalse);
      });

      test('returns false for stabilizing', () {
        expect(StabilizationState.stabilizing.isCancelling, isFalse);
      });

      test('returns false for compilingVideo', () {
        expect(StabilizationState.compilingVideo.isCancelling, isFalse);
      });

      test('returns false for completed', () {
        expect(StabilizationState.completed.isCancelling, isFalse);
      });

      test('returns false for cancelled', () {
        expect(StabilizationState.cancelled.isCancelling, isFalse);
      });

      test('returns false for error', () {
        expect(StabilizationState.error.isCancelling, isFalse);
      });
    });

    group('isFinished', () {
      test('returns true for idle', () {
        expect(StabilizationState.idle.isFinished, isTrue);
      });

      test('returns true for completed', () {
        expect(StabilizationState.completed.isFinished, isTrue);
      });

      test('returns true for cancelled', () {
        expect(StabilizationState.cancelled.isFinished, isTrue);
      });

      test('returns true for error', () {
        expect(StabilizationState.error.isFinished, isTrue);
      });

      test('returns false for preparing', () {
        expect(StabilizationState.preparing.isFinished, isFalse);
      });

      test('returns false for stabilizing', () {
        expect(StabilizationState.stabilizing.isFinished, isFalse);
      });

      test('returns false for cancelling', () {
        expect(StabilizationState.cancelling.isFinished, isFalse);
      });

      test('returns false for compilingVideo', () {
        expect(StabilizationState.compilingVideo.isFinished, isFalse);
      });

      test('returns false for cancellingVideo', () {
        expect(StabilizationState.cancellingVideo.isFinished, isFalse);
      });
    });

    group('isVideoPhase', () {
      test('returns true for compilingVideo', () {
        expect(StabilizationState.compilingVideo.isVideoPhase, isTrue);
      });

      test('returns true for cancellingVideo', () {
        expect(StabilizationState.cancellingVideo.isVideoPhase, isTrue);
      });

      test('returns false for idle', () {
        expect(StabilizationState.idle.isVideoPhase, isFalse);
      });

      test('returns false for preparing', () {
        expect(StabilizationState.preparing.isVideoPhase, isFalse);
      });

      test('returns false for stabilizing', () {
        expect(StabilizationState.stabilizing.isVideoPhase, isFalse);
      });

      test('returns false for cancelling', () {
        expect(StabilizationState.cancelling.isVideoPhase, isFalse);
      });

      test('returns false for completed', () {
        expect(StabilizationState.completed.isVideoPhase, isFalse);
      });

      test('returns false for cancelled', () {
        expect(StabilizationState.cancelled.isVideoPhase, isFalse);
      });

      test('returns false for error', () {
        expect(StabilizationState.error.isVideoPhase, isFalse);
      });
    });

    group('state categorization completeness', () {
      test('every state belongs to at least one category or is transitional',
          () {
        for (final state in StabilizationState.values) {
          final isInSomeCategory = state.isActive ||
              state.isCancelling ||
              state.isFinished ||
              state.isVideoPhase;
          // All states should be categorizable
          // Note: cancelling states are in isCancelling, not isActive
          expect(
            isInSomeCategory,
            isTrue,
            reason: 'State $state should be in at least one category',
          );
        }
      });
    });

    group('state flow scenarios', () {
      test(
          'normal flow: idle -> preparing -> stabilizing -> compilingVideo -> completed',
          () {
        final flow = [
          StabilizationState.idle,
          StabilizationState.preparing,
          StabilizationState.stabilizing,
          StabilizationState.compilingVideo,
          StabilizationState.completed,
        ];

        expect(flow[0].isFinished, isTrue); // Start at idle
        expect(flow[1].isActive, isTrue); // Preparing is active
        expect(flow[2].isActive, isTrue); // Stabilizing is active
        expect(flow[3].isActive, isTrue); // Compiling is active
        expect(flow[3].isVideoPhase, isTrue); // Compiling is video phase
        expect(flow[4].isFinished, isTrue); // End at completed
      });

      test('cancellation flow during stabilization', () {
        final flow = [
          StabilizationState.stabilizing,
          StabilizationState.cancelling,
          StabilizationState.cancelled,
        ];

        expect(flow[0].isActive, isTrue);
        expect(flow[1].isCancelling, isTrue);
        expect(flow[1].isActive, isFalse);
        expect(flow[2].isFinished, isTrue);
      });

      test('cancellation flow during video compilation', () {
        final flow = [
          StabilizationState.compilingVideo,
          StabilizationState.cancellingVideo,
          StabilizationState.cancelled,
        ];

        expect(flow[0].isVideoPhase, isTrue);
        expect(flow[1].isVideoPhase, isTrue);
        expect(flow[1].isCancelling, isTrue);
        expect(flow[2].isFinished, isTrue);
      });

      test('error flow', () {
        final state = StabilizationState.error;
        expect(state.isFinished, isTrue);
        expect(state.isActive, isFalse);
        expect(state.isCancelling, isFalse);
        expect(state.isVideoPhase, isFalse);
      });
    });
  });
}
