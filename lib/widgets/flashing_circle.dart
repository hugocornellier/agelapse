import 'package:flutter/material.dart';

class FlashingCircle extends StatefulWidget {
  final double diameter;
  final Offset position;

  const FlashingCircle({
    super.key, 
    required this.diameter, 
    required this.position
  });

  @override
  FlashingCircleState createState() => FlashingCircleState();
}

class FlashingCircleState extends State<FlashingCircle> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          left: widget.position.dx - widget.diameter / 2,
          top: widget.position.dy - widget.diameter / 2,
          child: Container(
            width: widget.diameter,
            height: widget.diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue.withAlpha(128 + (128 * _controller.value).round()), // Equivalent to opacity 0.5-1.0 range
            ),
          ),
        );
      },
    );
  }
}
