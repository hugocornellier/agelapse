import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/camera_page/countdown_overlay.dart';

/// Unit tests for CountdownOverlay and CountdownProgressPainter.
void main() {
  group('CountdownOverlay', () {
    test('can be referenced', () {
      expect(CountdownOverlay, isNotNull);
    });
  });

  group('CountdownProgressPainter', () {
    test('can be instantiated with required parameters', () {
      final painter = CountdownProgressPainter(progress: 0.5);
      expect(painter, isNotNull);
      expect(painter, isA<CountdownProgressPainter>());
    });

    test('stores progress value', () {
      final painter = CountdownProgressPainter(progress: 0.75);
      expect(painter.progress, 0.75);
    });

    test('has default strokeWidth of 4', () {
      final painter = CountdownProgressPainter(progress: 0.5);
      expect(painter.strokeWidth, 4);
    });

    test('accepts custom strokeWidth', () {
      final painter = CountdownProgressPainter(
        progress: 0.5,
        strokeWidth: 8,
      );
      expect(painter.strokeWidth, 8);
    });

    test('accepts custom color', () {
      final painter = CountdownProgressPainter(
        progress: 0.5,
        color: Colors.red,
      );
      expect(painter.color, Colors.red);
    });

    test('accepts custom backgroundColor', () {
      final painter = CountdownProgressPainter(
        progress: 0.5,
        backgroundColor: Colors.blue,
      );
      expect(painter.backgroundColor, Colors.blue);
    });

    test('shouldRepaint returns true when progress changes', () {
      final painter1 = CountdownProgressPainter(progress: 0.5);
      final painter2 = CountdownProgressPainter(progress: 0.7);
      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('shouldRepaint returns false when nothing changes', () {
      final painter1 = CountdownProgressPainter(progress: 0.5);
      final painter2 = CountdownProgressPainter(progress: 0.5);
      expect(painter1.shouldRepaint(painter2), isFalse);
    });

    test('shouldRepaint returns true when color changes', () {
      final painter1 = CountdownProgressPainter(
        progress: 0.5,
        color: Colors.red,
      );
      final painter2 = CountdownProgressPainter(
        progress: 0.5,
        color: Colors.blue,
      );
      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('shouldRepaint returns true when strokeWidth changes', () {
      final painter1 = CountdownProgressPainter(
        progress: 0.5,
        strokeWidth: 4,
      );
      final painter2 = CountdownProgressPainter(
        progress: 0.5,
        strokeWidth: 8,
      );
      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('handles progress value of 0.0', () {
      final painter = CountdownProgressPainter(progress: 0.0);
      expect(painter.progress, 0.0);
    });

    test('handles progress value of 1.0', () {
      final painter = CountdownProgressPainter(progress: 1.0);
      expect(painter.progress, 1.0);
    });
  });
}
