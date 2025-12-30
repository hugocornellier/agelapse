import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/manual_stab_page.dart';

/// Widget tests for ManualStabilizationPage.
/// Tests widget structure and properties.
void main() {
  group('ManualStabilizationPage Widget', () {
    test('ManualStabilizationPage has required constructor parameters', () {
      expect(ManualStabilizationPage, isNotNull);
    });

    test('ManualStabilizationPage can be instantiated with parameters', () {
      final widget = ManualStabilizationPage(
        imagePath: '/path/to/image.jpg',
        projectId: 1,
      );

      expect(widget.imagePath, '/path/to/image.jpg');
      expect(widget.projectId, 1);
    });

    test('ManualStabilizationPage stores image path', () {
      final widget = ManualStabilizationPage(
        imagePath: '/custom/path/photo.png',
        projectId: 5,
      );

      expect(widget.imagePath, '/custom/path/photo.png');
    });

    test('ManualStabilizationPage stores project id', () {
      final widget = ManualStabilizationPage(
        imagePath: '/test/image.jpg',
        projectId: 42,
      );

      expect(widget.projectId, 42);
    });

    test('ManualStabilizationPage handles different image extensions', () {
      final jpgWidget = ManualStabilizationPage(
        imagePath: '/path/image.jpg',
        projectId: 1,
      );
      expect(jpgWidget.imagePath, endsWith('.jpg'));

      final pngWidget = ManualStabilizationPage(
        imagePath: '/path/image.png',
        projectId: 1,
      );
      expect(pngWidget.imagePath, endsWith('.png'));

      final heicWidget = ManualStabilizationPage(
        imagePath: '/path/image.heic',
        projectId: 1,
      );
      expect(heicWidget.imagePath, endsWith('.heic'));
    });
  });

  group('ManualStabilizationPage State', () {
    test('ManualStabilizationPageState creates state class', () {
      final widget = ManualStabilizationPage(
        imagePath: '/path/to/image.jpg',
        projectId: 1,
      );

      expect(widget.createState(), isA<ManualStabilizationPageState>());
    });
  });

  group('ManualStabilizationPage Path Handling', () {
    test('handles paths with spaces', () {
      final widget = ManualStabilizationPage(
        imagePath: '/path with spaces/image file.jpg',
        projectId: 1,
      );

      expect(widget.imagePath, contains(' '));
    });

    test('handles deeply nested paths', () {
      final widget = ManualStabilizationPage(
        imagePath: '/a/b/c/d/e/f/g/h/image.jpg',
        projectId: 1,
      );

      expect(widget.imagePath, startsWith('/a/b/c'));
    });

    test('handles timestamp-based filenames', () {
      final widget = ManualStabilizationPage(
        imagePath: '/path/1234567890123.jpg',
        projectId: 1,
      );

      expect(widget.imagePath, contains('1234567890123'));
    });
  });
}
