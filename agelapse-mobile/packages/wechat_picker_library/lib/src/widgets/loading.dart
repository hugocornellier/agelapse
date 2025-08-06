// Copyright 2019 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A loading indicator in WeChat style.
final class LoadingIndicator extends StatefulWidget {
  const LoadingIndicator({super.key, required this.tip});

  final String tip;

  @override
  State<LoadingIndicator> createState() => _LoadingIndicatorState();
}

final class _LoadingIndicatorState extends State<LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(seconds: 2),
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildContent(BuildContext context, double minWidth) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox.fromSize(
          size: Size.square(minWidth / 3),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, Widget? child) => Transform.rotate(
              angle: math.pi * 2 * _controller.value,
              child: child,
            ),
            child: CustomPaint(
              painter: _LoadingIndicatorPainter(
                Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ),
        ),
        SizedBox(height: minWidth / 10),
        Text(widget.tip, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final double minWidth = MediaQuery.of(context).size.shortestSide / 3;
    return Container(
      color: Colors.black38,
      alignment: Alignment.center,
      child: RepaintBoundary(
        child: Container(
          constraints: BoxConstraints(minWidth: minWidth),
          padding: EdgeInsets.all(minWidth / 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Theme.of(context).canvasColor,
          ),
          child: _buildContent(context, minWidth),
        ),
      ),
    );
  }
}

final class _LoadingIndicatorPainter extends CustomPainter {
  const _LoadingIndicatorPainter(this.activeColor);

  final Color? activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Color color = activeColor ?? Colors.white;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final Rect rect = Rect.fromCenter(
      center: center,
      width: size.width,
      height: size.height,
    );
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..shader = SweepGradient(
        colors: <Color>[color.withOpacity(0), color],
      ).createShader(rect);
    canvas.drawArc(rect, 0.1, math.pi * 2 * 0.9, false, paint);
  }

  @override
  bool shouldRepaint(_LoadingIndicatorPainter oldDelegate) => false;
}
