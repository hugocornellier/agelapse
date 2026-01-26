import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../styles/styles.dart';

/// Overlay widget that displays a countdown number during camera timer countdown
class CountdownOverlay extends StatelessWidget {
  final int countdownValue;
  final Animation<double> pulseAnimation;

  const CountdownOverlay({
    super.key,
    required this.countdownValue,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    // Smaller, less obtrusive countdown positioned above the shutter area
    final screenSize = MediaQuery.of(context).size;
    final shortestSide = screenSize.shortestSide;

    // Smaller size - doesn't block the face/camera view
    final circleSize = (shortestSide * 0.18).clamp(64.0, 100.0);
    final fontSize = (circleSize * 0.55).clamp(32.0, 56.0);
    final borderWidth = (circleSize * 0.04).clamp(2.0, 4.0);

    return Positioned(
      // Position above the shutter button area, not blocking the face
      bottom: 120,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: pulseAnimation.value,
              child: Container(
                width: circleSize,
                height: circleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.overlay.withValues(alpha: 0.7),
                  border: Border.all(
                    color: AppColors.textPrimary,
                    width: borderWidth,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.overlay.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '$countdownValue',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          blurRadius: 8,
                          color: AppColors.overlay,
                          offset: const Offset(1, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Custom painter for drawing a circular progress ring around the shutter button
class CountdownProgressPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final double strokeWidth;
  final Color color;
  final Color backgroundColor;

  CountdownProgressPainter({
    required this.progress,
    this.strokeWidth = 4,
    Color? color,
    Color? backgroundColor,
  })  : color = color ?? AppColors.textPrimary,
        backgroundColor = backgroundColor ?? const Color(0x4DFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background circle
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // Start from top
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(CountdownProgressPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth;
  }
}
