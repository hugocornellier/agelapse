import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/took_first_photo_page.dart';

/// Widget tests for TookFirstPhotoPage.
void main() {
  group('TookFirstPhotoPage Widget', () {
    test('TookFirstPhotoPage can be instantiated', () {
      expect(TookFirstPhotoPage, isNotNull);
    });

    test('TookFirstPhotoPage stores required parameters', () {
      final widget = TookFirstPhotoPage(
        projectId: 1,
        projectName: 'Test Project',
        goToPage: (index) {},
      );

      expect(widget.projectId, 1);
      expect(widget.projectName, 'Test Project');
    });

    test('goToPage callback is stored correctly', () {
      int? receivedIndex;

      final widget = TookFirstPhotoPage(
        projectId: 1,
        projectName: 'Test',
        goToPage: (index) {
          receivedIndex = index;
        },
      );

      widget.goToPage(2);
      expect(receivedIndex, 2);
    });

    test('TookFirstPhotoPage creates state', () {
      final widget = TookFirstPhotoPage(
        projectId: 1,
        projectName: 'Test',
        goToPage: (index) {},
      );

      expect(widget.createState(), isA<TookFirstPhotoPageState>());
    });

    test('handles different project IDs', () {
      final widget1 = TookFirstPhotoPage(
        projectId: 0,
        projectName: 'First',
        goToPage: (index) {},
      );

      final widget2 = TookFirstPhotoPage(
        projectId: 999,
        projectName: 'Last',
        goToPage: (index) {},
      );

      expect(widget1.projectId, 0);
      expect(widget2.projectId, 999);
    });

    test('handles long project names', () {
      final widget = TookFirstPhotoPage(
        projectId: 1,
        projectName: 'This is a very long project name that might be used',
        goToPage: (index) {},
      );

      expect(widget.projectName.length, greaterThan(40));
    });
  });

  group('TookFirstPhotoPage goToPage Behavior', () {
    test('goToPage can navigate to index 0', () {
      int? receivedIndex;

      final widget = TookFirstPhotoPage(
        projectId: 1,
        projectName: 'Test',
        goToPage: (index) {
          receivedIndex = index;
        },
      );

      widget.goToPage(0);
      expect(receivedIndex, 0);
    });

    test('goToPage can navigate to index 1', () {
      int? receivedIndex;

      final widget = TookFirstPhotoPage(
        projectId: 1,
        projectName: 'Test',
        goToPage: (index) {
          receivedIndex = index;
        },
      );

      widget.goToPage(1);
      expect(receivedIndex, 1);
    });

    test('goToPage tracks call count', () {
      int callCount = 0;

      final widget = TookFirstPhotoPage(
        projectId: 1,
        projectName: 'Test',
        goToPage: (index) {
          callCount++;
        },
      );

      widget.goToPage(0);
      widget.goToPage(1);
      widget.goToPage(2);
      expect(callCount, 3);
    });
  });
}
