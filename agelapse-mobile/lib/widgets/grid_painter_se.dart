import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
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

  GridPainterSE(
    this.offsetX,
    this.offsetY,
    this.ghostImageOffsetX,
    this.ghostImageOffsetY,
    this.guideImage,
    this.aspectRatio,
    this.projectOrientation,
    {this.hideToolTip = false}
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (guideImage != null && ghostImageOffsetX != null && ghostImageOffsetY != null) {
      final imagePaint = Paint()..color = Colors.white.withOpacity(0.95);
      final imageWidth = guideImage!.width.toDouble();
      final imageHeight = guideImage!.height.toDouble();
      final scale = _calculateImageScale(size.width, imageWidth, imageHeight);

      final scaledWidth = imageWidth * scale;
      final scaledHeight = imageHeight * scale;

      final eyeOffsetFromCenterInGhostPhoto = (0.5 - ghostImageOffsetY!) * scaledHeight;
      final eyeOffsetFromCenterGuideLines = (0.5 - offsetY) * size.height;
      final difference = eyeOffsetFromCenterGuideLines - eyeOffsetFromCenterInGhostPhoto;

      final rect = Rect.fromCenter(
        center: Offset(size.width / 2, (size.height / 2) - difference),
        width: scaledWidth,
        height: scaledHeight,
      );
      canvas.drawImageRect(guideImage!, Offset.zero & Size(imageWidth, imageHeight), rect, imagePaint);
    }

    final paint = Paint()
      ..color = Colors.lightBlueAccent.withOpacity(0.5)
      ..strokeWidth = 2;

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
    final cornerPaint = Paint()
      ..color = const Color(0xff924904)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final double lineLength = 0.15 * size.width;

    canvas.drawLine(const Offset(0, 0), Offset(0, lineLength), cornerPaint);
    canvas.drawLine(const Offset(0, 0), Offset(lineLength, 0), cornerPaint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, lineLength), cornerPaint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - lineLength, 0), cornerPaint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - lineLength), cornerPaint);
    canvas.drawLine(Offset(0, size.height), Offset(lineLength, size.height), cornerPaint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - lineLength), cornerPaint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - lineLength, size.height), cornerPaint);

    if (!hideToolTip) {
      // Draw text background rectangle
      final textBackgroundPaint = Paint()
        ..color = Colors.black.withOpacity(0.9)
        ..style = PaintingStyle.fill;

      const textPadding = 8.0;
      final text = 'Inter-Eye Distance: ${(offsetX * 2 * 100).toStringAsFixed(2)} %\n'
          'Vertical Offset: ${(offsetY * 100).toStringAsFixed(2)} %';

      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
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
      textPainter.paint(canvas, const Offset(10 + textPadding, 10 + textPadding));
    }
  }

  double _calculateImageScale(double canvasWidth, double imageWidth, double imageHeight) {
    return (canvasWidth * offsetX) / (imageWidth * ghostImageOffsetX!);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
