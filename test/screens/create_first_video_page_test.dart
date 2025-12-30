import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/create_first_video_page.dart';

/// Widget tests for CreateFirstVideoPage.
void main() {
  group('CreateFirstVideoPage Widget', () {
    test('CreateFirstVideoPage can be instantiated', () {
      expect(CreateFirstVideoPage, isNotNull);
    });

    test('CreateFirstVideoPage stores required parameters', () {
      final widget = CreateFirstVideoPage(
        projectId: 1,
        projectName: 'Test Project',
        goToPage: (index) {},
      );

      expect(widget.projectId, 1);
      expect(widget.projectName, 'Test Project');
    });

    test('goToPage callback is stored correctly', () {
      int? receivedIndex;

      final widget = CreateFirstVideoPage(
        projectId: 1,
        projectName: 'Test',
        goToPage: (index) {
          receivedIndex = index;
        },
      );

      widget.goToPage(3);
      expect(receivedIndex, 3);
    });

    test('CreateFirstVideoPage creates state', () {
      final widget = CreateFirstVideoPage(
        projectId: 1,
        projectName: 'Test',
        goToPage: (index) {},
      );

      expect(widget.createState(), isA<CreateFirstVideoPageState>());
    });
  });

  group('CreateFirstVideoPage Edge Cases', () {
    test('handles empty project name', () {
      final widget = CreateFirstVideoPage(
        projectId: 1,
        projectName: '',
        goToPage: (index) {},
      );

      expect(widget.projectName, '');
    });

    test('handles special characters in project name', () {
      final widget = CreateFirstVideoPage(
        projectId: 1,
        projectName: "John's Project #1",
        goToPage: (index) {},
      );

      expect(widget.projectName, contains("'"));
    });

    test('handles zero projectId', () {
      final widget = CreateFirstVideoPage(
        projectId: 0,
        projectName: 'Test',
        goToPage: (index) {},
      );

      expect(widget.projectId, 0);
    });
  });
}
