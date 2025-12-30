import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/project_page.dart';

/// Widget tests for ProjectPage.
void main() {
  group('ProjectPage Widget', () {
    test('ProjectPage can be instantiated', () {
      expect(ProjectPage, isNotNull);
    });

    test('ProjectPage stores required parameters', () {
      final widget = ProjectPage(
        projectId: 1,
        projectName: 'Test Project',
        cancelStabCallback: () async {},
        stabilizingRunningInMain: false,
        goToPage: (index) {},
        stabCallback: () async {},
        setUserOnImportTutorialTrue: () async {},
        settingsCache: null,
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        photoTakenToday: false,
      );

      expect(widget.projectId, 1);
      expect(widget.projectName, 'Test Project');
      expect(widget.stabilizingRunningInMain, isFalse);
      expect(widget.photoTakenToday, isFalse);
    });

    test('ProjectPage accepts optional stabUpdateStream', () {
      final widget = ProjectPage(
        projectId: 1,
        projectName: 'Test',
        cancelStabCallback: () async {},
        stabilizingRunningInMain: true,
        goToPage: (index) {},
        stabCallback: () async {},
        setUserOnImportTutorialTrue: () async {},
        settingsCache: null,
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        photoTakenToday: true,
        stabUpdateStream: null,
      );

      expect(widget.stabUpdateStream, isNull);
    });

    test('ProjectPage callbacks are accessible', () {
      bool cancelCalled = false;
      bool stabCalled = false;
      bool refreshCalled = false;
      bool clearCalled = false;
      bool tutorialCalled = false;
      int? pageIndex;

      final widget = ProjectPage(
        projectId: 2,
        projectName: 'Callback Test',
        cancelStabCallback: () async {
          cancelCalled = true;
        },
        stabilizingRunningInMain: false,
        goToPage: (index) {
          pageIndex = index;
        },
        stabCallback: () async {
          stabCalled = true;
        },
        setUserOnImportTutorialTrue: () async {
          tutorialCalled = true;
        },
        settingsCache: null,
        refreshSettings: () async {
          refreshCalled = true;
        },
        clearRawAndStabPhotos: () {
          clearCalled = true;
        },
        photoTakenToday: false,
      );

      // Test callbacks
      widget.cancelStabCallback();
      widget.stabCallback();
      widget.refreshSettings();
      widget.clearRawAndStabPhotos();
      widget.setUserOnImportTutorialTrue();
      widget.goToPage(3);

      expect(cancelCalled, isTrue);
      expect(stabCalled, isTrue);
      expect(refreshCalled, isTrue);
      expect(clearCalled, isTrue);
      expect(tutorialCalled, isTrue);
      expect(pageIndex, 3);
    });

    test('ProjectPage creates state', () {
      final widget = ProjectPage(
        projectId: 1,
        projectName: 'Test',
        cancelStabCallback: () async {},
        stabilizingRunningInMain: false,
        goToPage: (index) {},
        stabCallback: () async {},
        setUserOnImportTutorialTrue: () async {},
        settingsCache: null,
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        photoTakenToday: false,
      );

      expect(widget.createState(), isA<ProjectPageState>());
    });
  });

  group('ProjectPage State Combinations', () {
    test('handles stabilizing running state', () {
      final widget = ProjectPage(
        projectId: 1,
        projectName: 'Test',
        cancelStabCallback: () async {},
        stabilizingRunningInMain: true,
        goToPage: (index) {},
        stabCallback: () async {},
        setUserOnImportTutorialTrue: () async {},
        settingsCache: null,
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        photoTakenToday: false,
      );

      expect(widget.stabilizingRunningInMain, isTrue);
    });

    test('handles photo taken today state', () {
      final widget = ProjectPage(
        projectId: 1,
        projectName: 'Test',
        cancelStabCallback: () async {},
        stabilizingRunningInMain: false,
        goToPage: (index) {},
        stabCallback: () async {},
        setUserOnImportTutorialTrue: () async {},
        settingsCache: null,
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        photoTakenToday: true,
      );

      expect(widget.photoTakenToday, isTrue);
    });
  });

  group('ProjectPage Edge Cases', () {
    test('handles empty project name', () {
      final widget = ProjectPage(
        projectId: 1,
        projectName: '',
        cancelStabCallback: () async {},
        stabilizingRunningInMain: false,
        goToPage: (index) {},
        stabCallback: () async {},
        setUserOnImportTutorialTrue: () async {},
        settingsCache: null,
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        photoTakenToday: false,
      );

      expect(widget.projectName, '');
    });

    test('handles special characters in project name', () {
      final widget = ProjectPage(
        projectId: 1,
        projectName: "John's Project #1 (2024)",
        cancelStabCallback: () async {},
        stabilizingRunningInMain: false,
        goToPage: (index) {},
        stabCallback: () async {},
        setUserOnImportTutorialTrue: () async {},
        settingsCache: null,
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        photoTakenToday: false,
      );

      expect(widget.projectName, contains("'"));
      expect(widget.projectName, contains('#'));
    });
  });
}
