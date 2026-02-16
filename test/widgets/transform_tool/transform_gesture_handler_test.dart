import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/transform_tool/transform_gesture_handler.dart';
import 'package:agelapse/widgets/transform_tool/transform_state.dart';
import 'package:agelapse/widgets/transform_tool/transform_handle.dart';

/// Unit tests for TransformGestureHandler.
void main() {
  TransformState createState({
    double translateX = 0,
    double translateY = 0,
    double scale = 1.0,
    double rotation = 0,
  }) {
    return TransformState(
      translateX: translateX,
      translateY: translateY,
      scale: scale,
      rotation: rotation,
      pivot: const Offset(400, 300),
      imageSize: const Size(800, 600),
      canvasSize: const Size(800, 600),
    );
  }

  group('TransformGestureHandler.applyDrag', () {
    test('applies translation delta', () {
      final state = createState();
      final result = TransformGestureHandler.applyDrag(
        state,
        const Offset(10, 20),
      );
      expect(result.translateX, 10);
      expect(result.translateY, 20);
    });

    test('applies negative delta', () {
      final state = createState(translateX: 50, translateY: 50);
      final result = TransformGestureHandler.applyDrag(
        state,
        const Offset(-30, -20),
      );
      expect(result.translateX, 20);
      expect(result.translateY, 30);
    });

    test('applies zero delta', () {
      final state = createState(translateX: 10, translateY: 20);
      final result = TransformGestureHandler.applyDrag(
        state,
        Offset.zero,
      );
      expect(result.translateX, 10);
      expect(result.translateY, 20);
    });
  });

  group('TransformGestureHandler.applyScale', () {
    test('does not modify state for non-resize handles', () {
      final state = createState();
      final result = TransformGestureHandler.applyScale(
        state: state,
        handle: TransformHandle.body,
        startPosition: const Offset(100, 100),
        currentPosition: const Offset(200, 200),
        startState: state,
        maintainAspectRatio: true,
      );
      expect(result, equals(state));
    });

    test('scales from corner handle', () {
      final state = createState();
      final result = TransformGestureHandler.applyScale(
        state: state,
        handle: TransformHandle.topLeft,
        startPosition: const Offset(100, 100),
        currentPosition: const Offset(50, 50),
        startState: state,
        maintainAspectRatio: true,
      );
      expect(result.scale, isNot(equals(state.scale)));
    });
  });

  group('TransformGestureHandler.applyRotation', () {
    test('rotates around image center', () {
      final state = createState();
      final result = TransformGestureHandler.applyRotation(
        startState: state,
        startPosition: const Offset(400, 0),
        currentPosition: const Offset(800, 300),
      );
      expect(result.rotation, isNot(equals(0)));
    });

    test('snaps to 15-degree increments when enabled', () {
      final state = createState();
      final result = TransformGestureHandler.applyRotation(
        startState: state,
        startPosition: const Offset(400, 0),
        currentPosition: const Offset(500, 100),
        snapToAngles: true,
      );
      expect(result.rotation % 15, closeTo(0, 0.01));
    });
  });

  group('TransformGestureHandler.nudge', () {
    test('adds dx to translateX', () {
      final state = createState();
      final result = TransformGestureHandler.nudge(state, 5, 0);
      expect(result.translateX, 5);
    });

    test('adds dy to translateY', () {
      final state = createState();
      final result = TransformGestureHandler.nudge(state, 0, 10);
      expect(result.translateY, 10);
    });

    test('adds both dx and dy', () {
      final state = createState(translateX: 10, translateY: 20);
      final result = TransformGestureHandler.nudge(state, 5, 10);
      expect(result.translateX, 15);
      expect(result.translateY, 30);
    });
  });

  group('TransformGestureHandler.adjustRotation', () {
    test('adds rotation degrees', () {
      final state = createState();
      final result = TransformGestureHandler.adjustRotation(state, 45);
      expect(result.rotation, 45);
    });

    test('normalizes rotation to -180..180', () {
      final state = createState(rotation: 170);
      final result = TransformGestureHandler.adjustRotation(state, 20);
      expect(result.rotation, closeTo(-170, 0.01));
    });

    test('snaps when enabled', () {
      final state = createState();
      final result = TransformGestureHandler.adjustRotation(
        state,
        22,
        snapToAngles: true,
      );
      expect(result.rotation % 15, closeTo(0, 0.01));
    });
  });

  group('TransformGestureHandler.adjustScale', () {
    test('increases scale by percentage', () {
      final state = createState();
      final result = TransformGestureHandler.adjustScale(state, 50);
      expect(result.scale, closeTo(1.5, 0.01));
    });

    test('decreases scale by percentage', () {
      final state = createState(scale: 2.0);
      final result = TransformGestureHandler.adjustScale(state, -50);
      expect(result.scale, closeTo(1.0, 0.01));
    });

    test('clamps scale to minimum', () {
      final state = createState(scale: 0.2);
      final result = TransformGestureHandler.adjustScale(state, -90);
      expect(result.scale, greaterThanOrEqualTo(0.1));
    });

    test('clamps scale to maximum', () {
      final state = createState(scale: 9.0);
      final result = TransformGestureHandler.adjustScale(state, 50);
      expect(result.scale, lessThanOrEqualTo(10.0));
    });
  });

  group('TransformGestureHandler.reset', () {
    test('returns identity state', () {
      final state = createState(
        translateX: 50,
        translateY: 100,
        scale: 2.0,
        rotation: 45,
      );
      final result = TransformGestureHandler.reset(state);
      expect(result.translateX, 0);
      expect(result.translateY, 0);
      expect(result.rotation, 0);
    });

    test('preserves image and canvas size', () {
      final state = createState();
      final result = TransformGestureHandler.reset(state);
      expect(result.imageSize, state.imageSize);
      expect(result.canvasSize, state.canvasSize);
    });
  });

  group('TransformGestureHandler.fitToCanvas', () {
    test('returns identity state', () {
      final state = createState(
        translateX: 50,
        translateY: 100,
        scale: 2.0,
        rotation: 45,
      );
      final result = TransformGestureHandler.fitToCanvas(state);
      expect(result.translateX, 0);
      expect(result.translateY, 0);
      expect(result.rotation, 0);
    });
  });

  group('TransformGestureHandler coordinate transforms', () {
    test('canvasToImage returns a point', () {
      final state = createState();
      final result = TransformGestureHandler.canvasToImage(
        const Offset(400, 300),
        state,
      );
      expect(result, isA<Offset>());
    });

    test('imageToCanvas returns a point', () {
      final state = createState();
      final result = TransformGestureHandler.imageToCanvas(
        const Offset(400, 300),
        state,
      );
      expect(result, isA<Offset>());
    });

    test('canvasToImage and imageToCanvas are inverse', () {
      final state = createState();
      final original = const Offset(400, 300);
      final imagePoint = TransformGestureHandler.canvasToImage(original, state);
      final backToCanvas = TransformGestureHandler.imageToCanvas(
        imagePoint,
        state,
      );
      expect(backToCanvas.dx, closeTo(original.dx, 0.01));
      expect(backToCanvas.dy, closeTo(original.dy, 0.01));
    });
  });
}
