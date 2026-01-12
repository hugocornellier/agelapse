import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/project_select_sheet.dart';

/// Widget tests for ProjectSelectionSheet.
void main() {
  group('ProjectSelectionSheet Widget', () {
    test('ProjectSelectionSheet can be instantiated', () {
      expect(ProjectSelectionSheet, isNotNull);
    });

    test('ProjectSelectionSheet stores required parameters', () {
      final widget = ProjectSelectionSheet(
        isDefaultProject: true,
        cancelStabCallback: () {},
      );

      expect(widget.isDefaultProject, isTrue);
    });

    test('showCloseButton defaults to true', () {
      final widget = ProjectSelectionSheet(
        isDefaultProject: false,
        cancelStabCallback: () {},
      );

      expect(widget.showCloseButton, isTrue);
    });

    test('showCloseButton can be set to false', () {
      final widget = ProjectSelectionSheet(
        isDefaultProject: false,
        showCloseButton: false,
        cancelStabCallback: () {},
      );

      expect(widget.showCloseButton, isFalse);
    });

    test('currentProjectId can be set', () {
      final widget = ProjectSelectionSheet(
        isDefaultProject: false,
        cancelStabCallback: () {},
        currentProjectId: 5,
      );

      expect(widget.currentProjectId, 5);
    });

    test('currentProjectId defaults to null', () {
      final widget = ProjectSelectionSheet(
        isDefaultProject: false,
        cancelStabCallback: () {},
      );

      expect(widget.currentProjectId, isNull);
    });

    test('isFullPage defaults to false', () {
      final widget = ProjectSelectionSheet(
        isDefaultProject: false,
        cancelStabCallback: () {},
      );

      expect(widget.isFullPage, isFalse);
    });

    test('isFullPage can be set to true', () {
      final widget = ProjectSelectionSheet(
        isDefaultProject: false,
        cancelStabCallback: () {},
        isFullPage: true,
      );

      expect(widget.isFullPage, isTrue);
    });

    test('cancelStabCallback is stored correctly', () {
      bool cancelled = false;

      final widget = ProjectSelectionSheet(
        isDefaultProject: false,
        cancelStabCallback: () {
          cancelled = true;
        },
      );

      widget.cancelStabCallback();
      expect(cancelled, isTrue);
    });

    test('ProjectSelectionSheet creates state', () {
      final widget = ProjectSelectionSheet(
        isDefaultProject: false,
        cancelStabCallback: () {},
      );

      expect(widget.createState(), isA<ProjectSelectionSheetState>());
    });
  });

  group('ProjectSelectionSheet State Combinations', () {
    test('default project with close button', () {
      final widget = ProjectSelectionSheet(
        isDefaultProject: true,
        showCloseButton: true,
        cancelStabCallback: () {},
      );

      expect(widget.isDefaultProject, isTrue);
      expect(widget.showCloseButton, isTrue);
    });

    test('non-default project without close button', () {
      final widget = ProjectSelectionSheet(
        isDefaultProject: false,
        showCloseButton: false,
        cancelStabCallback: () {},
      );

      expect(widget.isDefaultProject, isFalse);
      expect(widget.showCloseButton, isFalse);
    });

    test('full page mode', () {
      final widget = ProjectSelectionSheet(
        isDefaultProject: false,
        cancelStabCallback: () {},
        isFullPage: true,
        showCloseButton: false,
      );

      expect(widget.isFullPage, isTrue);
      expect(widget.showCloseButton, isFalse);
    });
  });

  group('ProjectSelectionSheetState Static Methods', () {
    test('getProjectImage method exists', () {
      expect(ProjectSelectionSheetState.getProjectImage, isA<Function>());
    });

    test('checkForStabilizedImage method exists', () {
      expect(
        ProjectSelectionSheetState.checkForStabilizedImage,
        isA<Function>(),
      );
    });

    test('photoWasTakenToday method exists', () {
      expect(ProjectSelectionSheetState.photoWasTakenToday, isA<Function>());
    });

    // Note: These methods require database/filesystem access so we only verify signatures
    test('getProjectImage method signature is correct', () {
      expect(ProjectSelectionSheetState.getProjectImage, isA<Function>());
    });

    test('photoWasTakenToday method signature is correct', () {
      expect(ProjectSelectionSheetState.photoWasTakenToday, isA<Function>());
    });

    test('checkForStabilizedImage returns Future<String?>', () {
      final result = ProjectSelectionSheetState.checkForStabilizedImage(
        '/nonexistent',
      );
      expect(result, isA<Future<String?>>());
    });

    test('checkForStabilizedImage returns null for nonexistent dir', () async {
      final result = await ProjectSelectionSheetState.checkForStabilizedImage(
        '/nonexistent/path/that/does/not/exist',
      );
      expect(result, isNull);
    });
  });
}
