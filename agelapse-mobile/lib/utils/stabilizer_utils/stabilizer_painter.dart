import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class StabilizerPainter extends CustomPainter {
  final ui.Image? image;
  final double rotationAngle;
  final double scaleFactor;
  final double translateX;
  final double translateY;

  StabilizerPainter({
    this.image,
    required this.rotationAngle,
    required this.scaleFactor,
    required this.translateX,
    required this.translateY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) return;

    // print("Painting... translateX: $translateX, translateY: $translateY, scaleFactor: $scaleFactor, rotationAngle: $rotationAngle");

    // Translate
    canvas.save();
    canvas.translate(translateX, translateY);

    // Rotate
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotationAngle * (pi / 180));
    canvas.translate(-size.width / 2, -size.height / 2);

    // Paint the image using paintImage
    paintImage(
      canvas: canvas,
      image: image!,
      fit: BoxFit.fill,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      rect: Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: image!.width * scaleFactor,     // Scaling occurs here
        height: image!.height * scaleFactor    //     (and here)
      ),
    );

    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is StabilizerPainter && (oldDelegate.image != image || oldDelegate.rotationAngle != rotationAngle || oldDelegate.scaleFactor != scaleFactor || oldDelegate.translateX != translateX || oldDelegate.translateY != translateY);
  }
}
