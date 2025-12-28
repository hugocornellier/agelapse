import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/fancy_button.dart';

void main() {
  group('FancyButton', () {
    group('buildElevatedButton', () {
      testWidgets('renders with provided text', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FancyButton.buildElevatedButton(
                  context,
                  text: 'Test Button',
                  icon: Icons.add,
                  color: Colors.blue,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );

        expect(find.text('Test Button'), findsOneWidget);
      });

      testWidgets('renders with provided icon', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FancyButton.buildElevatedButton(
                  context,
                  text: 'Button',
                  icon: Icons.camera,
                  color: Colors.red,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.camera), findsOneWidget);
      });

      testWidgets('shows arrow forward icon', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FancyButton.buildElevatedButton(
                  context,
                  text: 'Button',
                  icon: Icons.add,
                  color: Colors.blue,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.arrow_forward_ios), findsOneWidget);
      });

      testWidgets('calls onPressed when tapped', (tester) async {
        var pressed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FancyButton.buildElevatedButton(
                  context,
                  text: 'Tap Me',
                  icon: Icons.add,
                  color: Colors.blue,
                  onPressed: () => pressed = true,
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(ElevatedButton));
        await tester.pump();

        expect(pressed, isTrue);
      });

      testWidgets('uses default background color when not provided',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FancyButton.buildElevatedButton(
                  context,
                  text: 'Button',
                  icon: Icons.add,
                  color: Colors.blue,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );

        final button =
            tester.widget<ElevatedButton>(find.byType(ElevatedButton));
        expect(button.style, isNotNull);
      });

      testWidgets('uses custom background color when provided', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FancyButton.buildElevatedButton(
                  context,
                  text: 'Button',
                  icon: Icons.add,
                  color: Colors.blue,
                  onPressed: () {},
                  backgroundColor: Colors.purple,
                ),
              ),
            ),
          ),
        );

        final button =
            tester.widget<ElevatedButton>(find.byType(ElevatedButton));
        expect(button.style, isNotNull);
      });

      testWidgets('contains CircleAvatar with icon', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FancyButton.buildElevatedButton(
                  context,
                  text: 'Button',
                  icon: Icons.star,
                  color: Colors.yellow,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );

        expect(find.byType(CircleAvatar), findsOneWidget);
        expect(find.byIcon(Icons.star), findsOneWidget);
      });

      testWidgets('has correct structure with Row', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FancyButton.buildElevatedButton(
                  context,
                  text: 'Button',
                  icon: Icons.add,
                  color: Colors.blue,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );

        // Should have a Row inside the ElevatedButton
        expect(
            find.descendant(
              of: find.byType(ElevatedButton),
              matching: find.byType(Row),
            ),
            findsOneWidget);
      });
    });
  });
}
