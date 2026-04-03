import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/main_navigation.dart';

/// Widget tests for MainNavigation.
void main() {
  group('MainNavigation Widget', () {
    test('MainNavigation can be instantiated', () {
      expect(MainNavigation, isNotNull);
    });

    test('MainNavigation stores required parameters', () {
      final widget = MainNavigation(
        projectId: 1,
        projectName: 'Test Project',
        showFlashingCircle: false,
      );

      expect(widget.projectId, 1);
      expect(widget.projectName, 'Test Project');
      expect(widget.showFlashingCircle, isFalse);
    });

    test('MainNavigation accepts optional index', () {
      final widget = MainNavigation(
        projectId: 1,
        projectName: 'Test',
        showFlashingCircle: false,
        index: 2,
      );

      expect(widget.index, 2);
    });

    test('MainNavigation accepts optional takingGuidePhoto', () {
      final widget = MainNavigation(
        projectId: 1,
        projectName: 'Test',
        showFlashingCircle: false,
        takingGuidePhoto: true,
      );

      expect(widget.takingGuidePhoto, isTrue);
    });

    test('MainNavigation accepts optional initialSettingsCache', () {
      final widget = MainNavigation(
        projectId: 1,
        projectName: 'Test',
        showFlashingCircle: false,
        initialSettingsCache: null,
      );

      expect(widget.initialSettingsCache, isNull);
    });

    test('MainNavigation newProject defaults to false', () {
      final widget = MainNavigation(
        projectId: 1,
        projectName: 'Test',
        showFlashingCircle: false,
      );

      expect(widget.newProject, isFalse);
    });

    test('MainNavigation accepts newProject parameter', () {
      final widget = MainNavigation(
        projectId: 1,
        projectName: 'Test',
        showFlashingCircle: true,
        newProject: true,
      );

      expect(widget.newProject, isTrue);
    });

    test('MainNavigation creates state', () {
      final widget = MainNavigation(
        projectId: 1,
        projectName: 'Test',
        showFlashingCircle: false,
      );

      expect(widget.createState(), isA<MainNavigationState>());
    });
  });

  group('MainNavigation Edge Cases', () {
    test('handles empty project name', () {
      final widget = MainNavigation(
        projectId: 1,
        projectName: '',
        showFlashingCircle: false,
      );

      expect(widget.projectName, '');
    });

    test('handles special characters in project name', () {
      final widget = MainNavigation(
        projectId: 1,
        projectName: "John's Project #1 (2024)",
        showFlashingCircle: true,
      );

      expect(widget.projectName, contains("'"));
      expect(widget.projectName, contains('#'));
    });

    test('handles zero projectId', () {
      final widget = MainNavigation(
        projectId: 0,
        projectName: 'Test',
        showFlashingCircle: false,
      );

      expect(widget.projectId, 0);
    });

    test('handles large projectId', () {
      final widget = MainNavigation(
        projectId: 999999,
        projectName: 'Test',
        showFlashingCircle: false,
      );

      expect(widget.projectId, 999999);
    });
  });

  group('MainNavigation Index Values', () {
    test('handles index 0', () {
      final widget = MainNavigation(
        projectId: 1,
        projectName: 'Test',
        showFlashingCircle: false,
        index: 0,
      );

      expect(widget.index, 0);
    });

    test('handles index 4 (last tab)', () {
      final widget = MainNavigation(
        projectId: 1,
        projectName: 'Test',
        showFlashingCircle: false,
        index: 4,
      );

      expect(widget.index, 4);
    });

    test('handles null index', () {
      final widget = MainNavigation(
        projectId: 1,
        projectName: 'Test',
        showFlashingCircle: false,
        index: null,
      );

      expect(widget.index, isNull);
    });
  });

  // photoWasTakenToday logic moved to ProjectUtils.photoWasTakenToday
  // (capture-offset aware). See test/utils/project_utils_test.dart.
}
