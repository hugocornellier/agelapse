import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/global_drop_overlay.dart';

/// Unit tests for GlobalDropOverlay widget.
void main() {
  group('GlobalDropOverlay', () {
    test('can be instantiated with isDragging false', () {
      const widget = GlobalDropOverlay(isDragging: false);
      expect(widget, isA<GlobalDropOverlay>());
      expect(widget.isDragging, isFalse);
    });

    test('can be instantiated with isDragging true', () {
      const widget = GlobalDropOverlay(isDragging: true);
      expect(widget.isDragging, isTrue);
    });

    testWidgets('renders SizedBox.shrink when not dragging', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                GlobalDropOverlay(isDragging: false),
              ],
            ),
          ),
        ),
      );

      // Should render a shrunk widget
      expect(find.byType(SizedBox), findsWidgets);
      // Should NOT show the drop text
      expect(find.text('Drop files to import'), findsNothing);
    });

    testWidgets('renders overlay when dragging', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                GlobalDropOverlay(isDragging: true),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Drop files to import'), findsOneWidget);
      expect(
        find.text('Release anywhere in window to add photos'),
        findsOneWidget,
      );
    });

    testWidgets('shows file download icon when dragging', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                GlobalDropOverlay(isDragging: true),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);
    });

    testWidgets('wraps in IgnorePointer when dragging', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                GlobalDropOverlay(isDragging: true),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(IgnorePointer), findsWidgets);
    });
  });
}
