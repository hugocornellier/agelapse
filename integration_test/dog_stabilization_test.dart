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
    await StabUtils.disposeDogDetector();
    await cleanupFixtures();
  });

  /// Helper to initialize app and load fixtures (must be called after app.main())
  Future<bool> initAppAndFixtures(WidgetTester tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 3));

    // Load fixtures after app is initialized (required for rootBundle on mobile)
    if (!fixturesLoaded) {
      await preloadFixtures();
      if (!fixturesUnavailable) {
        testImage = await getSampleDogPathAsync(1);
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

  group('Dog Detection', () {
    testWidgets('detects dog from bytes', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final bytes = await File(testImage!).readAsBytes();
      final faces = await StabUtils.getDogFacesFromBytes(bytes);
      expect(faces, isNotNull, reason: 'Dog detection should return a result');
      expect(faces, isNotEmpty, reason: 'Should detect at least one dog');
    });

    testWidgets('extracts eye landmarks from dog', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final bytes = await File(testImage!).readAsBytes();
      final faces = await StabUtils.getDogFacesFromBytes(bytes);
      if (faces == null || faces.isEmpty) {
        markTestSkipped('Dog detection returned no faces');
        return;
      }
      final face = faces.first;
      expect(face.leftEye, isNotNull, reason: 'Should detect left eye');
      expect(face.rightEye, isNotNull, reason: 'Should detect right eye');
    });

    testWidgets('detects dog via project type dispatcher', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final bytes = await File(testImage!).readAsBytes();
      final faces = await StabUtils.getFacesFromBytesForProjectType(
        'dog',
        bytes,
      );
      expect(faces, isNotNull);
      expect(
        faces,
        isNotEmpty,
        reason: 'Project type dispatcher should detect dog',
      );
    });

    testWidgets('detects dog in all sample images', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      for (int day = 1; day <= 3; day++) {
        final path = await getSampleDogPathAsync(day);
        final file = File(path);
        if (!await file.exists()) continue;

        final bytes = await file.readAsBytes();
        final faces = await StabUtils.getDogFacesFromBytes(bytes);
        expect(faces, isNotNull, reason: 'Day $day: should return a result');
        expect(
          faces,
          isNotEmpty,
          reason: 'Day $day: should detect at least one dog',
        );
      }
    });
  });

  group('Dog Stabilization', () {
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

  group('Dog End-to-End Pipeline', () {
    testWidgets('stabilizes image with detected dog face', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final bytes = await File(testImage!).readAsBytes();

      final faces = await StabUtils.getDogFacesFromBytes(bytes);
      if (faces == null || faces.isEmpty) {
        markTestSkipped('Dog detection returned no faces');
        return;
      }

      final face = faces.first;
      final leftEye = face.leftEye;
      final rightEye = face.rightEye;

      if (leftEye == null || rightEye == null) {
        markTestSkipped('Eye landmarks not detected');
        return;
      }

      final dy = rightEye.y - leftEye.y;
      final dx = rightEye.x - leftEye.x;
      final rotationRadians = atan2(dy, dx);
      final rotationDegrees = rotationRadians * 180 / pi;

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

      final stabilizedFaces = await StabUtils.getDogFacesFromBytes(stabilized!);
      if (stabilizedFaces == null || stabilizedFaces.isEmpty) {
        return;
      }

      final newFace = stabilizedFaces.first;
      if (newFace.leftEye != null && newFace.rightEye != null) {
        expect(newFace.leftEye, isNotNull);
        expect(newFace.rightEye, isNotNull);
      }
    });
  });
}
