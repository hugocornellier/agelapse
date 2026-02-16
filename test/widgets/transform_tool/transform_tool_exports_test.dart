import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/transform_tool/transform_tool_exports.dart';

/// Unit tests for transform_tool_exports.dart barrel file.
/// Verifies all expected types are re-exported.
void main() {
  group('Transform Tool Exports', () {
    test('TransformController is exported', () {
      expect(TransformController, isNotNull);
    });

    test('TransformGestureHandler is exported', () {
      expect(TransformGestureHandler, isNotNull);
    });

    test('TransformHandle is exported', () {
      expect(TransformHandle, isNotNull);
    });

    test('TransformHandlePainter is exported', () {
      expect(TransformHandlePainter, isNotNull);
    });

    test('TransformHistory is exported', () {
      expect(TransformHistory, isNotNull);
    });

    test('TransformState is exported', () {
      expect(TransformState, isNotNull);
    });

    test('TransformTool is exported', () {
      expect(TransformTool, isNotNull);
    });

    test('cornerHandles constant is exported', () {
      expect(cornerHandles, isNotNull);
      expect(cornerHandles.length, 4);
    });

    test('edgeHandles constant is exported', () {
      expect(edgeHandles, isNotNull);
      expect(edgeHandles.length, 4);
    });

    test('resizeHandles constant is exported', () {
      expect(resizeHandles, isNotNull);
      expect(resizeHandles.length, 8);
    });
  });
}
