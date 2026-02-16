import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/transform_tool/transform_handle_painter.dart';
import 'package:agelapse/widgets/transform_tool/transform_state.dart';
import 'package:agelapse/widgets/transform_tool/transform_handle.dart';

/// Unit tests for TransformHandlePainter and TransformBoundingBoxPainter.
void main() {
  TransformState createState() {
    return TransformState(
      translateX: 0,
      translateY: 0,
      scale: 1.0,
      rotation: 0,
      pivot: const Offset(400, 300),
      imageSize: const Size(800, 600),
      canvasSize: const Size(800, 600),
    );
  }

  group('TransformHandlePainter', () {
    test('can be instantiated with required parameters', () {
      final painter = TransformHandlePainter(state: createState());
      expect(painter, isA<TransformHandlePainter>());
      expect(painter, isA<CustomPainter>());
    });

    test('stores state', () {
      final state = createState();
      final painter = TransformHandlePainter(state: state);
      expect(painter.state, equals(state));
    });

    test('has default visual configuration', () {
      final painter = TransformHandlePainter(state: createState());
      expect(painter.handleSize, 10.0);
      expect(painter.edgeHandleSize, 8.0);
      expect(painter.rotationHandleSize, 12.0);
      expect(painter.rotationHandleDistance, 30.0);
      expect(painter.boundingBoxWidth, 1.0);
      expect(painter.handleStrokeWidth, 1.5);
    });

    test('accepts custom visual configuration', () {
      final painter = TransformHandlePainter(
        state: createState(),
        handleSize: 14.0,
        edgeHandleSize: 12.0,
        rotationHandleSize: 16.0,
        displayScale: 2.0,
      );
      expect(painter.handleSize, 14.0);
      expect(painter.edgeHandleSize, 12.0);
      expect(painter.rotationHandleSize, 16.0);
      expect(painter.displayScale, 2.0);
    });

    test('showRotationHandle defaults to true', () {
      final painter = TransformHandlePainter(state: createState());
      expect(painter.showRotationHandle, isTrue);
    });

    test('showPivotPoint defaults to false', () {
      final painter = TransformHandlePainter(state: createState());
      expect(painter.showPivotPoint, isFalse);
    });

    test('showCornerHandles defaults to true', () {
      final painter = TransformHandlePainter(state: createState());
      expect(painter.showCornerHandles, isTrue);
    });

    test('showEdgeHandles defaults to true', () {
      final painter = TransformHandlePainter(state: createState());
      expect(painter.showEdgeHandles, isTrue);
    });

    test('accepts activeHandle', () {
      final painter = TransformHandlePainter(
        state: createState(),
        activeHandle: TransformHandle.topLeft,
      );
      expect(painter.activeHandle, TransformHandle.topLeft);
    });

    test('accepts hoveredHandle', () {
      final painter = TransformHandlePainter(
        state: createState(),
        hoveredHandle: TransformHandle.body,
      );
      expect(painter.hoveredHandle, TransformHandle.body);
    });

    group('shouldRepaint', () {
      test('returns true when state changes', () {
        final state1 = createState();
        final state2 = TransformState(
          translateX: 10,
          translateY: 0,
          scale: 1.0,
          rotation: 0,
          pivot: const Offset(400, 300),
          imageSize: const Size(800, 600),
          canvasSize: const Size(800, 600),
        );
        final painter1 = TransformHandlePainter(state: state1);
        final painter2 = TransformHandlePainter(state: state2);
        expect(painter1.shouldRepaint(painter2), isTrue);
      });

      test('returns false when nothing changes', () {
        final state = createState();
        final painter1 = TransformHandlePainter(state: state);
        final painter2 = TransformHandlePainter(state: state);
        expect(painter1.shouldRepaint(painter2), isFalse);
      });

      test('returns true when activeHandle changes', () {
        final state = createState();
        final painter1 = TransformHandlePainter(
          state: state,
          activeHandle: TransformHandle.topLeft,
        );
        final painter2 = TransformHandlePainter(
          state: state,
          activeHandle: TransformHandle.body,
        );
        expect(painter1.shouldRepaint(painter2), isTrue);
      });

      test('returns true when displayScale changes', () {
        final state = createState();
        final painter1 = TransformHandlePainter(
          state: state,
          displayScale: 1.0,
        );
        final painter2 = TransformHandlePainter(
          state: state,
          displayScale: 2.0,
        );
        expect(painter1.shouldRepaint(painter2), isTrue);
      });
    });
  });

  group('TransformBoundingBoxPainter', () {
    test('can be instantiated with required parameters', () {
      final painter = TransformBoundingBoxPainter(state: createState());
      expect(painter, isA<TransformBoundingBoxPainter>());
      expect(painter, isA<CustomPainter>());
    });

    test('has default color', () {
      final painter = TransformBoundingBoxPainter(state: createState());
      expect(painter.color, const Color(0xFF2196F3));
    });

    test('has default strokeWidth', () {
      final painter = TransformBoundingBoxPainter(state: createState());
      expect(painter.strokeWidth, 1.5);
    });

    test('dashed defaults to false', () {
      final painter = TransformBoundingBoxPainter(state: createState());
      expect(painter.dashed, isFalse);
    });

    test('accepts custom values', () {
      final painter = TransformBoundingBoxPainter(
        state: createState(),
        color: Colors.red,
        strokeWidth: 3.0,
        dashed: true,
      );
      expect(painter.color, Colors.red);
      expect(painter.strokeWidth, 3.0);
      expect(painter.dashed, isTrue);
    });

    group('shouldRepaint', () {
      test('returns true when state changes', () {
        final state1 = createState();
        final state2 = TransformState(
          translateX: 10,
          translateY: 0,
          scale: 1.0,
          rotation: 0,
          pivot: const Offset(400, 300),
          imageSize: const Size(800, 600),
          canvasSize: const Size(800, 600),
        );
        final p1 = TransformBoundingBoxPainter(state: state1);
        final p2 = TransformBoundingBoxPainter(state: state2);
        expect(p1.shouldRepaint(p2), isTrue);
      });

      test('returns false when nothing changes', () {
        final state = createState();
        final p1 = TransformBoundingBoxPainter(state: state);
        final p2 = TransformBoundingBoxPainter(state: state);
        expect(p1.shouldRepaint(p2), isFalse);
      });

      test('returns true when dashed changes', () {
        final state = createState();
        final p1 = TransformBoundingBoxPainter(state: state, dashed: false);
        final p2 = TransformBoundingBoxPainter(state: state, dashed: true);
        expect(p1.shouldRepaint(p2), isTrue);
      });
    });
  });
}
