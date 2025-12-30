import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/guide_mode_tutorial_page.dart';

/// Widget tests for GuideModeTutorialPage.
void main() {
  group('GuideModeTutorialPage Widget', () {
    test('GuideModeTutorialPage can be instantiated', () {
      expect(GuideModeTutorialPage, isNotNull);
    });

    test('GuideModeTutorialPage stores required parameters', () {
      final widget = GuideModeTutorialPage(
        projectId: 1,
        projectName: 'Test Project',
        goToPage: (index) {},
        sourcePage: 'camera',
      );

      expect(widget.projectId, 1);
      expect(widget.projectName, 'Test Project');
      expect(widget.sourcePage, 'camera');
    });

    test('goToPage callback is stored correctly', () {
      int? receivedIndex;

      final widget = GuideModeTutorialPage(
        projectId: 1,
        projectName: 'Test',
        goToPage: (index) {
          receivedIndex = index;
        },
        sourcePage: 'camera',
      );

      widget.goToPage(3);
      expect(receivedIndex, 3);
    });

    test('GuideModeTutorialPage creates state', () {
      final widget = GuideModeTutorialPage(
        projectId: 1,
        projectName: 'Test',
        goToPage: (index) {},
        sourcePage: 'camera',
      );

      expect(widget.createState(), isA<GuideModeTutorialPageState>());
    });

    test('sourcePage accepts different values', () {
      final widget1 = GuideModeTutorialPage(
        projectId: 1,
        projectName: 'Test',
        goToPage: (index) {},
        sourcePage: 'camera',
      );

      final widget2 = GuideModeTutorialPage(
        projectId: 1,
        projectName: 'Test',
        goToPage: (index) {},
        sourcePage: 'gallery',
      );

      final widget3 = GuideModeTutorialPage(
        projectId: 1,
        projectName: 'Test',
        goToPage: (index) {},
        sourcePage: 'settings',
      );

      expect(widget1.sourcePage, 'camera');
      expect(widget2.sourcePage, 'gallery');
      expect(widget3.sourcePage, 'settings');
    });

    test('handles different project IDs', () {
      final widget1 = GuideModeTutorialPage(
        projectId: 0,
        projectName: 'First',
        goToPage: (index) {},
        sourcePage: 'camera',
      );

      final widget2 = GuideModeTutorialPage(
        projectId: 999,
        projectName: 'Last',
        goToPage: (index) {},
        sourcePage: 'camera',
      );

      expect(widget1.projectId, 0);
      expect(widget2.projectId, 999);
    });
  });
}
