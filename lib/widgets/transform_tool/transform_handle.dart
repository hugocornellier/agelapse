import 'package:flutter/services.dart';
import 'transform_state.dart';

/// Represents the different interactive handles on the transform bounding box.
enum TransformHandle {
  /// Top-left corner handle (resize)
  topLeft,

  /// Top-right corner handle (resize)
  topRight,

  /// Bottom-left corner handle (resize)
  bottomLeft,

  /// Bottom-right corner handle (resize)
  bottomRight,

  /// Top edge center handle (resize height)
  topCenter,

  /// Bottom edge center handle (resize height)
  bottomCenter,

  /// Left edge center handle (resize width)
  leftCenter,

  /// Right edge center handle (resize width)
  rightCenter,

  /// Rotation handle (outside top edge)
  rotationHandle,

  /// Body of the image (drag to move)
  body,

  /// No handle (outside all interactive zones)
  none,
}

/// Extension providing additional properties and methods for TransformHandle
extension TransformHandleExtension on TransformHandle {
  /// Whether this is a corner handle (for proportional resize)
  bool get isCorner =>
      this == TransformHandle.topLeft ||
      this == TransformHandle.topRight ||
      this == TransformHandle.bottomLeft ||
      this == TransformHandle.bottomRight;

  /// Whether this is an edge handle
  bool get isEdge =>
      this == TransformHandle.topCenter ||
      this == TransformHandle.bottomCenter ||
      this == TransformHandle.leftCenter ||
      this == TransformHandle.rightCenter;

  /// Whether this handle is used for rotation
  bool get isRotation => this == TransformHandle.rotationHandle;

  /// Whether this handle allows resizing
  bool get isResize => isCorner || isEdge;

  /// Whether this handle should maintain aspect ratio by default
  bool get defaultMaintainAspectRatio => isCorner;

  /// Get the appropriate mouse cursor for this handle
  SystemMouseCursor get cursor {
    switch (this) {
      case TransformHandle.topLeft:
      case TransformHandle.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case TransformHandle.topRight:
      case TransformHandle.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
      case TransformHandle.topCenter:
      case TransformHandle.bottomCenter:
        return SystemMouseCursors.resizeUpDown;
      case TransformHandle.leftCenter:
      case TransformHandle.rightCenter:
        return SystemMouseCursors.resizeLeftRight;
      case TransformHandle.rotationHandle:
        // No built-in rotation cursor, use alias or grab
        return SystemMouseCursors.alias;
      case TransformHandle.body:
        return SystemMouseCursors.grab;
      case TransformHandle.none:
        return SystemMouseCursors.basic;
    }
  }

  /// Get the cursor to show while actively dragging this handle
  SystemMouseCursor get activeCursor {
    if (this == TransformHandle.body) {
      return SystemMouseCursors.grabbing;
    }
    return cursor;
  }

  /// Get the anchor point index for scaling operations.
  /// Returns the index of the opposite corner/edge in the corners/edgeMidpoints list.
  /// Returns -1 for non-resize handles.
  int get anchorIndex {
    switch (this) {
      case TransformHandle.topLeft:
        return 2; // bottom-right corner
      case TransformHandle.topRight:
        return 3; // bottom-left corner
      case TransformHandle.bottomRight:
        return 0; // top-left corner
      case TransformHandle.bottomLeft:
        return 1; // top-right corner
      case TransformHandle.topCenter:
        return 2; // bottom edge midpoint
      case TransformHandle.bottomCenter:
        return 0; // top edge midpoint
      case TransformHandle.leftCenter:
        return 1; // right edge midpoint
      case TransformHandle.rightCenter:
        return 3; // left edge midpoint
      default:
        return -1;
    }
  }

  /// Get the anchor point for scaling operations (opposite corner/edge).
  Offset? getAnchorPoint(TransformState state) {
    if (!isResize) return null;

    if (isCorner) {
      return state.corners[anchorIndex];
    } else {
      return state.edgeMidpoints[anchorIndex];
    }
  }

  /// Get the position of this handle in canvas coordinates
  Offset? getPosition(TransformState state,
      {double rotationHandleDistance = 30}) {
    switch (this) {
      case TransformHandle.topLeft:
        return state.corners[0];
      case TransformHandle.topRight:
        return state.corners[1];
      case TransformHandle.bottomRight:
        return state.corners[2];
      case TransformHandle.bottomLeft:
        return state.corners[3];
      case TransformHandle.topCenter:
        return state.edgeMidpoints[0];
      case TransformHandle.rightCenter:
        return state.edgeMidpoints[1];
      case TransformHandle.bottomCenter:
        return state.edgeMidpoints[2];
      case TransformHandle.leftCenter:
        return state.edgeMidpoints[3];
      case TransformHandle.rotationHandle:
        return state.getRotationHandlePosition(rotationHandleDistance);
      case TransformHandle.body:
      case TransformHandle.none:
        return null;
    }
  }

  /// Get the index of this handle's position in the corners list (0-3 for corners)
  int get cornerIndex {
    switch (this) {
      case TransformHandle.topLeft:
        return 0;
      case TransformHandle.topRight:
        return 1;
      case TransformHandle.bottomRight:
        return 2;
      case TransformHandle.bottomLeft:
        return 3;
      default:
        return -1;
    }
  }

  /// Get the index of this handle's position in the edgeMidpoints list (0-3 for edges)
  int get edgeIndex {
    switch (this) {
      case TransformHandle.topCenter:
        return 0;
      case TransformHandle.rightCenter:
        return 1;
      case TransformHandle.bottomCenter:
        return 2;
      case TransformHandle.leftCenter:
        return 3;
      default:
        return -1;
    }
  }

  /// Whether this edge handle affects horizontal sizing
  bool get isHorizontalEdge =>
      this == TransformHandle.leftCenter || this == TransformHandle.rightCenter;

  /// Whether this edge handle affects vertical sizing
  bool get isVerticalEdge =>
      this == TransformHandle.topCenter || this == TransformHandle.bottomCenter;
}

/// List of all corner handles in order
const cornerHandles = [
  TransformHandle.topLeft,
  TransformHandle.topRight,
  TransformHandle.bottomRight,
  TransformHandle.bottomLeft,
];

/// List of all edge handles in order (top, right, bottom, left)
const edgeHandles = [
  TransformHandle.topCenter,
  TransformHandle.rightCenter,
  TransformHandle.bottomCenter,
  TransformHandle.leftCenter,
];

/// List of all resize handles (corners + edges)
const resizeHandles = [...cornerHandles, ...edgeHandles];
