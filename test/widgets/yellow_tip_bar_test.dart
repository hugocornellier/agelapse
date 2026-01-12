import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/yellow_tip_bar.dart';

void main() {
  group('YellowTipBar', () {
    testWidgets('displays the provided message', (tester) async {
      const testMessage = 'This is a helpful tip';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: YellowTipBar(message: testMessage)),
        ),
      );

      expect(find.text(testMessage), findsOneWidget);
    });

    testWidgets('displays lightbulb icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: YellowTipBar(message: 'Test')),
        ),
      );

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('has correct layout with Row', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: YellowTipBar(message: 'Test')),
        ),
      );

      expect(find.byType(Row), findsOneWidget);
    });

    testWidgets('wraps long text', (tester) async {
      const longMessage =
          'This is a very long message that should wrap to multiple lines '
          'when displayed in the yellow tip bar widget to ensure proper display.';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: YellowTipBar(message: longMessage)),
        ),
      );

      expect(find.text(longMessage), findsOneWidget);
      expect(find.byType(Flexible), findsOneWidget);
    });

    testWidgets('has Container with padding and margin', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: YellowTipBar(message: 'Test')),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.padding, const EdgeInsets.all(16));
      expect(container.margin, const EdgeInsets.symmetric(horizontal: 16));
    });

    testWidgets('icon has correct size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: YellowTipBar(message: 'Test')),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.info_outline));
      expect(icon.size, 20);
    });

    testWidgets('displays empty message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: YellowTipBar(message: '')),
        ),
      );

      // Should still render without errors
      expect(find.byType(YellowTipBar), findsOneWidget);
    });

    testWidgets('text has white color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: YellowTipBar(message: 'Test')),
        ),
      );

      final text = tester.widget<Text>(find.text('Test'));
      expect(text.style?.color, Colors.white);
    });
  });
}
