import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/projects_page.dart';

/// Widget tests for ProjectsPage.
void main() {
  group('ProjectsPage Widget', () {
    test('ProjectsPage can be instantiated', () {
      expect(ProjectsPage, isNotNull);
    });

    test('ProjectsPage has no required parameters', () {
      const widget = ProjectsPage();
      expect(widget, isA<ProjectsPage>());
    });

    test('ProjectsPage creates state', () {
      const widget = ProjectsPage();
      expect(widget.createState(), isA<ProjectsPageState>());
    });
  });
}
