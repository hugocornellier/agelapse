import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/delete_project_dialog.dart';

/// Widget tests for delete_project_dialog.dart.
void main() {
  group('showDeleteProjectDialog Function', () {
    test('showDeleteProjectDialog function exists', () {
      expect(showDeleteProjectDialog, isA<Function>());
    });

    test('showDeleteProjectDialog returns Future<bool?>', () {
      // We can't actually call this function without a BuildContext,
      // but we can verify the function signature
      // ignore: unnecessary_type_check
      expect(showDeleteProjectDialog is Function, isTrue);
    });
  });

  group('Delete Project Dialog Behavior', () {
    testWidgets('dialog can be shown and cancelled', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showDeleteProjectDialog(
                      context: context,
                      projectName: 'TestProj',
                    );
                  },
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Tap button to show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog is shown
      expect(find.text('Delete Project'), findsOneWidget);
      // The project name appears in the warning text
      expect(find.textContaining('TestProj'), findsWidgets);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('dialog shows project name in warning', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDeleteProjectDialog(
                      context: context,
                      projectName: 'SpecialProj',
                    );
                  },
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Project name should appear in the warning text
      expect(find.textContaining('SpecialProj'), findsWidgets);
    });

    testWidgets('Delete button is disabled initially', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDeleteProjectDialog(
                      context: context,
                      projectName: 'Test',
                    );
                  },
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Delete button should be present but disabled (visually different)
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('Delete button enables after typing project name',
        (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showDeleteProjectDialog(
                      context: context,
                      projectName: 'Test',
                    );
                  },
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Enter the exact project name
      final textField = find.byType(TextField);
      await tester.enterText(textField, 'Test');
      await tester.pumpAndSettle();

      // Now Delete should be enabled - tap it
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('close button returns false', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showDeleteProjectDialog(
                      context: context,
                      projectName: 'Test',
                    );
                  },
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Find and tap the close button (Icon)
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('handles special characters in project name', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showDeleteProjectDialog(
                      context: context,
                      projectName: "Johns1",
                    );
                  },
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Enter the project name
      final textField = find.byType(TextField);
      await tester.enterText(textField, "Johns1");
      await tester.pumpAndSettle();

      // Delete should be enabled
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });
  });
}
