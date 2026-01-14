import 'dart:math';
import 'dart:ui';

/// Immutable state object representing a 2D image transform.
///
/// Contains translation, scale, rotation, and pivot point data,
/// along with computed properties for the transform matrix and
/// bounding box calculations.
class TransformState {
  /// Horizontal offset in canvas pixels
  final double translateX;

  /// Vertical offset in canvas pixels
  final double translateY;

  /// Scale multiplier (1.0 = original size after fitting to canvas)
  final double scale;

  /// Rotation in degrees (positive = clockwise)
  final double rotation;

  /// Rotation/scale pivot point in canvas coordinates
  /// Defaults to image center
  final Offset pivot;

  /// Original image size (before any transforms)
  final Size imageSize;

  /// Canvas/viewport size
  final Size canvasSize;

  /// Base scale factor (ratio to fit raw image to canvas)
  /// Used for converting between UI scale and actual render scale
  final double baseScale;

  const TransformState({
    required this.translateX,
    required this.translateY,
    required this.scale,
    required this.rotation,
    required this.pivot,
    required this.imageSize,
    required this.canvasSize,
    this.baseScale = 1.0,
  });

  /// The effective scale factor for rendering (scale * baseScale)
  double get effectiveScale => scale * baseScale;

  /// Create identity transform (image centered, no rotation, scale to fit)
  factory TransformState.identity({
    required Size imageSize,
    required Size canvasSize,
    double baseScale = 1.0,
  }) {
    return TransformState(
      translateX: 0,
      translateY: 0,
      scale: 1.0,
      rotation: 0,
      pivot: Offset(canvasSize.width / 2, canvasSize.height / 2),
      imageSize: imageSize,
      canvasSize: canvasSize,
      baseScale: baseScale,
    );
  }

  /// Create transform state from database values
  factory TransformState.fromDatabaseValues({
    required double translateX,
    required double translateY,
    required double scaleFactor,
    required double rotationDegrees,
    required Size imageSize,
    required Size canvasSize,
    required double baseScale,
  }) {
    // Convert stored scale factor (multiplier) to actual scale
    final scale = scaleFactor / baseScale;

    return TransformState(
      translateX: translateX,
      translateY: translateY,
      scale: scale,
      rotation: rotationDegrees,
      pivot: Offset(canvasSize.width / 2, canvasSize.height / 2),
      imageSize: imageSize,
      canvasSize: canvasSize,
      baseScale: baseScale,
    );
  }

  /// Rotation in radians
  double get rotationRadians => rotation * pi / 180;

  /// The center point of the image in canvas space (after translation)
  Offset get imageCenter => Offset(
        canvasSize.width / 2 + translateX,
        canvasSize.height / 2 + translateY,
      );

  /// The effective size of the image after scaling (for visual rendering)
  Size get scaledImageSize => Size(
        imageSize.width * effectiveScale,
        imageSize.height * effectiveScale,
      );

  /// Get the four corners of the transformed image in canvas space.
  /// Order: top-left, top-right, bottom-right, bottom-left
  List<Offset> get corners {
    final halfWidth = scaledImageSize.width / 2;
    final halfHeight = scaledImageSize.height / 2;
    final center = imageCenter;

    // Corners relative to center (before rotation)
    final localCorners = [
      Offset(-halfWidth, -halfHeight), // top-left
      Offset(halfWidth, -halfHeight), // top-right
      Offset(halfWidth, halfHeight), // bottom-right
      Offset(-halfWidth, halfHeight), // bottom-left
    ];

    // Rotate each corner around the center
    final cosR = cos(rotationRadians);
    final sinR = sin(rotationRadians);

    return localCorners.map((corner) {
      final rotatedX = corner.dx * cosR - corner.dy * sinR;
      final rotatedY = corner.dx * sinR + corner.dy * cosR;
      return Offset(center.dx + rotatedX, center.dy + rotatedY);
    }).toList();
  }

  /// Get the axis-aligned bounding box that contains the rotated image
  Rect get boundingBox {
    final c = corners;
    final minX = c.map((p) => p.dx).reduce(min);
    final maxX = c.map((p) => p.dx).reduce(max);
    final minY = c.map((p) => p.dy).reduce(min);
    final maxY = c.map((p) => p.dy).reduce(max);
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Get the midpoint of each edge.
  /// Order: top, right, bottom, left
  List<Offset> get edgeMidpoints {
    final c = corners;
    return [
      Offset((c[0].dx + c[1].dx) / 2, (c[0].dy + c[1].dy) / 2), // top
      Offset((c[1].dx + c[2].dx) / 2, (c[1].dy + c[2].dy) / 2), // right
      Offset((c[2].dx + c[3].dx) / 2, (c[2].dy + c[3].dy) / 2), // bottom
      Offset((c[3].dx + c[0].dx) / 2, (c[3].dy + c[0].dy) / 2), // left
    ];
  }

  /// Get the position for the rotation handle (above top edge midpoint)
  Offset getRotationHandlePosition(double distance) {
    final topMid = edgeMidpoints[0];
    final center = imageCenter;

    // Direction from center to top midpoint
    final direction = topMid - center;
    final normalized = direction / direction.distance;

    // Extend beyond the top edge
    return topMid + normalized * distance;
  }

  /// Create a copy with updated values
  TransformState copyWith({
    double? translateX,
    double? translateY,
    double? scale,
    double? rotation,
    Offset? pivot,
    Size? imageSize,
    Size? canvasSize,
    double? baseScale,
  }) {
    return TransformState(
      translateX: translateX ?? this.translateX,
      translateY: translateY ?? this.translateY,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      pivot: pivot ?? this.pivot,
      imageSize: imageSize ?? this.imageSize,
      canvasSize: canvasSize ?? this.canvasSize,
      baseScale: baseScale ?? this.baseScale,
    );
  }

  /// Apply a translation delta
  TransformState withTranslation(Offset delta) {
    return copyWith(
      translateX: translateX + delta.dx,
      translateY: translateY + delta.dy,
    );
  }

  /// Apply a new scale value, adjusting translation to keep anchor fixed
  TransformState withScaleAroundAnchor(double newScale, Offset anchor) {
    // Calculate current position of anchor in image-local space
    final center = imageCenter;
    final anchorLocal = _rotatePointAroundCenter(
      anchor,
      center,
      -rotationRadians,
    );

    // Position relative to center
    final relX = (anchorLocal.dx - center.dx) / scale;
    final relY = (anchorLocal.dy - center.dy) / scale;

    // After scale change, where would the anchor be?
    final newRelX = relX * newScale;
    final newRelY = relY * newScale;

    // Rotate back
    final cosR = cos(rotationRadians);
    final sinR = sin(rotationRadians);
    final rotatedRelX = newRelX * cosR - newRelY * sinR;
    final rotatedRelY = newRelX * sinR + newRelY * cosR;

    // Calculate translation adjustment to keep anchor fixed
    final newCenterX = anchor.dx - rotatedRelX;
    final newCenterY = anchor.dy - rotatedRelY;

    return copyWith(
      scale: newScale,
      translateX: newCenterX - canvasSize.width / 2,
      translateY: newCenterY - canvasSize.height / 2,
    );
  }

  /// Apply a new rotation value, adjusting translation to keep pivot fixed
  TransformState withRotationAroundPivot(
      double newRotation, Offset pivotPoint) {
    final center = imageCenter;
    final oldRotRad = rotationRadians;
    final newRotRad = newRotation * pi / 180;

    // Vector from pivot to current center
    final dx = center.dx - pivotPoint.dx;
    final dy = center.dy - pivotPoint.dy;

    // Rotate this vector by the rotation delta
    final deltaRot = newRotRad - oldRotRad;
    final cosD = cos(deltaRot);
    final sinD = sin(deltaRot);

    final newDx = dx * cosD - dy * sinD;
    final newDy = dx * sinD + dy * cosD;

    // New center position
    final newCenterX = pivotPoint.dx + newDx;
    final newCenterY = pivotPoint.dy + newDy;

    return copyWith(
      rotation: newRotation,
      translateX: newCenterX - canvasSize.width / 2,
      translateY: newCenterY - canvasSize.height / 2,
    );
  }

  /// Rotate a point around a center by given radians
  Offset _rotatePointAroundCenter(Offset point, Offset center, double radians) {
    final cosR = cos(radians);
    final sinR = sin(radians);
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    return Offset(
      center.dx + dx * cosR - dy * sinR,
      center.dy + dx * sinR + dy * cosR,
    );
  }

  /// Check if a point is inside the transformed image bounds
  bool containsPoint(Offset point) {
    // Transform point to local image space (undo rotation around center)
    final center = imageCenter;
    final localPoint =
        _rotatePointAroundCenter(point, center, -rotationRadians);

    // Check if within scaled image bounds centered at imageCenter
    final halfW = scaledImageSize.width / 2;
    final halfH = scaledImageSize.height / 2;

    return localPoint.dx >= center.dx - halfW &&
        localPoint.dx <= center.dx + halfW &&
        localPoint.dy >= center.dy - halfH &&
        localPoint.dy <= center.dy + halfH;
  }

  /// Convert to database values for storage
  Map<String, double> toDatabaseValues(double baseScale) {
    return {
      'translateX': translateX,
      'translateY': translateY,
      'scaleFactor': scale * baseScale,
      'rotationDegrees': rotation,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TransformState &&
        other.translateX == translateX &&
        other.translateY == translateY &&
        other.scale == scale &&
        other.rotation == rotation &&
        other.pivot == pivot &&
        other.imageSize == imageSize &&
        other.canvasSize == canvasSize &&
        other.baseScale == baseScale;
  }

  @override
  int get hashCode => Object.hash(
        translateX,
        translateY,
        scale,
        rotation,
        pivot,
        imageSize,
        canvasSize,
        baseScale,
      );

  @override
  String toString() {
    return 'TransformState(tx: $translateX, ty: $translateY, scale: $scale, rotation: $rotation)';
  }
}
