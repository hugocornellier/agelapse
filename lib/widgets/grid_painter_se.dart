import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class GridPainterSE extends CustomPainter {
  final double offsetX;
  final double offsetY;
  final double? ghostImageOffsetX;
  final double? ghostImageOffsetY;
  final ui.Image? guideImage;
  final String aspectRatio;
  final String projectOrientation;
  final bool hideToolTip;
  final bool hideCorners;
  final Color? backgroundColor;

  // Date stamp preview parameters
  final bool dateStampEnabled;
  final String? dateStampText;
  final String dateStampPosition;
  final int dateStampSizePercent;
  final double dateStampOpacity;
  final String dateStampFontFamily;
  final bool watermarkEnabled;
  final String? watermarkPosition;

  GridPainterSE(
    this.offsetX,
    this.offsetY,
    this.ghostImageOffsetX,
    this.ghostImageOffsetY,
    this.guideImage,
    this.aspectRatio,
    this.projectOrientation, {
    this.hideToolTip = false,
    this.hideCorners = false,
    this.backgroundColor,
    this.dateStampEnabled = false,
    this.dateStampText,
    this.dateStampPosition = 'lower right',
    this.dateStampSizePercent = 3,
    this.dateStampOpacity = 1.0,
    this.dateStampFontFamily = 'Inter',
    this.watermarkEnabled = false,
    this.watermarkPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Clip to canvas bounds to prevent guide image from spilling outside frame
    canvas.clipRect(Offset.zero & size);

    // Paint background color first (for areas not covered by the image)
    if (backgroundColor != null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = backgroundColor!,
      );
    }

    if (guideImage != null &&
        ghostImageOffsetX != null &&
        ghostImageOffsetY != null) {
      final imagePaint = Paint()
        ..color = Colors.white.withAlpha(242); // Equivalent to opacity 0.95
      final imageWidth = guideImage!.width.toDouble();
      final imageHeight = guideImage!.height.toDouble();
      final scale = _calculateImageScale(size.width, imageWidth, imageHeight);

      final scaledWidth = imageWidth * scale;
      final scaledHeight = imageHeight * scale;

      final eyeOffsetFromCenterInGhostPhoto =
          (0.5 - ghostImageOffsetY!) * scaledHeight;
      final eyeOffsetFromCenterGuideLines = (0.5 - offsetY) * size.height;
      final difference =
          eyeOffsetFromCenterGuideLines - eyeOffsetFromCenterInGhostPhoto;

      final rect = Rect.fromCenter(
        center: Offset(size.width / 2, (size.height / 2) - difference),
        width: scaledWidth,
        height: scaledHeight,
      );
      canvas.drawImageRect(
        guideImage!,
        Offset.zero & Size(imageWidth, imageHeight),
        rect,
        imagePaint,
      );
    }

    // Scale stroke width proportionally to canvas size so it looks consistent
    // when scaled down by FittedBox (2px at 1920px width as reference)
    final scaledStrokeWidth = size.width * 0.0015;

    final paint = Paint()
      ..color =
          Colors.lightBlueAccent.withAlpha(128) // Equivalent to opacity 0.5
      ..strokeWidth = scaledStrokeWidth.clamp(2.0, 20.0);

    final offsetXInPixels = size.width * offsetX;
    final centerX = size.width / 2;
    final leftX = centerX - offsetXInPixels;
    final rightX = centerX + offsetXInPixels;

    // Draw vertical grid lines
    canvas.drawLine(Offset(leftX, 0), Offset(leftX, size.height), paint);
    canvas.drawLine(Offset(rightX, 0), Offset(rightX, size.height), paint);

    final y = size.height * offsetY;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);

    // Draw corners
    if (!hideCorners) {
      final cornerPaint = Paint()
        ..color = const Color(0xff924904)
        ..strokeWidth = (scaledStrokeWidth * 1.25).clamp(2.5, 25.0)
        ..style = PaintingStyle.stroke;

      final double lineLength = 0.15 * size.width;

      canvas.drawLine(const Offset(0, 0), Offset(0, lineLength), cornerPaint);
      canvas.drawLine(const Offset(0, 0), Offset(lineLength, 0), cornerPaint);
      canvas.drawLine(
        Offset(size.width, 0),
        Offset(size.width, lineLength),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(size.width, 0),
        Offset(size.width - lineLength, 0),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(0, size.height),
        Offset(0, size.height - lineLength),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(0, size.height),
        Offset(lineLength, size.height),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(size.width, size.height),
        Offset(size.width, size.height - lineLength),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(size.width, size.height),
        Offset(size.width - lineLength, size.height),
        cornerPaint,
      );
    }

    // Draw date stamp preview (if enabled and has text)
    if (dateStampEnabled &&
        dateStampText != null &&
        dateStampText!.isNotEmpty) {
      _paintDateStamp(canvas, size);
    }

    if (!hideToolTip) {
      // Draw text background rectangle
      final textBackgroundPaint = Paint()
        ..color = Colors.black.withAlpha(230) // Equivalent to opacity 0.9
        ..style = PaintingStyle.fill;

      const textPadding = 8.0;
      final text =
          'Inter-Eye Distance: ${(offsetX * 2 * 100).toStringAsFixed(2)} %\n'
          'Vertical Offset: ${(offsetY * 100).toStringAsFixed(2)} %';

      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(minWidth: 0, maxWidth: size.width);

      final textRect = Rect.fromLTWH(
        10,
        10,
        textPainter.width + textPadding * 2,
        textPainter.height + textPadding * 2,
      );

      // Draw rounded rectangle
      final rrect = RRect.fromRectAndRadius(textRect, const Radius.circular(8));
      canvas.drawRRect(rrect, textBackgroundPaint);

      // Draw text on top of the rectangle
      textPainter.paint(
        canvas,
        const Offset(10 + textPadding, 10 + textPadding),
      );
      textPainter.dispose();
    }
  }

  void _paintDateStamp(Canvas canvas, Size size) {
    // Calculate font size (percentage of canvas height, matching export formula)
    final fontSize =
        (size.height * dateStampSizePercent / 100).clamp(8.0, 48.0);

    // Create text painter matching DateStampUtils.getExportTextStyle
    final textPainter = TextPainter(
      text: TextSpan(
        text: dateStampText,
        style: TextStyle(
          fontFamily: dateStampFontFamily,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: dateStampOpacity),
          shadows: [
            Shadow(
              offset: const Offset(1, 1),
              blurRadius: 2,
              color: Colors.black.withValues(alpha: dateStampOpacity * 0.8),
            ),
            Shadow(
              offset: const Offset(-1, -1),
              blurRadius: 2,
              color: Colors.black.withValues(alpha: dateStampOpacity * 0.5),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: size.width * 0.8);

    // Calculate position with 2% margin
    final marginX = size.width * 0.02;
    final marginY = size.height * 0.02;

    double x, y;
    switch (dateStampPosition.toLowerCase()) {
      case 'lower right':
        x = size.width - textPainter.width - marginX;
        y = size.height - textPainter.height - marginY;
      case 'lower left':
        x = marginX;
        y = size.height - textPainter.height - marginY;
      case 'upper right':
        x = size.width - textPainter.width - marginX;
        y = marginY;
      case 'upper left':
        x = marginX;
        y = marginY;
        // Offset below tooltip if tooltip is visible
        if (!hideToolTip) {
          y += size.height * 0.08;
        }
      default:
        x = size.width - textPainter.width - marginX;
        y = size.height - textPainter.height - marginY;
    }

    // Apply watermark collision offset if both in same position
    if (watermarkEnabled &&
        watermarkPosition != null &&
        dateStampPosition.toLowerCase() == watermarkPosition!.toLowerCase()) {
      final isLower = dateStampPosition.toLowerCase().contains('lower');
      final offset = size.height * 0.06;
      y += isLower ? -offset : offset;
    }

    // Background padding (matching image_preview_navigator style)
    const paddingH = 8.0;
    const paddingV = 4.0;

    // Draw semi-transparent background pill
    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5 * dateStampOpacity)
      ..style = PaintingStyle.fill;

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        x - paddingH,
        y - paddingV,
        textPainter.width + paddingH * 2,
        textPainter.height + paddingV * 2,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(bgRect, backgroundPaint);

    // Draw text
    textPainter.paint(canvas, Offset(x, y));
    textPainter.dispose();
  }

  double _calculateImageScale(
    double canvasWidth,
    double imageWidth,
    double imageHeight,
  ) {
    return (canvasWidth * offsetX) / (imageWidth * ghostImageOffsetX!);
  }

  @override
  bool shouldRepaint(covariant GridPainterSE oldDelegate) {
    return offsetX != oldDelegate.offsetX ||
        offsetY != oldDelegate.offsetY ||
        ghostImageOffsetX != oldDelegate.ghostImageOffsetX ||
        ghostImageOffsetY != oldDelegate.ghostImageOffsetY ||
        guideImage != oldDelegate.guideImage ||
        aspectRatio != oldDelegate.aspectRatio ||
        projectOrientation != oldDelegate.projectOrientation ||
        hideToolTip != oldDelegate.hideToolTip ||
        hideCorners != oldDelegate.hideCorners ||
        backgroundColor != oldDelegate.backgroundColor ||
        dateStampEnabled != oldDelegate.dateStampEnabled ||
        dateStampText != oldDelegate.dateStampText ||
        dateStampPosition != oldDelegate.dateStampPosition ||
        dateStampSizePercent != oldDelegate.dateStampSizePercent ||
        dateStampOpacity != oldDelegate.dateStampOpacity ||
        dateStampFontFamily != oldDelegate.dateStampFontFamily ||
        watermarkEnabled != oldDelegate.watermarkEnabled ||
        watermarkPosition != oldDelegate.watermarkPosition;
  }
}
