import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/create_project_page.dart';

/// Widget tests for CreateProjectPage.
void main() {
  group('CreateProjectPage Widget', () {
    test('CreateProjectPage can be instantiated', () {
      expect(CreateProjectPage, isNotNull);
    });

    test('showCloseButton defaults to true', () {
      const widget = CreateProjectPage();
      expect(widget.showCloseButton, isTrue);
    });

    test('showCloseButton can be set to false', () {
      const widget = CreateProjectPage(showCloseButton: false);
      expect(widget.showCloseButton, isFalse);
    });

    test('CreateProjectPage creates state', () {
      const widget = CreateProjectPage();
      expect(widget.createState(), isA<CreateProjectPageState>());
    });
  });

  group('CreateProjectPage State Combinations', () {
    test('with close button shown', () {
      const widget = CreateProjectPage(showCloseButton: true);
      expect(widget.showCloseButton, isTrue);
    });

    test('with close button hidden', () {
      const widget = CreateProjectPage(showCloseButton: false);
      expect(widget.showCloseButton, isFalse);
    });
  });
}
