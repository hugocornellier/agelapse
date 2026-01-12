import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/tutorial_page.dart';

/// Widget tests for TutorialPage.
void main() {
  group('TutorialPage Widget', () {
    test('TutorialPage can be instantiated', () {
      expect(TutorialPage, isNotNull);
    });

    test('TutorialPage has no required parameters', () {
      const widget = TutorialPage();
      expect(widget, isA<TutorialPage>());
    });

    test('TutorialPage is a StatelessWidget', () {
      const widget = TutorialPage();
      expect(widget, isA<StatelessWidget>());
    });
  });

  group('TutorialSection Widget', () {
    test('TutorialSection can be instantiated', () {
      expect(TutorialSection, isNotNull);
    });

    test('TutorialSection stores required parameters', () {
      const widget = TutorialSection(
        title: 'Import photos',
        steps: [Text('Step 1'), Text('Step 2')],
      );

      expect(widget.title, 'Import photos');
      expect(widget.steps.length, 2);
    });

    test('TutorialSection creates state', () {
      const widget = TutorialSection(title: 'Test', steps: [Text('Step')]);

      expect(widget.createState(), isA<TutorialSectionState>());
    });

    test('TutorialSection handles empty steps', () {
      const widget = TutorialSection(title: 'Empty Section', steps: []);

      expect(widget.steps, isEmpty);
    });

    test('TutorialSection handles many steps', () {
      final widget = TutorialSection(
        title: 'Many Steps',
        steps: List.generate(10, (i) => Text('Step ${i + 1}')),
      );

      expect(widget.steps.length, 10);
    });
  });
}
