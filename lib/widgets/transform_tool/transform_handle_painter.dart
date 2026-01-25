import 'dart:math';
import 'package:flutter/material.dart';

import '../../styles/styles.dart';
import 'transform_handle.dart';
import 'transform_state.dart';

/// CustomPainter that draws the transform bounding box and handles.
///
/// This renders:
/// - The rotated bounding box outline
/// - Resize handles at corners and edge midpoints
/// - Rotation handle above the top edge
/// - Connection line from top edge to rotation handle
/// - Optional pivot point indicator
class TransformHandlePainter extends CustomPainter {
  final TransformState state;
  final TransformHandle? activeHandle;
  final TransformHandle? hoveredHandle;
  final bool showRotationHandle;
  final bool showPivotPoint;
  final bool showCornerHandles;
  final bool showEdgeHandles;

  /// Scale factor from canvas resolution to display size.
  /// Used to counter-scale handle sizes so they appear consistent on screen
  /// regardless of canvas resolution (e.g., 1080p vs 8K).
  ///
  /// displayScale = previewWidth / canvasWidth
  /// - If < 1: preview is smaller than canvas, handles drawn larger
  /// - If > 1: preview is larger than canvas, handles drawn smaller
  /// - If = 1: no scaling needed
  final double displayScale;

  // Visual configuration
  final Color boundingBoxColor;
  final Color handleFillColor;
  final Color handleStrokeColor;
  final Color handleActiveColor;
  final Color handleHoverColor;
  final Color rotationHandleColor;
  final Color pivotColor;
  final double boundingBoxWidth;
  final double handleSize;
  final double edgeHandleSize;
  final double rotationHandleSize;
  final double rotationHandleDistance;
  final double handleStrokeWidth;

  TransformHandlePainter({
    required this.state,
    this.activeHandle,
    this.hoveredHandle,
    this.showRotationHandle = true,
    this.showPivotPoint = false,
    this.showCornerHandles = true,
    this.showEdgeHandles = true,
    this.displayScale = 1.0,
    this.boundingBoxColor = const Color(0xB3FFFFFF), // White at 70% opacity
    this.handleFillColor = const Color(0xFFFFFFFF),
    this.handleStrokeColor = const Color(0xFF333333), // Dark gray border
    this.handleActiveColor = const Color(0xFF1976D2), // Darker blue when active
    this.handleHoverColor = const Color(0xFF2196F3), // Light blue on hover
    this.rotationHandleColor = const Color(0xFF333333), // Dark gray
    this.pivotColor = const Color(0xFFFF9800),
    this.boundingBoxWidth = 1.0,
    this.handleSize = 10.0,
    this.edgeHandleSize = 8.0,
    this.rotationHandleSize = 12.0,
    this.rotationHandleDistance = 30.0,
    this.handleStrokeWidth = 1.5,
  });

  // Effective sizes after counter-scaling for display
  double get _effectiveHandleSize => handleSize / displayScale;
  double get _effectiveEdgeHandleSize => edgeHandleSize / displayScale;
  double get _effectiveRotationHandleSize => rotationHandleSize / displayScale;
  double get _effectiveRotationHandleDistance =>
      rotationHandleDistance / displayScale;
  double get _effectiveBoundingBoxWidth => boundingBoxWidth / displayScale;
  double get _effectiveHandleStrokeWidth => handleStrokeWidth / displayScale;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw in order: bounding box, handles, rotation handle, pivot
    _drawBoundingBox(canvas);
    _drawRotationConnector(canvas);
    _drawResizeHandles(canvas);
    if (showRotationHandle) {
      _drawRotationHandle(canvas);
    }
    if (showPivotPoint) {
      _drawPivotPoint(canvas);
    }
  }

  void _drawBoundingBox(Canvas canvas) {
    final corners = state.corners;

    final paint = Paint()
      ..color = boundingBoxColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _effectiveBoundingBoxWidth;

    final path = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    canvas.drawPath(path, paint);
  }

  void _drawResizeHandles(Canvas canvas) {
    final corners = state.corners;
    final edges = state.edgeMidpoints;

    // Draw corner handles (squares)
    if (showCornerHandles) {
      for (int i = 0; i < cornerHandles.length; i++) {
        final handle = cornerHandles[i];
        final position = corners[i];
        final isActive = activeHandle == handle;
        final isHovered = hoveredHandle == handle;

        _drawSquareHandle(
          canvas,
          position,
          _effectiveHandleSize,
          isActive: isActive,
          isHovered: isHovered,
          rotation: state.rotationRadians,
        );
      }
    }

    // Draw edge handles (circles)
    if (showEdgeHandles) {
      for (int i = 0; i < edgeHandles.length; i++) {
        final handle = edgeHandles[i];
        final position = edges[i];
        final isActive = activeHandle == handle;
        final isHovered = hoveredHandle == handle;

        _drawCircleHandle(
          canvas,
          position,
          _effectiveEdgeHandleSize / 2,
          isActive: isActive,
          isHovered: isHovered,
        );
      }
    }
  }

  void _drawSquareHandle(
    Canvas canvas,
    Offset center,
    double size, {
    bool isActive = false,
    bool isHovered = false,
    double rotation = 0,
  }) {
    final halfSize = (isActive ? size * 1.2 : size) / 2;

    // Determine colors based on state
    final fillColor = isActive
        ? handleActiveColor
        : (isHovered ? handleHoverColor : handleFillColor);
    final strokeColor =
        isActive ? handleActiveColor.withValues(alpha: 1.0) : handleStrokeColor;

    // Create rotated square path
    final path = Path();
    final corners = <Offset>[];

    for (int i = 0; i < 4; i++) {
      final angle = rotation + (i * pi / 2) + (pi / 4);
      final dist = halfSize * sqrt(2);
      corners.add(Offset(
        center.dx + cos(angle) * dist,
        center.dy + sin(angle) * dist,
      ));
    }

    path.moveTo(corners[0].dx, corners[0].dy);
    for (int i = 1; i < 4; i++) {
      path.lineTo(corners[i].dx, corners[i].dy);
    }
    path.close();

    // Draw shadow for depth
    final shadowPath = Path();
    final shadowOffset = const Offset(1, 1);
    final shadowCorners = corners.map((c) => c + shadowOffset).toList();
    shadowPath.moveTo(shadowCorners[0].dx, shadowCorners[0].dy);
    for (int i = 1; i < 4; i++) {
      shadowPath.lineTo(shadowCorners[i].dx, shadowCorners[i].dy);
    }
    shadowPath.close();
    canvas.drawPath(
      shadowPath,
      Paint()
        ..color = AppColors.overlay.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Draw fill
    canvas.drawPath(
      path,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );

    // Draw stroke
    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _effectiveHandleStrokeWidth,
    );
  }

  void _drawCircleHandle(
    Canvas canvas,
    Offset center,
    double radius, {
    bool isActive = false,
    bool isHovered = false,
  }) {
    final actualRadius = isActive ? radius * 1.2 : radius;

    // Determine colors based on state
    final fillColor = isActive
        ? handleActiveColor
        : (isHovered ? handleHoverColor : handleFillColor);
    final strokeColor =
        isActive ? handleActiveColor.withValues(alpha: 1.0) : handleStrokeColor;

    // Draw shadow for depth
    canvas.drawCircle(
      center + const Offset(1, 1),
      actualRadius,
      Paint()
        ..color = AppColors.overlay.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Draw fill
    canvas.drawCircle(
      center,
      actualRadius,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );

    // Draw stroke
    canvas.drawCircle(
      center,
      actualRadius,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _effectiveHandleStrokeWidth,
    );
  }

  void _drawRotationConnector(Canvas canvas) {
    if (!showRotationHandle) return;

    final topMidpoint = state.edgeMidpoints[0];
    final rotationHandlePos =
        state.getRotationHandlePosition(_effectiveRotationHandleDistance);

    final paint = Paint()
      ..color = const Color(0x99666666) // Subtle gray at 60% opacity
      ..style = PaintingStyle.stroke
      ..strokeWidth = _effectiveBoundingBoxWidth;

    // Draw solid line connector
    canvas.drawLine(topMidpoint, rotationHandlePos, paint);
  }

  void _drawRotationHandle(Canvas canvas) {
    final position =
        state.getRotationHandlePosition(_effectiveRotationHandleDistance);
    final isActive = activeHandle == TransformHandle.rotationHandle;
    final isHovered = hoveredHandle == TransformHandle.rotationHandle;

    final baseSize = _effectiveRotationHandleSize;
    final radius = (isActive ? baseSize * 1.2 : baseSize) / 2;

    // Determine colors
    final fillColor = isActive
        ? handleActiveColor
        : (isHovered ? handleHoverColor : handleFillColor);
    final strokeColor = isActive
        ? handleActiveColor.withValues(alpha: 1.0)
        : rotationHandleColor;

    // Draw shadow for depth
    canvas.drawCircle(
      position + const Offset(1, 1),
      radius,
      Paint()
        ..color = AppColors.overlay.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Draw outer circle fill
    canvas.drawCircle(
      position,
      radius,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );

    // Draw outer circle stroke
    canvas.drawCircle(
      position,
      radius,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _effectiveHandleStrokeWidth,
    );

    // Draw rotation icon (curved arrow)
    _drawRotationIcon(canvas, position, radius * 0.6, strokeColor);
  }

  void _drawRotationIcon(
      Canvas canvas, Offset center, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _effectiveHandleStrokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw a small curved arrow
    final path = Path();

    // Arc
    final rect = Rect.fromCircle(center: center, radius: size);
    path.addArc(rect, -pi * 0.7, pi * 1.2);

    canvas.drawPath(path, paint);

    // Arrow head
    final arrowTip = Offset(
      center.dx + size * cos(pi * 0.5),
      center.dy + size * sin(pi * 0.5),
    );

    final arrowSize = size * 0.5;
    final arrowAngle = pi * 0.5 + pi * 0.15;

    canvas.drawLine(
      arrowTip,
      Offset(
        arrowTip.dx + arrowSize * cos(arrowAngle + pi * 0.7),
        arrowTip.dy + arrowSize * sin(arrowAngle + pi * 0.7),
      ),
      paint,
    );

    canvas.drawLine(
      arrowTip,
      Offset(
        arrowTip.dx + arrowSize * cos(arrowAngle - pi * 0.3),
        arrowTip.dy + arrowSize * sin(arrowAngle - pi * 0.3),
      ),
      paint,
    );
  }

  void _drawPivotPoint(Canvas canvas) {
    final pivot = state.pivot;
    final size = 6.0 / displayScale;

    final paint = Paint()
      ..color = pivotColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _effectiveHandleStrokeWidth;

    // Draw crosshair
    canvas.drawLine(
      Offset(pivot.dx - size, pivot.dy),
      Offset(pivot.dx + size, pivot.dy),
      paint,
    );
    canvas.drawLine(
      Offset(pivot.dx, pivot.dy - size),
      Offset(pivot.dx, pivot.dy + size),
      paint,
    );

    // Draw center circle
    canvas.drawCircle(pivot, 3.0 / displayScale, paint);
  }

  @override
  bool shouldRepaint(TransformHandlePainter oldDelegate) {
    return state != oldDelegate.state ||
        activeHandle != oldDelegate.activeHandle ||
        hoveredHandle != oldDelegate.hoveredHandle ||
        showRotationHandle != oldDelegate.showRotationHandle ||
        showPivotPoint != oldDelegate.showPivotPoint ||
        showCornerHandles != oldDelegate.showCornerHandles ||
        showEdgeHandles != oldDelegate.showEdgeHandles ||
        displayScale != oldDelegate.displayScale;
  }
}

/// A lighter painter that only draws the bounding box outline.
/// Useful for preview-only scenarios where handles aren't needed.
class TransformBoundingBoxPainter extends CustomPainter {
  final TransformState state;
  final Color color;
  final double strokeWidth;
  final bool dashed;

  TransformBoundingBoxPainter({
    required this.state,
    this.color = const Color(0xFF2196F3),
    this.strokeWidth = 1.5,
    this.dashed = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final corners = state.corners;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    if (dashed) {
      // Draw dashed lines between corners
      for (int i = 0; i < 4; i++) {
        final start = corners[i];
        final end = corners[(i + 1) % 4];
        _drawDashedLine(canvas, start, end, paint);
      }
    } else {
      final path = Path()
        ..moveTo(corners[0].dx, corners[0].dy)
        ..lineTo(corners[1].dx, corners[1].dy)
        ..lineTo(corners[2].dx, corners[2].dy)
        ..lineTo(corners[3].dx, corners[3].dy)
        ..close();

      canvas.drawPath(path, paint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 5.0;
    const gapLength = 3.0;

    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = sqrt(dx * dx + dy * dy);

    if (distance < 0.001) return;

    final unitX = dx / distance;
    final unitY = dy / distance;

    var drawn = 0.0;
    var drawing = true;

    while (drawn < distance) {
      final segmentLength = drawing ? dashLength : gapLength;
      final remaining = distance - drawn;
      final actualLength = min(segmentLength, remaining);

      if (drawing) {
        canvas.drawLine(
          Offset(start.dx + unitX * drawn, start.dy + unitY * drawn),
          Offset(
            start.dx + unitX * (drawn + actualLength),
            start.dy + unitY * (drawn + actualLength),
          ),
          paint,
        );
      }

      drawn += actualLength;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(TransformBoundingBoxPainter oldDelegate) {
    return state != oldDelegate.state ||
        color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        dashed != oldDelegate.dashed;
  }
}
