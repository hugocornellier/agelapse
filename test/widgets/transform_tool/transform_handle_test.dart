import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/transform_tool/transform_handle.dart';

/// Unit tests for TransformHandle enum and extension.
void main() {
  group('TransformHandle enum', () {
    test('has 11 values', () {
      expect(TransformHandle.values.length, 11);
    });

    test('contains all expected values', () {
      expect(TransformHandle.values, contains(TransformHandle.topLeft));
      expect(TransformHandle.values, contains(TransformHandle.topRight));
      expect(TransformHandle.values, contains(TransformHandle.bottomLeft));
      expect(TransformHandle.values, contains(TransformHandle.bottomRight));
      expect(TransformHandle.values, contains(TransformHandle.topCenter));
      expect(TransformHandle.values, contains(TransformHandle.bottomCenter));
      expect(TransformHandle.values, contains(TransformHandle.leftCenter));
      expect(TransformHandle.values, contains(TransformHandle.rightCenter));
      expect(TransformHandle.values, contains(TransformHandle.rotationHandle));
      expect(TransformHandle.values, contains(TransformHandle.body));
      expect(TransformHandle.values, contains(TransformHandle.none));
    });
  });

  group('TransformHandle isCorner', () {
    test('topLeft is corner', () {
      expect(TransformHandle.topLeft.isCorner, isTrue);
    });

    test('topRight is corner', () {
      expect(TransformHandle.topRight.isCorner, isTrue);
    });

    test('bottomLeft is corner', () {
      expect(TransformHandle.bottomLeft.isCorner, isTrue);
    });

    test('bottomRight is corner', () {
      expect(TransformHandle.bottomRight.isCorner, isTrue);
    });

    test('topCenter is not corner', () {
      expect(TransformHandle.topCenter.isCorner, isFalse);
    });

    test('body is not corner', () {
      expect(TransformHandle.body.isCorner, isFalse);
    });

    test('none is not corner', () {
      expect(TransformHandle.none.isCorner, isFalse);
    });
  });

  group('TransformHandle isEdge', () {
    test('topCenter is edge', () {
      expect(TransformHandle.topCenter.isEdge, isTrue);
    });

    test('bottomCenter is edge', () {
      expect(TransformHandle.bottomCenter.isEdge, isTrue);
    });

    test('leftCenter is edge', () {
      expect(TransformHandle.leftCenter.isEdge, isTrue);
    });

    test('rightCenter is edge', () {
      expect(TransformHandle.rightCenter.isEdge, isTrue);
    });

    test('topLeft is not edge', () {
      expect(TransformHandle.topLeft.isEdge, isFalse);
    });

    test('body is not edge', () {
      expect(TransformHandle.body.isEdge, isFalse);
    });
  });

  group('TransformHandle isResize', () {
    test('corners are resize', () {
      expect(TransformHandle.topLeft.isResize, isTrue);
      expect(TransformHandle.topRight.isResize, isTrue);
      expect(TransformHandle.bottomLeft.isResize, isTrue);
      expect(TransformHandle.bottomRight.isResize, isTrue);
    });

    test('edges are resize', () {
      expect(TransformHandle.topCenter.isResize, isTrue);
      expect(TransformHandle.bottomCenter.isResize, isTrue);
      expect(TransformHandle.leftCenter.isResize, isTrue);
      expect(TransformHandle.rightCenter.isResize, isTrue);
    });

    test('rotation handle is not resize', () {
      expect(TransformHandle.rotationHandle.isResize, isFalse);
    });

    test('body is not resize', () {
      expect(TransformHandle.body.isResize, isFalse);
    });

    test('none is not resize', () {
      expect(TransformHandle.none.isResize, isFalse);
    });
  });

  group('TransformHandle isRotation', () {
    test('rotationHandle is rotation', () {
      expect(TransformHandle.rotationHandle.isRotation, isTrue);
    });

    test('topLeft is not rotation', () {
      expect(TransformHandle.topLeft.isRotation, isFalse);
    });

    test('body is not rotation', () {
      expect(TransformHandle.body.isRotation, isFalse);
    });
  });

  group('TransformHandle defaultMaintainAspectRatio', () {
    test('corners default to maintain aspect ratio', () {
      expect(TransformHandle.topLeft.defaultMaintainAspectRatio, isTrue);
      expect(TransformHandle.bottomRight.defaultMaintainAspectRatio, isTrue);
    });

    test('edges default to not maintain aspect ratio', () {
      expect(TransformHandle.topCenter.defaultMaintainAspectRatio, isFalse);
    });
  });

  group('TransformHandle cursor', () {
    test('each handle returns a SystemMouseCursor', () {
      for (final handle in TransformHandle.values) {
        expect(handle.cursor, isA<SystemMouseCursor>());
      }
    });

    test('body returns grab cursor', () {
      expect(TransformHandle.body.cursor, SystemMouseCursors.grab);
    });

    test('none returns basic cursor', () {
      expect(TransformHandle.none.cursor, SystemMouseCursors.basic);
    });

    test('rotationHandle returns alias cursor', () {
      expect(TransformHandle.rotationHandle.cursor, SystemMouseCursors.alias);
    });
  });

  group('TransformHandle activeCursor', () {
    test('body returns grabbing cursor', () {
      expect(TransformHandle.body.activeCursor, SystemMouseCursors.grabbing);
    });

    test('non-body returns same as cursor', () {
      expect(
          TransformHandle.topLeft.activeCursor, TransformHandle.topLeft.cursor);
    });
  });

  group('TransformHandle anchorIndex', () {
    test('topLeft anchor is bottomRight (index 2)', () {
      expect(TransformHandle.topLeft.anchorIndex, 2);
    });

    test('topRight anchor is bottomLeft (index 3)', () {
      expect(TransformHandle.topRight.anchorIndex, 3);
    });

    test('bottomRight anchor is topLeft (index 0)', () {
      expect(TransformHandle.bottomRight.anchorIndex, 0);
    });

    test('bottomLeft anchor is topRight (index 1)', () {
      expect(TransformHandle.bottomLeft.anchorIndex, 1);
    });

    test('non-resize handles return -1', () {
      expect(TransformHandle.body.anchorIndex, -1);
      expect(TransformHandle.none.anchorIndex, -1);
    });
  });

  group('TransformHandle edge properties', () {
    test('leftCenter is horizontal edge', () {
      expect(TransformHandle.leftCenter.isHorizontalEdge, isTrue);
    });

    test('rightCenter is horizontal edge', () {
      expect(TransformHandle.rightCenter.isHorizontalEdge, isTrue);
    });

    test('topCenter is vertical edge', () {
      expect(TransformHandle.topCenter.isVerticalEdge, isTrue);
    });

    test('bottomCenter is vertical edge', () {
      expect(TransformHandle.bottomCenter.isVerticalEdge, isTrue);
    });

    test('corners are not horizontal or vertical edges', () {
      expect(TransformHandle.topLeft.isHorizontalEdge, isFalse);
      expect(TransformHandle.topLeft.isVerticalEdge, isFalse);
    });
  });

  group('cornerHandles constant', () {
    test('has 4 handles', () {
      expect(cornerHandles.length, 4);
    });

    test('contains all corners', () {
      expect(cornerHandles, contains(TransformHandle.topLeft));
      expect(cornerHandles, contains(TransformHandle.topRight));
      expect(cornerHandles, contains(TransformHandle.bottomRight));
      expect(cornerHandles, contains(TransformHandle.bottomLeft));
    });
  });

  group('edgeHandles constant', () {
    test('has 4 handles', () {
      expect(edgeHandles.length, 4);
    });

    test('contains all edges', () {
      expect(edgeHandles, contains(TransformHandle.topCenter));
      expect(edgeHandles, contains(TransformHandle.rightCenter));
      expect(edgeHandles, contains(TransformHandle.bottomCenter));
      expect(edgeHandles, contains(TransformHandle.leftCenter));
    });
  });

  group('resizeHandles constant', () {
    test('has 8 handles (4 corners + 4 edges)', () {
      expect(resizeHandles.length, 8);
    });
  });
}
