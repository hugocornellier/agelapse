import 'package:flutter/material.dart';

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cellWidth = size.width / 3;
    final double cellHeight = size.height / 3;

    final paint = Paint()
      ..color = Colors.white.withAlpha(128) // Equivalent to opacity 0.5
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw vertical lines
    const int offset = 40;
    drawVerticalLine(canvas, cellWidth + offset, size.height, paint, 1);
    drawVerticalLine(canvas, (cellWidth * 2) - offset, size.height, paint, 1);

    // Draw horizontal line
    final dy = cellHeight + cellHeight * 0.3;
    canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
  }

  void drawVerticalLine(
      Canvas canvas, double dx, double height, Paint paint, int index) {
    canvas.drawLine(Offset(dx * index, 0), Offset(dx * index, height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
