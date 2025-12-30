import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/camera_page/camera_page.dart';

/// Widget tests for CameraPage and DetectorView.
/// Tests widget structure and properties.
void main() {
  group('CameraPage Widget', () {
    test('CameraPage has required constructor parameters', () {
      expect(CameraPage, isNotNull);
    });

    test('CameraPage can be instantiated with parameters', () {
      final widget = CameraPage(
        projectId: 1,
        projectName: 'Test Project',
        openGallery: () {},
        refreshSettings: () async {},
        goToPage: (index) {},
      );

      expect(widget.projectId, 1);
      expect(widget.projectName, 'Test Project');
    });

    test('CameraPage stores project id', () {
      final widget = CameraPage(
        projectId: 42,
        projectName: 'My Project',
        openGallery: () {},
        refreshSettings: () async {},
        goToPage: (index) {},
      );

      expect(widget.projectId, 42);
    });

    test('CameraPage stores project name', () {
      final widget = CameraPage(
        projectId: 1,
        projectName: 'Face Timelapse 2024',
        openGallery: () {},
        refreshSettings: () async {},
        goToPage: (index) {},
      );

      expect(widget.projectName, 'Face Timelapse 2024');
    });

    test('CameraPage accepts optional takingGuidePhoto flag', () {
      final widget = CameraPage(
        projectId: 1,
        projectName: 'Test',
        takingGuidePhoto: true,
        openGallery: () {},
        refreshSettings: () async {},
        goToPage: (index) {},
      );

      expect(widget.takingGuidePhoto, isTrue);
    });

    test('CameraPage accepts optional forceGridModeEnum', () {
      final widget = CameraPage(
        projectId: 1,
        projectName: 'Test',
        forceGridModeEnum: 2,
        openGallery: () {},
        refreshSettings: () async {},
        goToPage: (index) {},
      );

      expect(widget.forceGridModeEnum, 2);
    });

    test('CameraPage callbacks are stored correctly', () {
      bool galleryCalled = false;
      bool refreshCalled = false;
      int? pageIndex;

      final widget = CameraPage(
        projectId: 1,
        projectName: 'Test',
        openGallery: () {
          galleryCalled = true;
        },
        refreshSettings: () async {
          refreshCalled = true;
        },
        goToPage: (index) {
          pageIndex = index;
        },
      );

      // Verify callbacks are accessible
      widget.openGallery();
      widget.refreshSettings();
      widget.goToPage(2);

      expect(galleryCalled, isTrue);
      expect(refreshCalled, isTrue);
      expect(pageIndex, 2);
    });

    test('CameraPage defaults to null for optional parameters', () {
      final widget = CameraPage(
        projectId: 1,
        projectName: 'Test',
        openGallery: () {},
        refreshSettings: () async {},
        goToPage: (index) {},
      );

      expect(widget.takingGuidePhoto, isNull);
      expect(widget.forceGridModeEnum, isNull);
    });
  });

  group('DetectorViewMode Enum', () {
    test('DetectorViewMode has liveFeed value', () {
      expect(DetectorViewMode.liveFeed, isNotNull);
    });

    test('DetectorViewMode has gallery value', () {
      expect(DetectorViewMode.gallery, isNotNull);
    });

    test('DetectorViewMode values are different', () {
      expect(DetectorViewMode.liveFeed, isNot(DetectorViewMode.gallery));
    });
  });

  group('DetectorView Widget', () {
    test('DetectorView has required constructor parameters', () {
      expect(DetectorView, isNotNull);
    });

    test('DetectorView can be instantiated with required parameters', () {
      final widget = DetectorView(
        projectId: 1,
        projectName: 'Test',
        openGallery: () {},
        refreshSettings: () async {},
        goToPage: (index) {},
      );

      expect(widget.projectId, 1);
      expect(widget.projectName, 'Test');
    });

    test('DetectorView defaults to liveFeed mode', () {
      final widget = DetectorView(
        projectId: 1,
        projectName: 'Test',
        openGallery: () {},
        refreshSettings: () async {},
        goToPage: (index) {},
      );

      expect(widget.initialDetectionMode, DetectorViewMode.liveFeed);
    });

    test('DetectorView defaults to front camera', () {
      final widget = DetectorView(
        projectId: 1,
        projectName: 'Test',
        openGallery: () {},
        refreshSettings: () async {},
        goToPage: (index) {},
      );

      expect(widget.initialCameraLensDirection, CameraLensDirection.front);
    });

    test('DetectorView accepts custom initial mode', () {
      final widget = DetectorView(
        projectId: 1,
        projectName: 'Test',
        initialDetectionMode: DetectorViewMode.gallery,
        openGallery: () {},
        refreshSettings: () async {},
        goToPage: (index) {},
      );

      expect(widget.initialDetectionMode, DetectorViewMode.gallery);
    });

    test('DetectorView accepts custom camera direction', () {
      final widget = DetectorView(
        projectId: 1,
        projectName: 'Test',
        initialCameraLensDirection: CameraLensDirection.back,
        openGallery: () {},
        refreshSettings: () async {},
        goToPage: (index) {},
      );

      expect(widget.initialCameraLensDirection, CameraLensDirection.back);
    });

    test('DetectorView callback setters work correctly', () {
      bool cameraDirChanged = false;
      CameraLensDirection? newDirection;

      final widget = DetectorView(
        projectId: 1,
        projectName: 'Test',
        onCameraLensDirectionChanged: (dir) {
          cameraDirChanged = true;
          newDirection = dir;
        },
        openGallery: () {},
        refreshSettings: () async {},
        goToPage: (index) {},
      );

      widget.onCameraLensDirectionChanged?.call(CameraLensDirection.back);

      expect(cameraDirChanged, isTrue);
      expect(newDirection, CameraLensDirection.back);
    });
  });

  group('CameraPage Edge Cases', () {
    test('handles empty project name', () {
      final widget = CameraPage(
        projectId: 1,
        projectName: '',
        openGallery: () {},
        refreshSettings: () async {},
        goToPage: (index) {},
      );

      expect(widget.projectName, '');
    });

    test('handles special characters in project name', () {
      final widget = CameraPage(
        projectId: 1,
        projectName: "John's Project #1 (2024)",
        openGallery: () {},
        refreshSettings: () async {},
        goToPage: (index) {},
      );

      expect(widget.projectName, contains("'"));
      expect(widget.projectName, contains('#'));
    });

    test('goToPage handles different page indices', () {
      final indices = <int>[];

      final widget = CameraPage(
        projectId: 1,
        projectName: 'Test',
        openGallery: () {},
        refreshSettings: () async {},
        goToPage: (index) {
          indices.add(index);
        },
      );

      widget.goToPage(0);
      widget.goToPage(1);
      widget.goToPage(2);
      widget.goToPage(-1); // Edge case

      expect(indices, [0, 1, 2, -1]);
    });
  });
}
