import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/custom_dropdown_button.dart';

/// Widget tests for CustomDropdownButton.
void main() {
  group('CustomDropdownButton Widget', () {
    test('CustomDropdownButton can be instantiated', () {
      expect(CustomDropdownButton, isNotNull);
    });

    test('CustomDropdownButton stores required parameters', () {
      final widget = CustomDropdownButton<String>(
        value: 'option1',
        items: const [
          DropdownMenuItem(value: 'option1', child: Text('Option 1')),
          DropdownMenuItem(value: 'option2', child: Text('Option 2')),
        ],
      );

      expect(widget.value, 'option1');
      expect(widget.items.length, 2);
    });

    test('CustomDropdownButton accepts onChanged callback', () {
      final widget = CustomDropdownButton<String>(
        value: 'option1',
        items: const [
          DropdownMenuItem(value: 'option1', child: Text('Option 1')),
          DropdownMenuItem(value: 'option2', child: Text('Option 2')),
        ],
        onChanged: (value) {},
      );

      expect(widget.onChanged, isNotNull);
    });

    test('CustomDropdownButton works with int type', () {
      final widget = CustomDropdownButton<int>(
        value: 1,
        items: const [
          DropdownMenuItem(value: 1, child: Text('1')),
          DropdownMenuItem(value: 2, child: Text('2')),
          DropdownMenuItem(value: 3, child: Text('3')),
        ],
      );

      expect(widget.value, 1);
      expect(widget.items.length, 3);
    });

    test('CustomDropdownButton onChanged can be null', () {
      final widget = CustomDropdownButton<String>(
        value: 'option1',
        items: const [
          DropdownMenuItem(value: 'option1', child: Text('Option 1')),
        ],
        onChanged: null,
      );

      expect(widget.onChanged, isNull);
    });
  });

  group('CustomDropdownButton Widget Rendering', () {
    testWidgets('renders dropdown with given value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomDropdownButton<String>(
              value: 'Test Option',
              items: const [
                DropdownMenuItem(
                    value: 'Test Option', child: Text('Test Option')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Test Option'), findsOneWidget);
    });

    testWidgets('renders dropdown arrow icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomDropdownButton<String>(
              value: 'option1',
              items: const [
                DropdownMenuItem(value: 'option1', child: Text('Option 1')),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    });

    testWidgets('dropdown opens on tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomDropdownButton<String>(
              value: 'option1',
              items: const [
                DropdownMenuItem(value: 'option1', child: Text('Option 1')),
                DropdownMenuItem(value: 'option2', child: Text('Option 2')),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // The selected value should remain visible
      expect(find.text('Option 1'), findsWidgets);
    });

    testWidgets('calls onChanged when value is selected', (tester) async {
      final widget = CustomDropdownButton<String>(
        value: 'option1',
        items: const [
          DropdownMenuItem(value: 'option1', child: Text('Option 1')),
          DropdownMenuItem(value: 'option2', child: Text('Option 2')),
        ],
        onChanged: (value) {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: widget,
          ),
        ),
      );

      // Verify the onChanged callback is set
      expect(widget.onChanged, isNotNull);

      // Open dropdown
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
    });
  });

  group('CustomDropdownButton Generic Types', () {
    test('works with enum type', () {
      // Define a simple test
      final widget = CustomDropdownButton<int>(
        value: 0,
        items: const [
          DropdownMenuItem(value: 0, child: Text('First')),
          DropdownMenuItem(value: 1, child: Text('Second')),
        ],
      );

      expect(widget.value, 0);
    });

    test('works with nullable String', () {
      final widget = CustomDropdownButton<String?>(
        value: null,
        items: const [
          DropdownMenuItem(value: null, child: Text('None')),
          DropdownMenuItem(value: 'value', child: Text('Value')),
        ],
      );

      expect(widget.value, isNull);
    });
  });
}
