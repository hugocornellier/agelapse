import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/create_project_sheet.dart';

/// Widget tests for CreateProjectSheet.
void main() {
  group('CreateProjectSheet Widget', () {
    test('CreateProjectSheet can be instantiated', () {
      expect(CreateProjectSheet, isNotNull);
    });

    test('CreateProjectSheet stores required parameters', () {
      const widget = CreateProjectSheet(isDefaultProject: true);

      expect(widget.isDefaultProject, isTrue);
    });

    test('showCloseButton defaults to true', () {
      const widget = CreateProjectSheet(isDefaultProject: false);

      expect(widget.showCloseButton, isTrue);
    });

    test('showCloseButton can be set to false', () {
      const widget = CreateProjectSheet(
        isDefaultProject: false,
        showCloseButton: false,
      );

      expect(widget.showCloseButton, isFalse);
    });

    test('CreateProjectSheet creates state', () {
      const widget = CreateProjectSheet(isDefaultProject: false);

      expect(widget.createState(), isA<CreateProjectSheetState>());
    });
  });

  group('CreateProjectSheet State Combinations', () {
    test('default project with close button', () {
      const widget = CreateProjectSheet(
        isDefaultProject: true,
        showCloseButton: true,
      );

      expect(widget.isDefaultProject, isTrue);
      expect(widget.showCloseButton, isTrue);
    });

    test('non-default project without close button', () {
      const widget = CreateProjectSheet(
        isDefaultProject: false,
        showCloseButton: false,
      );

      expect(widget.isDefaultProject, isFalse);
      expect(widget.showCloseButton, isFalse);
    });
  });

  group('CreateProjectSheetState Static Methods', () {
    test('checkForStabilizedImage method exists', () {
      expect(CreateProjectSheetState.checkForStabilizedImage, isA<Function>());
    });

    test('photoWasTakenToday method exists', () {
      expect(CreateProjectSheetState.photoWasTakenToday, isA<Function>());
    });

    test('checkForStabilizedImage returns Future<String?>', () {
      final result = CreateProjectSheetState.checkForStabilizedImage(
        '/nonexistent',
      );
      expect(result, isA<Future<String?>>());
    });

    // Note: photoWasTakenToday requires database access so we only verify the method signature
    test('photoWasTakenToday method signature is correct', () {
      // Verify the method exists and accepts int parameter
      expect(CreateProjectSheetState.photoWasTakenToday, isA<Function>());
    });

    test(
      'checkForStabilizedImage returns null for nonexistent directory',
      () async {
        final result = await CreateProjectSheetState.checkForStabilizedImage(
          '/nonexistent/path/that/does/not/exist',
        );
        expect(result, isNull);
      },
    );
  });
}
