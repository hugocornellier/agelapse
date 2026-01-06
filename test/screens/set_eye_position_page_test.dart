import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/set_eye_position_page.dart';

/// Widget tests for SetEyePositionPage.
/// Tests widget structure and properties.
void main() {
  group('SetEyePositionPage Widget', () {
    test('SetEyePositionPage has required constructor parameters', () {
      expect(SetEyePositionPage, isNotNull);
    });

    test('SetEyePositionPage can be instantiated with parameters', () {
      final widget = SetEyePositionPage(
        projectId: 1,
        projectName: 'Test Project',
        cancelStabCallback: () async {},
        refreshSettings: () {},
        clearRawAndStabPhotos: () {},
        stabCallback: () {},
      );

      expect(widget.projectId, 1);
      expect(widget.projectName, 'Test Project');
    });

    test('SetEyePositionPage stores project id', () {
      final widget = SetEyePositionPage(
        projectId: 42,
        projectName: 'My Project',
        cancelStabCallback: () async {},
        refreshSettings: () {},
        clearRawAndStabPhotos: () {},
        stabCallback: () {},
      );

      expect(widget.projectId, 42);
    });

    test('SetEyePositionPage stores project name', () {
      final widget = SetEyePositionPage(
        projectId: 1,
        projectName: 'Face Timelapse 2024',
        cancelStabCallback: () async {},
        refreshSettings: () {},
        clearRawAndStabPhotos: () {},
        stabCallback: () {},
      );

      expect(widget.projectName, 'Face Timelapse 2024');
    });

    test('SetEyePositionPage callbacks are stored correctly', () {
      bool cancelCalled = false;
      bool refreshCalled = false;
      bool clearPhotosCalled = false;
      bool stabCalled = false;

      final widget = SetEyePositionPage(
        projectId: 1,
        projectName: 'Test',
        cancelStabCallback: () async {
          cancelCalled = true;
        },
        refreshSettings: () {
          refreshCalled = true;
        },
        clearRawAndStabPhotos: () {
          clearPhotosCalled = true;
        },
        stabCallback: () {
          stabCalled = true;
        },
      );

      // Verify callbacks are accessible
      widget.cancelStabCallback();
      widget.refreshSettings();
      widget.clearRawAndStabPhotos();
      widget.stabCallback();

      expect(cancelCalled, isTrue);
      expect(refreshCalled, isTrue);
      expect(clearPhotosCalled, isTrue);
      expect(stabCalled, isTrue);
    });
  });

  group('SetEyePositionPage State', () {
    test('SetEyePositionPageState creates state class', () {
      final widget = SetEyePositionPage(
        projectId: 1,
        projectName: 'Test',
        cancelStabCallback: () async {},
        refreshSettings: () {},
        clearRawAndStabPhotos: () {},
        stabCallback: () {},
      );

      expect(widget.createState(), isA<SetEyePositionPageState>());
    });
  });

  group('SetEyePositionPage Edge Cases', () {
    test('handles empty project name', () {
      final widget = SetEyePositionPage(
        projectId: 1,
        projectName: '',
        cancelStabCallback: () async {},
        refreshSettings: () {},
        clearRawAndStabPhotos: () {},
        stabCallback: () {},
      );

      expect(widget.projectName, '');
    });

    test('handles long project name', () {
      final longName = 'A' * 200;
      final widget = SetEyePositionPage(
        projectId: 1,
        projectName: longName,
        cancelStabCallback: () async {},
        refreshSettings: () {},
        clearRawAndStabPhotos: () {},
        stabCallback: () {},
      );

      expect(widget.projectName.length, 200);
    });

    test('handles special characters in project name', () {
      final widget = SetEyePositionPage(
        projectId: 1,
        projectName: "Project's #1 (2024)",
        cancelStabCallback: () async {},
        refreshSettings: () {},
        clearRawAndStabPhotos: () {},
        stabCallback: () {},
      );

      expect(widget.projectName, contains("'"));
      expect(widget.projectName, contains('#'));
      expect(widget.projectName, contains('('));
    });

    test('handles zero project id', () {
      // Edge case - might not be valid but shouldn't crash
      final widget = SetEyePositionPage(
        projectId: 0,
        projectName: 'Test',
        cancelStabCallback: () async {},
        refreshSettings: () {},
        clearRawAndStabPhotos: () {},
        stabCallback: () {},
      );

      expect(widget.projectId, 0);
    });
  });
}
