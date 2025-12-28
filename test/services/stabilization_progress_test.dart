import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/stabilization_progress.dart';
import 'package:agelapse/services/stabilization_state.dart';

void main() {
  group('StabilizationProgress', () {
    group('constructor', () {
      test('creates instance with required state', () {
        const progress = StabilizationProgress(
          state: StabilizationState.idle,
        );

        expect(progress.state, StabilizationState.idle);
        expect(progress.currentPhoto, 0);
        expect(progress.totalPhotos, 0);
        expect(progress.progressPercent, 0);
        expect(progress.eta, isNull);
        expect(progress.errorMessage, isNull);
        expect(progress.currentFrame, isNull);
        expect(progress.totalFrames, isNull);
        expect(progress.projectId, isNull);
      });

      test('creates instance with all parameters', () {
        const progress = StabilizationProgress(
          state: StabilizationState.stabilizing,
          currentPhoto: 5,
          totalPhotos: 10,
          progressPercent: 50,
          eta: '2m 30s',
          errorMessage: 'test error',
          currentFrame: 100,
          totalFrames: 200,
          projectId: 42,
        );

        expect(progress.state, StabilizationState.stabilizing);
        expect(progress.currentPhoto, 5);
        expect(progress.totalPhotos, 10);
        expect(progress.progressPercent, 50);
        expect(progress.eta, '2m 30s');
        expect(progress.errorMessage, 'test error');
        expect(progress.currentFrame, 100);
        expect(progress.totalFrames, 200);
        expect(progress.projectId, 42);
      });
    });

    group('factory constructors', () {
      test('idle() creates idle state', () {
        final progress = StabilizationProgress.idle();

        expect(progress.state, StabilizationState.idle);
        expect(progress.currentPhoto, 0);
        expect(progress.totalPhotos, 0);
        expect(progress.progressPercent, 0);
      });

      test('preparing() creates preparing state', () {
        final progress = StabilizationProgress.preparing(projectId: 1);

        expect(progress.state, StabilizationState.preparing);
        expect(progress.projectId, 1);
      });

      test('preparing() works without projectId', () {
        final progress = StabilizationProgress.preparing();

        expect(progress.state, StabilizationState.preparing);
        expect(progress.projectId, isNull);
      });

      test('stabilizing() creates stabilizing state with all parameters', () {
        final progress = StabilizationProgress.stabilizing(
          currentPhoto: 3,
          totalPhotos: 10,
          progressPercent: 30,
          eta: '5m 0s',
          projectId: 2,
        );

        expect(progress.state, StabilizationState.stabilizing);
        expect(progress.currentPhoto, 3);
        expect(progress.totalPhotos, 10);
        expect(progress.progressPercent, 30);
        expect(progress.eta, '5m 0s');
        expect(progress.projectId, 2);
      });

      test('cancelling() creates cancelling state', () {
        final progress = StabilizationProgress.cancelling(projectId: 3);

        expect(progress.state, StabilizationState.cancelling);
        expect(progress.projectId, 3);
      });

      test('compilingVideo() creates video compilation state', () {
        final progress = StabilizationProgress.compilingVideo(
          currentFrame: 50,
          totalFrames: 100,
          progressPercent: 50,
          projectId: 4,
        );

        expect(progress.state, StabilizationState.compilingVideo);
        expect(progress.currentFrame, 50);
        expect(progress.totalFrames, 100);
        expect(progress.progressPercent, 50);
        expect(progress.projectId, 4);
      });

      test('cancellingVideo() creates video cancelling state', () {
        final progress = StabilizationProgress.cancellingVideo(projectId: 5);

        expect(progress.state, StabilizationState.cancellingVideo);
        expect(progress.projectId, 5);
      });

      test('completed() creates completed state', () {
        final progress = StabilizationProgress.completed(projectId: 6);

        expect(progress.state, StabilizationState.completed);
        expect(progress.projectId, 6);
      });

      test('cancelled() creates cancelled state', () {
        final progress = StabilizationProgress.cancelled(projectId: 7);

        expect(progress.state, StabilizationState.cancelled);
        expect(progress.projectId, 7);
      });

      test('error() creates error state with message', () {
        final progress = StabilizationProgress.error(
          'Something went wrong',
          projectId: 8,
        );

        expect(progress.state, StabilizationState.error);
        expect(progress.errorMessage, 'Something went wrong');
        expect(progress.projectId, 8);
      });
    });

    group('copyWith()', () {
      test('creates copy with no changes when no parameters provided', () {
        final original = StabilizationProgress.stabilizing(
          currentPhoto: 5,
          totalPhotos: 10,
          progressPercent: 50,
          eta: '1m',
          projectId: 1,
        );

        final copy = original.copyWith();

        expect(copy, equals(original));
        expect(copy.state, original.state);
        expect(copy.currentPhoto, original.currentPhoto);
        expect(copy.totalPhotos, original.totalPhotos);
        expect(copy.progressPercent, original.progressPercent);
        expect(copy.eta, original.eta);
        expect(copy.projectId, original.projectId);
      });

      test('creates copy with updated state', () {
        final original = StabilizationProgress.stabilizing(
          currentPhoto: 5,
          totalPhotos: 10,
          progressPercent: 50,
        );

        final copy = original.copyWith(state: StabilizationState.completed);

        expect(copy.state, StabilizationState.completed);
        expect(copy.currentPhoto, 5); // Unchanged
        expect(copy.totalPhotos, 10); // Unchanged
      });

      test('creates copy with updated progress', () {
        final original = StabilizationProgress.stabilizing(
          currentPhoto: 5,
          totalPhotos: 10,
          progressPercent: 50,
        );

        final copy = original.copyWith(
          currentPhoto: 6,
          progressPercent: 60,
        );

        expect(copy.currentPhoto, 6);
        expect(copy.progressPercent, 60);
        expect(copy.totalPhotos, 10); // Unchanged
        expect(copy.state, StabilizationState.stabilizing); // Unchanged
      });

      test('can update all fields', () {
        final original = StabilizationProgress.idle();

        final copy = original.copyWith(
          state: StabilizationState.stabilizing,
          currentPhoto: 1,
          totalPhotos: 5,
          progressPercent: 20,
          eta: '30s',
          errorMessage: 'warning',
          currentFrame: 10,
          totalFrames: 50,
          projectId: 99,
        );

        expect(copy.state, StabilizationState.stabilizing);
        expect(copy.currentPhoto, 1);
        expect(copy.totalPhotos, 5);
        expect(copy.progressPercent, 20);
        expect(copy.eta, '30s');
        expect(copy.errorMessage, 'warning');
        expect(copy.currentFrame, 10);
        expect(copy.totalFrames, 50);
        expect(copy.projectId, 99);
      });
    });

    group('equality', () {
      test('two identical instances are equal', () {
        final a = StabilizationProgress.stabilizing(
          currentPhoto: 5,
          totalPhotos: 10,
          progressPercent: 50,
          eta: '1m',
          projectId: 1,
        );
        final b = StabilizationProgress.stabilizing(
          currentPhoto: 5,
          totalPhotos: 10,
          progressPercent: 50,
          eta: '1m',
          projectId: 1,
        );

        expect(a, equals(b));
        expect(a == b, isTrue);
      });

      test('instances with different states are not equal', () {
        final a = StabilizationProgress.idle();
        final b = StabilizationProgress.preparing();

        expect(a, isNot(equals(b)));
      });

      test('instances with different currentPhoto are not equal', () {
        final a = StabilizationProgress.stabilizing(
          currentPhoto: 1,
          totalPhotos: 10,
          progressPercent: 10,
        );
        final b = StabilizationProgress.stabilizing(
          currentPhoto: 2,
          totalPhotos: 10,
          progressPercent: 10,
        );

        expect(a, isNot(equals(b)));
      });

      test('instances with different projectId are not equal', () {
        final a = StabilizationProgress.completed(projectId: 1);
        final b = StabilizationProgress.completed(projectId: 2);

        expect(a, isNot(equals(b)));
      });

      test('identical returns true for same instance', () {
        final a = StabilizationProgress.idle();
        expect(identical(a, a), isTrue);
      });

      test('equality with non-StabilizationProgress returns false', () {
        final a = StabilizationProgress.idle();
        // ignore: unrelated_type_equality_checks
        expect(a == 'not a progress', isFalse);
        // ignore: unrelated_type_equality_checks
        expect(a == 42, isFalse);
      });
    });

    group('hashCode', () {
      test('equal instances have same hashCode', () {
        final a = StabilizationProgress.stabilizing(
          currentPhoto: 5,
          totalPhotos: 10,
          progressPercent: 50,
        );
        final b = StabilizationProgress.stabilizing(
          currentPhoto: 5,
          totalPhotos: 10,
          progressPercent: 50,
        );

        expect(a.hashCode, equals(b.hashCode));
      });

      test('different instances typically have different hashCodes', () {
        final a = StabilizationProgress.idle();
        final b = StabilizationProgress.preparing();

        // Note: hashCode collisions are possible but unlikely
        expect(a.hashCode, isNot(equals(b.hashCode)));
      });
    });

    group('toString()', () {
      test('includes state', () {
        final progress = StabilizationProgress.stabilizing(
          currentPhoto: 5,
          totalPhotos: 10,
          progressPercent: 50,
        );

        expect(progress.toString(),
            contains('state: StabilizationState.stabilizing'));
      });

      test('includes photo progress', () {
        final progress = StabilizationProgress.stabilizing(
          currentPhoto: 5,
          totalPhotos: 10,
          progressPercent: 50,
        );

        expect(progress.toString(), contains('photo: 5/10'));
      });

      test('includes percentage', () {
        final progress = StabilizationProgress.stabilizing(
          currentPhoto: 5,
          totalPhotos: 10,
          progressPercent: 50,
        );

        expect(progress.toString(), contains('progress: 50%'));
      });

      test('includes eta when present', () {
        final progress = StabilizationProgress.stabilizing(
          currentPhoto: 5,
          totalPhotos: 10,
          progressPercent: 50,
          eta: '2m 30s',
        );

        expect(progress.toString(), contains('eta: 2m 30s'));
      });

      test('includes frame info when present', () {
        final progress = StabilizationProgress.compilingVideo(
          currentFrame: 100,
          totalFrames: 200,
          progressPercent: 50,
        );

        expect(progress.toString(), contains('frame: 100/200'));
      });
    });

    group('state extension integration', () {
      test('idle progress state is finished', () {
        final progress = StabilizationProgress.idle();
        expect(progress.state.isFinished, isTrue);
        expect(progress.state.isActive, isFalse);
      });

      test('stabilizing progress state is active', () {
        final progress = StabilizationProgress.stabilizing(
          currentPhoto: 1,
          totalPhotos: 10,
          progressPercent: 10,
        );
        expect(progress.state.isActive, isTrue);
        expect(progress.state.isFinished, isFalse);
      });

      test('compilingVideo progress state is video phase', () {
        final progress = StabilizationProgress.compilingVideo(
          currentFrame: 1,
          totalFrames: 100,
          progressPercent: 1,
        );
        expect(progress.state.isVideoPhase, isTrue);
        expect(progress.state.isActive, isTrue);
      });

      test('cancelling progress state is cancelling', () {
        final progress = StabilizationProgress.cancelling();
        expect(progress.state.isCancelling, isTrue);
        expect(progress.state.isActive, isFalse);
      });

      test('error progress state is finished', () {
        final progress = StabilizationProgress.error('test error');
        expect(progress.state.isFinished, isTrue);
        expect(progress.state.isActive, isFalse);
      });
    });
  });
}
