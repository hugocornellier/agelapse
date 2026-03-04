import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/info_tooltip_icon.dart';

/// Unit tests for InfoTooltipIcon widget.
void main() {
  group('InfoTooltipIcon', () {
    test('can be instantiated with required parameters', () {
      const widget = InfoTooltipIcon(content: 'Test info');
      expect(widget, isA<InfoTooltipIcon>());
    });

    test('stores content correctly', () {
      const widget = InfoTooltipIcon(content: 'Some helpful info');
      expect(widget.content, 'Some helpful info');
    });

    test('disabled defaults to false', () {
      const widget = InfoTooltipIcon(content: 'Info');
      expect(widget.disabled, isFalse);
    });

    test('accepts disabled parameter', () {
      const widget = InfoTooltipIcon(content: 'Info', disabled: true);
      expect(widget.disabled, isTrue);
    });

    testWidgets('renders info icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InfoTooltipIcon(content: 'Test')),
        ),
      );

      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    });

    testWidgets('wraps in MouseRegion for cursor', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InfoTooltipIcon(content: 'Test')),
        ),
      );

      expect(find.byType(MouseRegion), findsWidgets);
    });

    testWidgets('wraps in GestureDetector for tap', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InfoTooltipIcon(content: 'Test')),
        ),
      );

      expect(find.byType(GestureDetector), findsOneWidget);
    });
  });
}
