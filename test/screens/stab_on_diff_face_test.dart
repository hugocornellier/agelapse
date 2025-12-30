import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/stab_on_diff_face.dart';

/// Widget tests for StabDiffFacePage.
void main() {
  group('StabDiffFacePage Widget', () {
    test('StabDiffFacePage can be instantiated', () {
      expect(StabDiffFacePage, isNotNull);
    });

    test('StabDiffFacePage stores required parameters', () {
      final widget = StabDiffFacePage(
        projectId: 1,
        imageTimestamp: '1704067200000',
        reloadImagesInGallery: () async {},
        stabCallback: () {},
        userRanOutOfSpaceCallback: () {},
      );

      expect(widget.projectId, 1);
      expect(widget.imageTimestamp, '1704067200000');
      expect(widget.stabilizationRunningInMain, isFalse);
    });

    test('stabilizationRunningInMain defaults to false', () {
      final widget = StabDiffFacePage(
        projectId: 1,
        imageTimestamp: '1234567890',
        reloadImagesInGallery: () async {},
        stabCallback: () {},
        userRanOutOfSpaceCallback: () {},
      );

      expect(widget.stabilizationRunningInMain, isFalse);
    });

    test('stabilizationRunningInMain can be set to true', () {
      final widget = StabDiffFacePage(
        projectId: 1,
        imageTimestamp: '1234567890',
        reloadImagesInGallery: () async {},
        stabCallback: () {},
        userRanOutOfSpaceCallback: () {},
        stabilizationRunningInMain: true,
      );

      expect(widget.stabilizationRunningInMain, isTrue);
    });

    test('StabDiffFacePage creates state', () {
      final widget = StabDiffFacePage(
        projectId: 1,
        imageTimestamp: '1234567890',
        reloadImagesInGallery: () async {},
        stabCallback: () {},
        userRanOutOfSpaceCallback: () {},
      );

      expect(widget.createState(), isA<StabDiffFacePageState>());
    });
  });

  group('StabDiffFacePage Callbacks', () {
    test('reloadImagesInGallery callback is accessible', () async {
      bool reloadCalled = false;

      final widget = StabDiffFacePage(
        projectId: 1,
        imageTimestamp: '1234567890',
        reloadImagesInGallery: () async {
          reloadCalled = true;
        },
        stabCallback: () {},
        userRanOutOfSpaceCallback: () {},
      );

      await widget.reloadImagesInGallery();
      expect(reloadCalled, isTrue);
    });

    test('stabCallback is accessible', () {
      bool stabCalled = false;

      final widget = StabDiffFacePage(
        projectId: 1,
        imageTimestamp: '1234567890',
        reloadImagesInGallery: () async {},
        stabCallback: () {
          stabCalled = true;
        },
        userRanOutOfSpaceCallback: () {},
      );

      widget.stabCallback();
      expect(stabCalled, isTrue);
    });

    test('userRanOutOfSpaceCallback is accessible', () {
      bool outOfSpaceCalled = false;

      final widget = StabDiffFacePage(
        projectId: 1,
        imageTimestamp: '1234567890',
        reloadImagesInGallery: () async {},
        stabCallback: () {},
        userRanOutOfSpaceCallback: () {
          outOfSpaceCalled = true;
        },
      );

      widget.userRanOutOfSpaceCallback();
      expect(outOfSpaceCalled, isTrue);
    });
  });

  group('FaceContourPainter', () {
    test('FaceContourPainter can be instantiated', () {
      final painter = FaceContourPainter(
        [],
        const Size(100, 100),
        const Size(200, 200),
      );

      expect(painter, isNotNull);
      expect(painter, isA<CustomPainter>());
    });

    test('FaceContourPainter stores parameters', () {
      final painter = FaceContourPainter(
        [],
        const Size(100, 100),
        const Size(200, 200),
      );

      expect(painter.faces, isEmpty);
      expect(painter.originalImageSize, const Size(100, 100));
      expect(painter.displaySize, const Size(200, 200));
    });

    test('calculateContours returns empty list for empty faces', () {
      final contours = FaceContourPainter.calculateContours(
        [],
        const Size(100, 100),
        const Size(200, 200),
      );

      expect(contours, isEmpty);
    });

    test('shouldRepaint returns true when faces change', () {
      final painter1 = FaceContourPainter(
        [],
        const Size(100, 100),
        const Size(200, 200),
      );

      final painter2 = FaceContourPainter(
        ['face'],
        const Size(100, 100),
        const Size(200, 200),
      );

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('shouldRepaint returns true when originalImageSize changes', () {
      final painter1 = FaceContourPainter(
        [],
        const Size(100, 100),
        const Size(200, 200),
      );

      final painter2 = FaceContourPainter(
        [],
        const Size(150, 150),
        const Size(200, 200),
      );

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('shouldRepaint returns true when displaySize changes', () {
      final painter1 = FaceContourPainter(
        [],
        const Size(100, 100),
        const Size(200, 200),
      );

      final painter2 = FaceContourPainter(
        [],
        const Size(100, 100),
        const Size(300, 300),
      );

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('shouldRepaint returns false when same instance values are used', () {
      // Note: List comparison uses reference equality, so same list instance
      // must be used for shouldRepaint to return false
      final sameList = <dynamic>[];
      const sameOriginalSize = Size(100, 100);
      const sameDisplaySize = Size(200, 200);

      final painter1 = FaceContourPainter(
        sameList,
        sameOriginalSize,
        sameDisplaySize,
      );

      final painter2 = FaceContourPainter(
        sameList,
        sameOriginalSize,
        sameDisplaySize,
      );

      expect(painter1.shouldRepaint(painter2), isFalse);
    });

    test('shouldRepaint returns true for different list instances', () {
      // Different list instances (even if empty) trigger repaint
      final painter1 = FaceContourPainter(
        [],
        const Size(100, 100),
        const Size(200, 200),
      );

      final painter2 = FaceContourPainter(
        [],
        const Size(100, 100),
        const Size(200, 200),
      );

      // Different list instances compare as not equal
      expect(painter1.shouldRepaint(painter2), isTrue);
    });
  });
}
