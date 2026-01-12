import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/import_page.dart';

/// Widget tests for ImportPage.
void main() {
  group('ImportPage Widget', () {
    test('ImportPage can be instantiated', () {
      expect(ImportPage, isNotNull);
    });

    test('ImportPage stores required parameters', () {
      const widget = ImportPage(projectId: 1, projectName: 'Test Project');

      expect(widget.projectId, 1);
      expect(widget.projectName, 'Test Project');
    });

    test('ImportPage creates state', () {
      const widget = ImportPage(projectId: 1, projectName: 'Test');

      expect(widget.createState(), isA<ImportPageState>());
    });
  });

  group('ImportPage Edge Cases', () {
    test('handles empty project name', () {
      const widget = ImportPage(projectId: 1, projectName: '');

      expect(widget.projectName, '');
    });

    test('handles special characters in project name', () {
      const widget = ImportPage(projectId: 1, projectName: "John's #1 (2024)");

      expect(widget.projectName, contains("'"));
      expect(widget.projectName, contains('#'));
    });

    test('handles zero projectId', () {
      const widget = ImportPage(projectId: 0, projectName: 'Test');

      expect(widget.projectId, 0);
    });

    test('handles large projectId', () {
      const widget = ImportPage(projectId: 999999, projectName: 'Test');

      expect(widget.projectId, 999999);
    });
  });
}
