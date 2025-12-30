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

  group('MainNavigationState.photoWasTakenToday', () {
    test('returns false for empty list', () {
      final result = MainNavigationState.photoWasTakenToday([]);
      expect(result, isFalse);
    });

    test('returns false for old photos', () {
      // Use a timestamp from a year ago
      final oldTimestamp = DateTime.now()
          .subtract(const Duration(days: 365))
          .millisecondsSinceEpoch;
      final result = MainNavigationState.photoWasTakenToday([
        '/path/$oldTimestamp.jpg',
      ]);
      expect(result, isFalse);
    });

    test('returns true for today\'s photo', () {
      // Use current timestamp
      final todayTimestamp = DateTime.now().millisecondsSinceEpoch;
      final result = MainNavigationState.photoWasTakenToday([
        '/path/$todayTimestamp.jpg',
      ]);
      expect(result, isTrue);
    });

    test('returns true if any photo is from today', () {
      final oldTimestamp = DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;
      final todayTimestamp = DateTime.now().millisecondsSinceEpoch;
      final result = MainNavigationState.photoWasTakenToday([
        '/path/$oldTimestamp.jpg',
        '/path/$todayTimestamp.jpg',
      ]);
      expect(result, isTrue);
    });
  });
}
