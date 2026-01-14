import 'dart:math';
import 'dart:ui';

import 'transform_handle.dart';
import 'transform_state.dart';

/// Pure math functions for handling transform gestures.
///
/// This class provides stateless utility methods for calculating
/// new transform states based on gesture inputs.
class TransformGestureHandler {
  TransformGestureHandler._();

  /// Calculate new state after applying a drag (translation) gesture.
  ///
  /// [state] Current transform state
  /// [delta] Movement delta in canvas coordinates
  static TransformState applyDrag(TransformState state, Offset delta) {
    return state.withTranslation(delta);
  }

  /// Calculate new state after applying a scale gesture from a resize handle.
  ///
  /// [state] Current transform state
  /// [handle] The handle being dragged
  /// [startPosition] Position where the gesture started
  /// [currentPosition] Current gesture position
  /// [startState] Transform state when gesture began
  /// [maintainAspectRatio] Whether to constrain proportions
  /// [scaleFromCenter] Whether to scale from center instead of opposite anchor
  static TransformState applyScale({
    required TransformState state,
    required TransformHandle handle,
    required Offset startPosition,
    required Offset currentPosition,
    required TransformState startState,
    required bool maintainAspectRatio,
    bool scaleFromCenter = false,
  }) {
    if (!handle.isResize) return state;

    // Get the anchor point (opposite corner or center)
    final Offset anchor;
    if (scaleFromCenter) {
      anchor = startState.imageCenter;
    } else {
      anchor = handle.getAnchorPoint(startState) ?? startState.imageCenter;
    }

    // For corner handles or when maintaining aspect ratio
    if (handle.isCorner || maintainAspectRatio) {
      return _applyProportionalScale(
        startState: startState,
        startPosition: startPosition,
        currentPosition: currentPosition,
        anchor: anchor,
        scaleFromCenter: scaleFromCenter,
      );
    }

    // For edge handles without aspect ratio constraint
    return _applyEdgeScale(
      startState: startState,
      handle: handle,
      startPosition: startPosition,
      currentPosition: currentPosition,
      anchor: anchor,
    );
  }

  /// Apply proportional (uniform) scaling
  static TransformState _applyProportionalScale({
    required TransformState startState,
    required Offset startPosition,
    required Offset currentPosition,
    required Offset anchor,
    required bool scaleFromCenter,
  }) {
    // Calculate distances from anchor
    final startDistance = (startPosition - anchor).distance;
    final currentDistance = (currentPosition - anchor).distance;

    // Avoid division by zero
    if (startDistance < 0.001) return startState;

    // Calculate scale ratio
    final scaleRatio = currentDistance / startDistance;
    final newScale = (startState.scale * scaleRatio).clamp(0.1, 10.0);

    if (scaleFromCenter) {
      // Simple scale change when scaling from center
      return startState.copyWith(scale: newScale);
    }

    // Adjust translation to keep anchor fixed
    return startState.withScaleAroundAnchor(newScale, anchor);
  }

  /// Apply non-uniform scaling from an edge handle.
  /// This is more complex as it changes aspect ratio.
  static TransformState _applyEdgeScale({
    required TransformState startState,
    required TransformHandle handle,
    required Offset startPosition,
    required Offset currentPosition,
    required Offset anchor,
  }) {
    // For edge-only scaling, we project the movement onto the edge normal
    // This is complex with rotation, so for now we'll use proportional scaling
    // but constrained to the edge direction

    final startDistance = (startPosition - anchor).distance;
    if (startDistance < 0.001) return startState;

    // Calculate signed distance along the edge normal
    final edgeDirection = _getEdgeDirection(handle, startState);

    final startProjected =
        _projectOntoDirection(startPosition - anchor, edgeDirection);
    final currentProjected =
        _projectOntoDirection(currentPosition - anchor, edgeDirection);

    if (startProjected.abs() < 0.001) return startState;

    final scaleRatio = currentProjected / startProjected;
    final newScale = (startState.scale * scaleRatio).clamp(0.1, 10.0);

    return startState.withScaleAroundAnchor(newScale, anchor);
  }

  /// Get the direction vector for an edge handle (perpendicular to the edge)
  static Offset _getEdgeDirection(
      TransformHandle handle, TransformState state) {
    final rotRad = state.rotationRadians;
    final cosR = cos(rotRad);
    final sinR = sin(rotRad);

    switch (handle) {
      case TransformHandle.topCenter:
      case TransformHandle.bottomCenter:
        // Vertical direction (perpendicular to horizontal edges)
        return Offset(-sinR, cosR);
      case TransformHandle.leftCenter:
      case TransformHandle.rightCenter:
        // Horizontal direction (perpendicular to vertical edges)
        return Offset(cosR, sinR);
      default:
        return const Offset(1, 0);
    }
  }

  /// Project a vector onto a direction
  static double _projectOntoDirection(Offset vector, Offset direction) {
    return vector.dx * direction.dx + vector.dy * direction.dy;
  }

  /// Calculate new state after applying a rotation gesture.
  ///
  /// [startState] Transform state when gesture began
  /// [startPosition] Position where the gesture started
  /// [currentPosition] Current gesture position
  /// [pivot] Point to rotate around (default: image center)
  /// [snapToAngles] Whether to snap to 15-degree increments
  static TransformState applyRotation({
    required TransformState startState,
    required Offset startPosition,
    required Offset currentPosition,
    Offset? pivot,
    bool snapToAngles = false,
  }) {
    final pivotPoint = pivot ?? startState.imageCenter;

    // Calculate angles from pivot
    final startAngle = atan2(
      startPosition.dy - pivotPoint.dy,
      startPosition.dx - pivotPoint.dx,
    );
    final currentAngle = atan2(
      currentPosition.dy - pivotPoint.dy,
      currentPosition.dx - pivotPoint.dx,
    );

    // Calculate rotation delta in degrees
    var deltaRotation = (currentAngle - startAngle) * 180 / pi;
    var newRotation = startState.rotation + deltaRotation;

    // Normalize to -180 to 180
    while (newRotation > 180) {
      newRotation -= 360;
    }
    while (newRotation < -180) {
      newRotation += 360;
    }

    // Optional: Snap to 15-degree increments
    if (snapToAngles) {
      newRotation = (newRotation / 15).round() * 15.0;
    }

    return startState.withRotationAroundPivot(newRotation, pivotPoint);
  }

  /// Transform a point from canvas (widget) space to image-local space.
  ///
  /// Useful for determining where a click lands on the original image.
  static Offset canvasToImage(Offset point, TransformState state) {
    final center = state.imageCenter;

    // Undo rotation
    final cosR = cos(-state.rotationRadians);
    final sinR = sin(-state.rotationRadians);

    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;

    final rotatedX = dx * cosR - dy * sinR;
    final rotatedY = dx * sinR + dy * cosR;

    // Undo scale and center offset
    return Offset(
      rotatedX / state.scale + state.imageSize.width / 2,
      rotatedY / state.scale + state.imageSize.height / 2,
    );
  }

  /// Transform a point from image-local space to canvas (widget) space.
  static Offset imageToCanvas(Offset point, TransformState state) {
    final center = state.imageCenter;

    // Apply center offset and scale
    final scaledX = (point.dx - state.imageSize.width / 2) * state.scale;
    final scaledY = (point.dy - state.imageSize.height / 2) * state.scale;

    // Apply rotation
    final cosR = cos(state.rotationRadians);
    final sinR = sin(state.rotationRadians);

    final rotatedX = scaledX * cosR - scaledY * sinR;
    final rotatedY = scaledX * sinR + scaledY * cosR;

    return Offset(center.dx + rotatedX, center.dy + rotatedY);
  }

  /// Nudge translation by a fixed amount in screen space.
  static TransformState nudge(
    TransformState state,
    double dx,
    double dy,
  ) {
    return state.copyWith(
      translateX: state.translateX + dx,
      translateY: state.translateY + dy,
    );
  }

  /// Adjust rotation by a fixed amount.
  static TransformState adjustRotation(
    TransformState state,
    double deltaDegrees, {
    bool snapToAngles = false,
  }) {
    var newRotation = state.rotation + deltaDegrees;

    // Normalize
    while (newRotation > 180) {
      newRotation -= 360;
    }
    while (newRotation < -180) {
      newRotation += 360;
    }

    if (snapToAngles) {
      newRotation = (newRotation / 15).round() * 15.0;
    }

    return state.copyWith(rotation: newRotation);
  }

  /// Adjust scale by a percentage.
  static TransformState adjustScale(
    TransformState state,
    double deltaPercent, {
    bool fromCenter = true,
  }) {
    final currentScale = state.scale;
    final newScale = (currentScale * (1 + deltaPercent / 100)).clamp(0.1, 10.0);

    if (fromCenter) {
      return state.copyWith(scale: newScale);
    }

    // Scale from canvas center
    final canvasCenter = Offset(
      state.canvasSize.width / 2,
      state.canvasSize.height / 2,
    );
    return state.withScaleAroundAnchor(newScale, canvasCenter);
  }

  /// Reset transform to identity (centered, no rotation, scale = 1)
  static TransformState reset(TransformState state) {
    return TransformState.identity(
      imageSize: state.imageSize,
      canvasSize: state.canvasSize,
      baseScale: state.baseScale,
    );
  }

  /// Fit image to canvas (scale to fit, center, no rotation)
  static TransformState fitToCanvas(TransformState state) {
    return TransformState.identity(
      imageSize: state.imageSize,
      canvasSize: state.canvasSize,
      baseScale: state.baseScale,
    );
  }
}
