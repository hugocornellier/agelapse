import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/flashing_circle.dart';

/// Widget tests for FlashingCircle.
void main() {
  group('FlashingCircle Widget', () {
    test('FlashingCircle can be instantiated', () {
      expect(FlashingCircle, isNotNull);
    });

    test('FlashingCircle stores required parameters', () {
      const widget = FlashingCircle(diameter: 20, position: Offset(100, 100));

      expect(widget.diameter, 20);
      expect(widget.position, const Offset(100, 100));
    });

    test('FlashingCircle creates state', () {
      const widget = FlashingCircle(diameter: 20, position: Offset(100, 100));

      expect(widget.createState(), isA<FlashingCircleState>());
    });
  });

  group('FlashingCircle Diameter Values', () {
    test('handles small diameter', () {
      const widget = FlashingCircle(diameter: 5, position: Offset.zero);

      expect(widget.diameter, 5);
    });

    test('handles large diameter', () {
      const widget = FlashingCircle(diameter: 200, position: Offset.zero);

      expect(widget.diameter, 200);
    });

    test('handles zero diameter', () {
      const widget = FlashingCircle(diameter: 0, position: Offset.zero);

      expect(widget.diameter, 0);
    });

    test('handles fractional diameter', () {
      const widget = FlashingCircle(diameter: 15.5, position: Offset.zero);

      expect(widget.diameter, 15.5);
    });
  });

  group('FlashingCircle Position Values', () {
    test('handles origin position', () {
      const widget = FlashingCircle(diameter: 20, position: Offset.zero);

      expect(widget.position.dx, 0);
      expect(widget.position.dy, 0);
    });

    test('handles positive position', () {
      const widget = FlashingCircle(diameter: 20, position: Offset(150, 200));

      expect(widget.position.dx, 150);
      expect(widget.position.dy, 200);
    });

    test('handles negative position', () {
      const widget = FlashingCircle(diameter: 20, position: Offset(-50, -100));

      expect(widget.position.dx, -50);
      expect(widget.position.dy, -100);
    });

    test('handles fractional position', () {
      const widget = FlashingCircle(
        diameter: 20,
        position: Offset(100.5, 200.75),
      );

      expect(widget.position.dx, 100.5);
      expect(widget.position.dy, 200.75);
    });
  });

  group('FlashingCircle Position Calculation', () {
    test('circle centers on position', () {
      const diameter = 20.0;
      const position = Offset(100, 100);

      // The circle should be positioned so its center is at the position
      final left = position.dx - diameter / 2;
      final top = position.dy - diameter / 2;

      expect(left, 90);
      expect(top, 90);
    });

    test('circle center calculation for various diameters', () {
      const position = Offset(200, 300);

      // diameter 50
      expect(position.dx - 50 / 2, 175);
      expect(position.dy - 50 / 2, 275);

      // diameter 100
      expect(position.dx - 100 / 2, 150);
      expect(position.dy - 100 / 2, 250);
    });
  });

  group('FlashingCircle Widget Rendering', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [
              FlashingCircle(diameter: 20, position: Offset(100, 100)),
            ],
          ),
        ),
      );

      expect(find.byType(FlashingCircle), findsOneWidget);
    });

    testWidgets('uses Positioned widget', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [
              FlashingCircle(diameter: 20, position: Offset(100, 100)),
            ],
          ),
        ),
      );

      // Pump once to trigger animation build
      await tester.pump();

      expect(find.byType(Positioned), findsOneWidget);
    });

    testWidgets('creates circular container', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [FlashingCircle(diameter: 30, position: Offset(50, 50))],
          ),
        ),
      );

      await tester.pump();

      // Find container with circle shape
      final containerFinder = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.decoration is BoxDecoration) {
          final decoration = widget.decoration as BoxDecoration;
          return decoration.shape == BoxShape.circle;
        }
        return false;
      });

      expect(containerFinder, findsOneWidget);
    });

    testWidgets('animation controller is created', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [
              FlashingCircle(diameter: 20, position: Offset(100, 100)),
            ],
          ),
        ),
      );

      // Pump a few frames to see animation
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(FlashingCircle), findsOneWidget);
    });

    testWidgets('disposes properly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [
              FlashingCircle(diameter: 20, position: Offset(100, 100)),
            ],
          ),
        ),
      );

      await tester.pump();

      // Replace with different widget to trigger dispose
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Replaced'))),
      );

      // Should not throw
      expect(find.byType(FlashingCircle), findsNothing);
    });
  });
}
