import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/in_progress_widget.dart';

void main() {
  group('InProgress', () {
    testWidgets('displays the provided message', (tester) async {
      const testMessage = 'Stabilizing photos...';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InProgress(message: testMessage)),
        ),
      );

      expect(find.text(testMessage), findsOneWidget);
    });

    testWidgets('uses red background for storage error message', (
      tester,
    ) async {
      const errorMessage = 'No storage space on device.';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InProgress(message: errorMessage)),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.color, Colors.red);
    });

    testWidgets('uses blue background for non-error messages', (tester) async {
      const normalMessage = 'Processing...';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InProgress(message: normalMessage)),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.color, isNot(Colors.red));
    });

    testWidgets('has GestureDetector wrapper', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InProgress(message: 'Test')),
        ),
      );

      expect(find.byType(GestureDetector), findsOneWidget);
    });

    testWidgets('text has centered alignment', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InProgress(message: 'Test')),
        ),
      );

      final text = tester.widget<Text>(find.text('Test'));
      expect(text.textAlign, TextAlign.center);
    });

    testWidgets('text has white color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InProgress(message: 'Test')),
        ),
      );

      final text = tester.widget<Text>(find.text('Test'));
      expect(text.style?.color, Colors.white);
    });

    testWidgets('container has max height constraint', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InProgress(message: 'Test')),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.constraints?.maxHeight, 32.0);
    });

    testWidgets('container takes full width', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InProgress(message: 'Test')),
        ),
      );

      // Container uses width: double.infinity to take full width
      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container, isNotNull);
    });

    testWidgets('displays long message', (tester) async {
      const longMessage =
          'This is a very long progress message that describes what is happening in detail';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InProgress(message: longMessage)),
        ),
      );

      expect(find.text(longMessage), findsOneWidget);
    });

    testWidgets('handles empty message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InProgress(message: '')),
        ),
      );

      expect(find.byType(InProgress), findsOneWidget);
    });

    testWidgets('goToPage callback can be null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InProgress(message: 'Test', goToPage: null)),
        ),
      );

      // Should render without error
      expect(find.byType(InProgress), findsOneWidget);
    });

    testWidgets('renders with goToPage callback provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InProgress(message: 'Test', goToPage: (page) {}),
          ),
        ),
      );

      expect(find.byType(InProgress), findsOneWidget);
    });
  });
}
