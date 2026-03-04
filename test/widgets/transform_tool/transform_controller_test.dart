import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/transform_tool/transform_controller.dart';
import 'package:agelapse/widgets/transform_tool/transform_state.dart';
import 'package:agelapse/widgets/transform_tool/transform_handle.dart';

/// Unit tests for TransformController.
void main() {
  TransformController createController({
    double translateX = 0,
    double translateY = 0,
    double scale = 1.0,
    double rotation = 0,
  }) {
    final state = TransformState(
      translateX: translateX,
      translateY: translateY,
      scale: scale,
      rotation: rotation,
      pivot: const Offset(400, 300),
      imageSize: const Size(800, 600),
      canvasSize: const Size(800, 600),
    );
    return TransformController(initialState: state, baseScale: 1.0);
  }

  group('TransformController Construction', () {
    test('can be instantiated', () {
      final controller = createController();
      expect(controller, isNotNull);
      expect(controller, isA<TransformController>());
      controller.dispose();
    });

    test('starts with no active gesture', () {
      final controller = createController();
      expect(controller.isGestureActive, isFalse);
      expect(controller.activeHandle, TransformHandle.none);
      controller.dispose();
    });

    test('stores initial state', () {
      final controller = createController(translateX: 10, translateY: 20);
      expect(controller.state.translateX, 10);
      expect(controller.state.translateY, 20);
      controller.dispose();
    });

    test('effectiveScaleFactor includes baseScale', () {
      final state = TransformState(
        translateX: 0,
        translateY: 0,
        scale: 2.0,
        rotation: 0,
        pivot: const Offset(400, 300),
        imageSize: const Size(800, 600),
        canvasSize: const Size(800, 600),
      );
      final controller = TransformController(
        initialState: state,
        baseScale: 0.5,
      );
      expect(controller.effectiveScaleFactor, 1.0); // 2.0 * 0.5
      controller.dispose();
    });
  });

  group('TransformController.fromDatabaseValues', () {
    test('creates controller from database values', () {
      final controller = TransformController.fromDatabaseValues(
        translateX: 10,
        translateY: 20,
        scaleFactor: 1.0,
        rotationDegrees: 45,
        imageSize: const Size(800, 600),
        canvasSize: const Size(800, 600),
        baseScale: 1.0,
      );
      expect(controller.state.translateX, 10);
      expect(controller.state.translateY, 20);
      expect(controller.state.rotation, 45);
      controller.dispose();
    });
  });

  group('TransformController Direct Value Setters', () {
    test('setTranslation updates position', () {
      final controller = createController();
      controller.setTranslation(50, 100);
      expect(controller.state.translateX, 50);
      expect(controller.state.translateY, 100);
      controller.dispose();
    });

    test('setScale updates scale', () {
      final controller = createController();
      controller.setScale(2.0);
      expect(controller.state.scale, 2.0);
      controller.dispose();
    });

    test('setScale clamps to valid range', () {
      final controller = createController();
      controller.setScale(0.01);
      expect(controller.state.scale, 0.1);
      controller.setScale(20.0);
      expect(controller.state.scale, 10.0);
      controller.dispose();
    });

    test('setRotation normalizes degrees', () {
      final controller = createController();
      controller.setRotation(270);
      expect(controller.state.rotation, -90);
      controller.dispose();
    });

    test('setRotation normalizes negative degrees', () {
      final controller = createController();
      controller.setRotation(-270);
      expect(controller.state.rotation, 90);
      controller.dispose();
    });

    test('setTransform updates multiple values', () {
      final controller = createController();
      controller.setTransform(translateX: 10, translateY: 20, scale: 1.5);
      expect(controller.state.translateX, 10);
      expect(controller.state.translateY, 20);
      expect(controller.state.scale, 1.5);
      controller.dispose();
    });
  });

  group('TransformController Keyboard Shortcuts', () {
    test('nudge adjusts position', () {
      final controller = createController();
      controller.nudge(5, 10);
      expect(controller.state.translateX, 5);
      expect(controller.state.translateY, 10);
      controller.dispose();
    });

    test('adjustRotation adds degrees', () {
      final controller = createController();
      controller.adjustRotation(15);
      expect(controller.state.rotation, 15);
      controller.dispose();
    });

    test('adjustScale changes scale by percentage', () {
      final controller = createController();
      controller.adjustScale(10); // +10%
      expect(controller.state.scale, closeTo(1.1, 0.01));
      controller.dispose();
    });

    test('reset returns to identity', () {
      final controller = createController(
        translateX: 50,
        translateY: 100,
        scale: 2.0,
        rotation: 45,
      );
      controller.reset();
      expect(controller.state.translateX, 0);
      expect(controller.state.translateY, 0);
      expect(controller.state.rotation, 0);
      controller.dispose();
    });
  });

  group('TransformController Gestures', () {
    test('beginGesture sets active handle', () {
      final controller = createController();
      controller.beginGesture(TransformHandle.body, const Offset(100, 100));
      expect(controller.isGestureActive, isTrue);
      expect(controller.activeHandle, TransformHandle.body);
      controller.dispose();
    });

    test('endGesture clears active handle', () {
      final controller = createController();
      controller.beginGesture(TransformHandle.body, const Offset(100, 100));
      controller.endGesture();
      expect(controller.isGestureActive, isFalse);
      expect(controller.activeHandle, TransformHandle.none);
      controller.dispose();
    });

    test('cancelGesture reverts to start state', () {
      final controller = createController();
      final initialX = controller.state.translateX;
      controller.beginGesture(TransformHandle.body, const Offset(100, 100));
      controller.updateGesture(const Offset(200, 200));
      controller.cancelGesture();
      expect(controller.state.translateX, initialX);
      controller.dispose();
    });
  });

  group('TransformController Undo/Redo', () {
    test('initially cannot undo or redo', () {
      final controller = createController();
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);
      controller.dispose();
    });

    test('undo returns false when nothing to undo', () {
      final controller = createController();
      expect(controller.undo(), isFalse);
      controller.dispose();
    });

    test('redo returns false when nothing to redo', () {
      final controller = createController();
      expect(controller.redo(), isFalse);
      controller.dispose();
    });

    test('commitToHistory enables undo', () {
      final controller = createController();
      controller.commitToHistory();
      controller.setTranslation(50, 50);
      expect(controller.canUndo, isTrue);
      controller.dispose();
    });

    test('clearHistory removes all history', () {
      final controller = createController();
      controller.commitToHistory();
      controller.setTranslation(50, 50);
      controller.clearHistory();
      expect(controller.canUndo, isFalse);
      controller.dispose();
    });
  });

  group('TransformController Canvas/Image Updates', () {
    test('updateCanvasSize updates canvas size', () {
      final controller = createController();
      controller.updateCanvasSize(const Size(1920, 1080));
      expect(controller.state.canvasSize, const Size(1920, 1080));
      controller.dispose();
    });

    test('updateImageSize updates image size', () {
      final controller = createController();
      controller.updateImageSize(const Size(3840, 2160));
      expect(controller.state.imageSize, const Size(3840, 2160));
      controller.dispose();
    });
  });

  group('TransformController Database Export', () {
    test('toDatabaseValues returns map with expected keys', () {
      final controller = createController();
      final values = controller.toDatabaseValues();
      expect(values, containsPair('translateX', isA<double>()));
      expect(values, containsPair('translateY', isA<double>()));
      expect(values, containsPair('scaleFactor', isA<double>()));
      expect(values, containsPair('rotationDegrees', isA<double>()));
      controller.dispose();
    });

    test('databaseTranslateX matches state', () {
      final controller = createController(translateX: 42);
      expect(controller.databaseTranslateX, 42);
      controller.dispose();
    });

    test('databaseRotationDegrees matches state', () {
      final controller = createController(rotation: 90);
      expect(controller.databaseRotationDegrees, 90);
      controller.dispose();
    });
  });

  group('TransformController Notification', () {
    test('notifies listeners on state change', () {
      final controller = createController();
      var notified = false;
      controller.addListener(() => notified = true);
      controller.setTranslation(10, 20);
      expect(notified, isTrue);
      controller.dispose();
    });

    test('does not notify when state is unchanged', () {
      final controller = createController();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);
      controller.setTranslation(0, 0); // Same as default
      expect(notifyCount, 0);
      controller.dispose();
    });
  });
}
