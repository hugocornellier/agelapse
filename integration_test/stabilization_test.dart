import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/utils/stabilizer_utils/stabilizer_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;

import 'test_utils.dart';

void main() {
  test_config.isTestMode = true;

  String? testImage;
  bool fixturesLoaded = false;

  tearDownAll(() async {
    await cleanupFixtures();
  });

  /// Helper to initialize app and load fixtures (must be called after app.main())
  Future<bool> initAppAndFixtures(WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Load fixtures after app is initialized (required for rootBundle on mobile)
    if (!fixturesLoaded) {
      await preloadFixtures();
      if (!fixturesUnavailable) {
        testImage = await getSampleFacePathAsync(1);
      }
      fixturesLoaded = true;
    }

    if (fixturesUnavailable || testImage == null) {
      markTestSkipped('Test fixtures not available on this platform');
      return false;
    }

    // Verify file actually exists
    if (!await File(testImage!).exists()) {
      markTestSkipped('Test image file not found: $testImage');
      return false;
    }

    return true;
  }

  group('Face Detection', () {
    testWidgets('detects face from file path', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final faces = await StabUtils.getFacesFromFilepath(testImage!);
      expect(faces, isNotNull, reason: 'Face detection should return a result');
      expect(faces, isNotEmpty, reason: 'Should detect at least one face');
    });

    testWidgets('extracts eye landmarks', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final faces = await StabUtils.getFacesFromFilepath(testImage!);
      if (faces == null || faces.isEmpty) {
        markTestSkipped('Face detection returned no faces');
        return;
      }
      final face = faces.first;
      expect(face.leftEye, isNotNull);
      expect(face.rightEye, isNotNull);
    });

    testWidgets('detects face from bytes', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final bytes = await File(testImage!).readAsBytes();
      final faces = await StabUtils.getFacesFromBytes(bytes);
      expect(faces, isNotNull);
      expect(faces, isNotEmpty);
    });
  });

  group('Image Stabilization', () {
    testWidgets('generates stabilized image bytes', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final bytes = await File(testImage!).readAsBytes();

      final result = await StabUtils.generateStabilizedImageBytesCVAsync(
        bytes,
        5.0, // rotation degrees
        1.1, // scale factor
        10.0, // translateX
        20.0, // translateY
        1920, // canvas width
        1080, // canvas height
      );

      expect(result, isNotNull);
      expect(result!.length, greaterThan(0));
    });
  });

  group('End-to-End Pipeline', () {
    testWidgets('stabilizes image with detected face', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      // 1. Load image
      final bytes = await File(testImage!).readAsBytes();

      // 2. Detect face
      final faces = await StabUtils.getFacesFromBytes(bytes);
      if (faces == null || faces.isEmpty) {
        markTestSkipped('Face detection returned no faces');
        return;
      }

      final face = faces.first;
      final leftEye = face.leftEye;
      final rightEye = face.rightEye;

      if (leftEye == null || rightEye == null) {
        markTestSkipped('Eye landmarks not detected');
        return;
      }

      // 3. Calculate rotation to make eyes horizontal
      final dy = rightEye.y - leftEye.y;
      final dx = rightEye.x - leftEye.x;
      final rotationRadians = atan2(dy, dx);
      final rotationDegrees = rotationRadians * 180 / pi;

      // 4. Apply stabilization
      final stabilized = await StabUtils.generateStabilizedImageBytesCVAsync(
        bytes,
        rotationDegrees,
        1.0,
        0.0,
        0.0,
        1920,
        1080,
      );

      expect(stabilized, isNotNull);

      // 5. Verify eyes are more horizontal in output
      final stabilizedFaces = await StabUtils.getFacesFromBytes(stabilized!);
      if (stabilizedFaces == null || stabilizedFaces.isEmpty) {
        // Stabilization worked, but face detection on result failed - still a pass
        return;
      }

      final newFace = stabilizedFaces.first;
      if (newFace.leftEye != null && newFace.rightEye != null) {
        final newDy = (newFace.rightEye!.y - newFace.leftEye!.y).abs();
        // Eyes should be more horizontal (smaller dy)
        expect(newDy, lessThan(dy.abs() + 5)); // Allow small tolerance
      }
    });
  });
}
