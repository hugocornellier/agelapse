import 'dart:math';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/transform_tool/transform_state.dart';

void main() {
  group('TransformState', () {
    group('constructor', () {
      test('creates instance with all required parameters', () {
        const state = TransformState(
          translateX: 10.0,
          translateY: 20.0,
          scale: 1.5,
          rotation: 45.0,
          pivot: Offset(100, 100),
          imageSize: Size(800, 600),
          canvasSize: Size(400, 300),
        );

        expect(state.translateX, equals(10.0));
        expect(state.translateY, equals(20.0));
        expect(state.scale, equals(1.5));
        expect(state.rotation, equals(45.0));
        expect(state.pivot, equals(const Offset(100, 100)));
        expect(state.imageSize, equals(const Size(800, 600)));
        expect(state.canvasSize, equals(const Size(400, 300)));
        expect(state.baseScale, equals(1.0)); // default
      });

      test('uses custom baseScale when provided', () {
        const state = TransformState(
          translateX: 0,
          translateY: 0,
          scale: 1.0,
          rotation: 0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
          baseScale: 0.5,
        );

        expect(state.baseScale, equals(0.5));
      });
    });

    group('identity factory', () {
      test('creates centered state with no rotation', () {
        final state = TransformState.identity(
          imageSize: const Size(800, 600),
          canvasSize: const Size(400, 300),
        );

        expect(state.translateX, equals(0));
        expect(state.translateY, equals(0));
        expect(state.scale, equals(1.0));
        expect(state.rotation, equals(0));
        expect(state.pivot, equals(const Offset(200, 150)));
      });

      test('uses provided baseScale', () {
        final state = TransformState.identity(
          imageSize: const Size(100, 100),
          canvasSize: const Size(50, 50),
          baseScale: 0.25,
        );

        expect(state.baseScale, equals(0.25));
      });
    });

    group('fromDatabaseValues factory', () {
      test('creates state from stored values', () {
        final state = TransformState.fromDatabaseValues(
          translateX: 10.0,
          translateY: 20.0,
          scaleFactor: 0.5,
          rotationDegrees: 90.0,
          imageSize: const Size(800, 600),
          canvasSize: const Size(400, 300),
          baseScale: 0.25,
        );

        expect(state.translateX, equals(10.0));
        expect(state.translateY, equals(20.0));
        expect(state.scale, equals(2.0)); // 0.5 / 0.25
        expect(state.rotation, equals(90.0));
      });
    });

    group('computed properties', () {
      test('effectiveScale returns scale * baseScale', () {
        const state = TransformState(
          translateX: 0,
          translateY: 0,
          scale: 2.0,
          rotation: 0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
          baseScale: 0.5,
        );

        expect(state.effectiveScale, equals(1.0)); // 2.0 * 0.5
      });

      test('rotationRadians converts degrees to radians', () {
        const state = TransformState(
          translateX: 0,
          translateY: 0,
          scale: 1.0,
          rotation: 180.0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        expect(state.rotationRadians, closeTo(pi, 0.001));
      });

      test('rotationRadians handles 90 degrees', () {
        const state = TransformState(
          translateX: 0,
          translateY: 0,
          scale: 1.0,
          rotation: 90.0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        expect(state.rotationRadians, closeTo(pi / 2, 0.001));
      });

      test('imageCenter includes translation', () {
        const state = TransformState(
          translateX: 10.0,
          translateY: 20.0,
          scale: 1.0,
          rotation: 0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        // Canvas center (50, 50) + translation (10, 20)
        expect(state.imageCenter, equals(const Offset(60, 70)));
      });

      test('scaledImageSize applies effective scale', () {
        const state = TransformState(
          translateX: 0,
          translateY: 0,
          scale: 2.0,
          rotation: 0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
          baseScale: 1.0,
        );

        expect(state.scaledImageSize, equals(const Size(200, 200)));
      });
    });

    group('corners', () {
      test('returns four corners in correct order without rotation', () {
        const state = TransformState(
          translateX: 0,
          translateY: 0,
          scale: 1.0,
          rotation: 0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        final corners = state.corners;
        expect(corners.length, equals(4));
        // Center at (50, 50), size 100x100 -> corners at 0,0 to 100,100
        expect(corners[0], equals(const Offset(0, 0))); // top-left
        expect(corners[1], equals(const Offset(100, 0))); // top-right
        expect(corners[2], equals(const Offset(100, 100))); // bottom-right
        expect(corners[3], equals(const Offset(0, 100))); // bottom-left
      });

      test('corners rotate around center', () {
        const state = TransformState(
          translateX: 0,
          translateY: 0,
          scale: 1.0,
          rotation: 90.0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        final corners = state.corners;
        // After 90-degree rotation, corners should have swapped positions
        // Top-left becomes top-right, etc.
        expect(corners[0].dx, closeTo(100, 0.01));
        expect(corners[0].dy, closeTo(0, 0.01));
      });
    });

    group('boundingBox', () {
      test('returns axis-aligned bounding box', () {
        const state = TransformState(
          translateX: 0,
          translateY: 0,
          scale: 1.0,
          rotation: 0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        final bbox = state.boundingBox;
        expect(bbox.left, equals(0));
        expect(bbox.top, equals(0));
        expect(bbox.right, equals(100));
        expect(bbox.bottom, equals(100));
      });

      test('boundingBox expands for rotated image', () {
        const state = TransformState(
          translateX: 0,
          translateY: 0,
          scale: 1.0,
          rotation: 45.0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        final bbox = state.boundingBox;
        // Rotated square has larger bounding box
        expect(bbox.width, greaterThan(100));
        expect(bbox.height, greaterThan(100));
      });
    });

    group('edgeMidpoints', () {
      test('returns four midpoints in correct order', () {
        const state = TransformState(
          translateX: 0,
          translateY: 0,
          scale: 1.0,
          rotation: 0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        final midpoints = state.edgeMidpoints;
        expect(midpoints.length, equals(4));
        expect(midpoints[0], equals(const Offset(50, 0))); // top
        expect(midpoints[1], equals(const Offset(100, 50))); // right
        expect(midpoints[2], equals(const Offset(50, 100))); // bottom
        expect(midpoints[3], equals(const Offset(0, 50))); // left
      });
    });

    group('getRotationHandlePosition', () {
      test('returns position above top edge midpoint', () {
        const state = TransformState(
          translateX: 0,
          translateY: 0,
          scale: 1.0,
          rotation: 0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        final handlePos = state.getRotationHandlePosition(20);
        // Top midpoint is (50, 0), 20 pixels above = (50, -20)
        expect(handlePos.dx, closeTo(50, 0.01));
        expect(handlePos.dy, closeTo(-20, 0.01));
      });
    });

    group('copyWith', () {
      test('creates copy with updated translateX', () {
        const original = TransformState(
          translateX: 10,
          translateY: 20,
          scale: 1.0,
          rotation: 0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        final copy = original.copyWith(translateX: 30);

        expect(copy.translateX, equals(30));
        expect(copy.translateY, equals(20)); // unchanged
        expect(copy.scale, equals(1.0)); // unchanged
      });

      test('creates copy with multiple updated values', () {
        const original = TransformState(
          translateX: 0,
          translateY: 0,
          scale: 1.0,
          rotation: 0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        final copy = original.copyWith(
          scale: 2.0,
          rotation: 45.0,
        );

        expect(copy.scale, equals(2.0));
        expect(copy.rotation, equals(45.0));
        expect(copy.translateX, equals(0)); // unchanged
      });
    });

    group('withTranslation', () {
      test('applies translation delta', () {
        const state = TransformState(
          translateX: 10,
          translateY: 20,
          scale: 1.0,
          rotation: 0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        final moved = state.withTranslation(const Offset(5, 10));

        expect(moved.translateX, equals(15));
        expect(moved.translateY, equals(30));
      });

      test('handles negative deltas', () {
        const state = TransformState(
          translateX: 10,
          translateY: 20,
          scale: 1.0,
          rotation: 0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        final moved = state.withTranslation(const Offset(-5, -10));

        expect(moved.translateX, equals(5));
        expect(moved.translateY, equals(10));
      });
    });

    group('withScaleAroundAnchor', () {
      test('scales around anchor point', () {
        final state = TransformState.identity(
          imageSize: const Size(100, 100),
          canvasSize: const Size(100, 100),
        );

        final scaled = state.withScaleAroundAnchor(2.0, const Offset(50, 50));

        expect(scaled.scale, equals(2.0));
      });

      test('adjusts translation when scaling around non-center point', () {
        final state = TransformState.identity(
          imageSize: const Size(100, 100),
          canvasSize: const Size(100, 100),
        );

        final scaled = state.withScaleAroundAnchor(2.0, const Offset(0, 0));

        expect(scaled.scale, equals(2.0));
        // Translation should be adjusted to keep top-left fixed
        expect(scaled.translateX, isNot(equals(0)));
        expect(scaled.translateY, isNot(equals(0)));
      });
    });

    group('withRotationAroundPivot', () {
      test('rotates around pivot point', () {
        final state = TransformState.identity(
          imageSize: const Size(100, 100),
          canvasSize: const Size(100, 100),
        );

        final rotated =
            state.withRotationAroundPivot(90.0, const Offset(50, 50));

        expect(rotated.rotation, equals(90.0));
      });

      test('adjusts translation when rotating around non-center point', () {
        final state = TransformState.identity(
          imageSize: const Size(100, 100),
          canvasSize: const Size(100, 100),
        );

        // Rotate around a corner (100, 100) instead of (0, 0)
        final rotated =
            state.withRotationAroundPivot(90.0, const Offset(100, 100));

        expect(rotated.rotation, equals(90.0));
        // Translation should be adjusted when rotating around a non-center point
        // The center moves in a circle around the pivot
        expect(rotated.translateX != 0 || rotated.translateY != 0, isTrue);
      });
    });

    group('containsPoint', () {
      test('returns true for point inside unrotated image', () {
        const state = TransformState(
          translateX: 0,
          translateY: 0,
          scale: 1.0,
          rotation: 0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        expect(state.containsPoint(const Offset(50, 50)), isTrue);
        expect(state.containsPoint(const Offset(10, 10)), isTrue);
        expect(state.containsPoint(const Offset(90, 90)), isTrue);
      });

      test('returns false for point outside unrotated image', () {
        const state = TransformState(
          translateX: 0,
          translateY: 0,
          scale: 1.0,
          rotation: 0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        expect(state.containsPoint(const Offset(-10, 50)), isFalse);
        expect(state.containsPoint(const Offset(110, 50)), isFalse);
        expect(state.containsPoint(const Offset(50, 110)), isFalse);
      });

      test('handles rotated image correctly', () {
        const state = TransformState(
          translateX: 0,
          translateY: 0,
          scale: 1.0,
          rotation: 45.0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        // Center should still be inside
        expect(state.containsPoint(const Offset(50, 50)), isTrue);
      });
    });

    group('toDatabaseValues', () {
      test('converts to storable map', () {
        const state = TransformState(
          translateX: 10.0,
          translateY: 20.0,
          scale: 2.0,
          rotation: 45.0,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        final values = state.toDatabaseValues(0.5);

        expect(values['translateX'], equals(10.0));
        expect(values['translateY'], equals(20.0));
        expect(values['scaleFactor'], equals(1.0)); // 2.0 * 0.5
        expect(values['rotationDegrees'], equals(45.0));
      });
    });

    group('equality', () {
      test('equal states are equal', () {
        const state1 = TransformState(
          translateX: 10,
          translateY: 20,
          scale: 1.5,
          rotation: 45,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        const state2 = TransformState(
          translateX: 10,
          translateY: 20,
          scale: 1.5,
          rotation: 45,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        expect(state1 == state2, isTrue);
        expect(state1.hashCode, equals(state2.hashCode));
      });

      test('different states are not equal', () {
        const state1 = TransformState(
          translateX: 10,
          translateY: 20,
          scale: 1.5,
          rotation: 45,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        const state2 = TransformState(
          translateX: 10,
          translateY: 20,
          scale: 2.0, // different
          rotation: 45,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        expect(state1 == state2, isFalse);
      });

      test('identical states are equal', () {
        const state = TransformState(
          translateX: 10,
          translateY: 20,
          scale: 1.5,
          rotation: 45,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        expect(state == state, isTrue);
      });
    });

    group('toString', () {
      test('returns readable string representation', () {
        const state = TransformState(
          translateX: 10,
          translateY: 20,
          scale: 1.5,
          rotation: 45,
          pivot: Offset(50, 50),
          imageSize: Size(100, 100),
          canvasSize: Size(100, 100),
        );

        final str = state.toString();

        expect(str, contains('TransformState'));
        expect(str, contains('tx: 10'));
        expect(str, contains('ty: 20'));
        expect(str, contains('scale: 1.5'));
        expect(str, contains('rotation: 45'));
      });
    });
  });
}
