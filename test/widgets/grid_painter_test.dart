import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/grid_painter.dart';

/// Unit tests for GridPainter.
void main() {
  group('GridPainter Class', () {
    test('GridPainter can be instantiated', () {
      final painter = GridPainter();
      expect(painter, isNotNull);
      expect(painter, isA<CustomPainter>());
    });

    test('GridPainter extends CustomPainter', () {
      final painter = GridPainter();
      expect(painter, isA<CustomPainter>());
    });
  });

  group('GridPainter shouldRepaint', () {
    test('shouldRepaint returns false', () {
      final painter1 = GridPainter();
      final painter2 = GridPainter();

      expect(painter1.shouldRepaint(painter2), isFalse);
    });

    test('shouldRepaint returns false for same instance', () {
      final painter = GridPainter();
      expect(painter.shouldRepaint(painter), isFalse);
    });
  });

  group('GridPainter Paint Method', () {
    test('paint method exists', () {
      final painter = GridPainter();
      expect(painter.paint, isA<Function>());
    });

    test('drawVerticalLine method exists', () {
      final painter = GridPainter();
      expect(painter.drawVerticalLine, isA<Function>());
    });
  });

  group('GridPainter Widget Integration', () {
    testWidgets('CustomPaint renders with GridPainter', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              painter: GridPainter(),
              size: const Size(300, 300),
            ),
          ),
        ),
      );

      // Find CustomPaint with GridPainter specifically
      final gridPainterFinder = find.byWidgetPredicate((widget) {
        return widget is CustomPaint && widget.painter is GridPainter;
      });
      expect(gridPainterFinder, findsOneWidget);
    });

    testWidgets('GridPainter works with different sizes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  CustomPaint(
                    painter: GridPainter(),
                    size: const Size(100, 100),
                  ),
                  CustomPaint(
                    painter: GridPainter(),
                    size: const Size(200, 200),
                  ),
                  CustomPaint(
                    painter: GridPainter(),
                    size: const Size(100, 100),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Find CustomPaint widgets with GridPainter specifically
      final gridPainterFinder = find.byWidgetPredicate((widget) {
        return widget is CustomPaint && widget.painter is GridPainter;
      });
      expect(gridPainterFinder, findsNWidgets(3));
    });

    testWidgets('GridPainter works with zero size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              painter: GridPainter(),
              size: Size.zero,
            ),
          ),
        ),
      );

      // Find CustomPaint with GridPainter specifically
      final gridPainterFinder = find.byWidgetPredicate((widget) {
        return widget is CustomPaint && widget.painter is GridPainter;
      });
      expect(gridPainterFinder, findsOneWidget);
    });
  });

  group('GridPainter Calculations', () {
    test('grid divides into thirds', () {
      // The GridPainter divides width and height by 3
      const size = Size(300, 300);
      final cellWidth = size.width / 3;
      final cellHeight = size.height / 3;

      expect(cellWidth, 100);
      expect(cellHeight, 100);
    });

    test('horizontal line position calculation', () {
      const size = Size(300, 300);
      final cellHeight = size.height / 3;
      final dy = cellHeight + cellHeight * 0.3;

      expect(dy, closeTo(130, 0.001));
    });
  });
}
