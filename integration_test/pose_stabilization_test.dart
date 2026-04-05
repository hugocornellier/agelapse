import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/utils/stabilizer_utils/stabilizer_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:pose_detection/pose_detection.dart';

import 'test_utils.dart';

void main() {
  test_config.isTestMode = true;

  late PoseDetector detector;
  bool fixturesLoaded = false;
  bool detectorInitialized = false;

  tearDownAll(() async {
    if (detectorInitialized) {
      await detector.dispose();
    }
    await cleanupFixtures();
  });

  Future<bool> initAppAndFixtures(WidgetTester tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 3));

    if (!fixturesLoaded) {
      await preloadFixtures();
      fixturesLoaded = true;
    }

    if (fixturesUnavailable) {
      markTestSkipped('Test fixtures not available on this platform');
      return false;
    }

    if (!detectorInitialized) {
      detector = PoseDetector(
        mode: PoseMode.boxesAndLandmarks,
        landmarkModel: PoseLandmarkModel.lite,
      );
      await detector.initialize();
      detectorInitialized = true;
    }

    return true;
  }

  Future<List<Pose>> detectPosesFromFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return await detector.detect(bytes);
  }

  // ---------------------------------------------------------------------------
  // Multi-person detection
  // ---------------------------------------------------------------------------
  group('Multi-Person Pose Detection', () {
    testWidgets('detects 2 people in two_people.jpeg', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('two_people.jpeg');
      if (!await File(path).exists()) {
        markTestSkipped('two_people.jpeg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      expect(poses.length, 2, reason: 'Expected 2 people in skaters image');
    });

    testWidgets('both people have landmarks', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('two_people.jpeg');
      if (!await File(path).exists()) {
        markTestSkipped('two_people.jpeg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      expect(poses.length, 2);

      for (int i = 0; i < poses.length; i++) {
        expect(
          poses[i].hasLandmarks,
          true,
          reason: 'Person $i should have landmarks',
        );
        expect(
          poses[i].landmarks.length,
          33,
          reason: 'Person $i should have 33 landmarks',
        );
      }
    });

    testWidgets('bounding boxes do not overlap excessively', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('two_people.jpeg');
      if (!await File(path).exists()) {
        markTestSkipped('two_people.jpeg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      expect(poses.length, 2);

      final bb0 = poses[0].boundingBox;
      final bb1 = poses[1].boundingBox;

      final overlapLeft = bb0.left > bb1.left ? bb0.left : bb1.left;
      final overlapTop = bb0.top > bb1.top ? bb0.top : bb1.top;
      final overlapRight = bb0.right < bb1.right ? bb0.right : bb1.right;
      final overlapBottom = bb0.bottom < bb1.bottom ? bb0.bottom : bb1.bottom;

      final overlapW = (overlapRight - overlapLeft).clamp(0, double.infinity);
      final overlapH = (overlapBottom - overlapTop).clamp(0, double.infinity);
      final overlapArea = overlapW * overlapH;

      final area0 = (bb0.right - bb0.left) * (bb0.bottom - bb0.top);
      final area1 = (bb1.right - bb1.left) * (bb1.bottom - bb1.top);
      final minArea = area0 < area1 ? area0 : area1;

      if (minArea > 0) {
        expect(
          overlapArea / minArea,
          lessThan(0.5),
          reason: 'Bounding boxes overlap too much',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Pregnancy mode: nose + rightAnkle stabilization
  // ---------------------------------------------------------------------------
  group('Pregnancy Pose Detection', () {
    testWidgets('pregnancy1 detects at least 1 person', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('pregnancy1.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('pregnancy1.jpg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      expect(poses, isNotEmpty, reason: 'Expected at least 1 person');
    });

    testWidgets('pregnancy1 has nose and rightAnkle', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('pregnancy1.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('pregnancy1.jpg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      expect(poses, isNotEmpty);
      final pose = poses.first;
      expect(pose.hasLandmarks, true);

      final nose = pose.getLandmark(PoseLandmarkType.nose);
      final rightAnkle = pose.getLandmark(PoseLandmarkType.rightAnkle);

      expect(nose, isNotNull, reason: 'Nose not detected');
      expect(rightAnkle, isNotNull, reason: 'Right ankle not detected');
      expect(
        nose!.y,
        lessThan(rightAnkle!.y),
        reason: 'Nose should be above right ankle',
      );
    });

    testWidgets('pregnancy2 detects at least 1 person', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('pregnancy2.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('pregnancy2.jpg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      expect(poses, isNotEmpty, reason: 'Expected at least 1 person');
    });

    testWidgets('pregnancy2 has nose and rightAnkle', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('pregnancy2.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('pregnancy2.jpg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      expect(poses, isNotEmpty);
      final pose = poses.first;
      expect(pose.hasLandmarks, true);

      final nose = pose.getLandmark(PoseLandmarkType.nose);
      final rightAnkle = pose.getLandmark(PoseLandmarkType.rightAnkle);

      expect(nose, isNotNull, reason: 'Nose not detected');
      expect(rightAnkle, isNotNull, reason: 'Right ankle not detected');
      expect(
        nose!.y,
        lessThan(rightAnkle!.y),
        reason: 'Nose should be above right ankle',
      );
    });

    testWidgets('pregnancy landmarks have reasonable visibility', (
      tester,
    ) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('pregnancy1.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('pregnancy1.jpg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      final pose = poses.first;
      final nose = pose.getLandmark(PoseLandmarkType.nose)!;
      final rightAnkle = pose.getLandmark(PoseLandmarkType.rightAnkle)!;

      expect(
        nose.visibility,
        greaterThan(0.5),
        reason: 'Nose visibility too low for pregnancy stabilization',
      );
      expect(
        rightAnkle.visibility,
        greaterThan(0.3),
        reason: 'Right ankle visibility too low for pregnancy stabilization',
      );
    });

    testWidgets('full body chain present (nose to ankles)', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('pregnancy2.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('pregnancy2.jpg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      final pose = poses.first;

      final chain = [
        PoseLandmarkType.nose,
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      ];

      for (final type in chain) {
        expect(
          pose.getLandmark(type),
          isNotNull,
          reason: '$type missing from full body chain',
        );
      }
    });

    testWidgets('pregnancy scale factor inputs are computable', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('pregnancy1.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('pregnancy1.jpg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      final pose = poses.first;
      final nose = pose.getLandmark(PoseLandmarkType.nose)!;
      final rightAnkle = pose.getLandmark(PoseLandmarkType.rightAnkle)!;

      // Replicate the pregnancy scale computation from FaceStabilizer
      final dx = (rightAnkle.x - nose.x).abs();
      final dy = (rightAnkle.y - nose.y).abs();
      final hypotenuse = sqrt(dx * dx + dy * dy);

      expect(
        hypotenuse,
        greaterThan(0),
        reason: 'Nose-to-ankle distance is zero — cannot compute scale',
      );

      // Rotation should be computable (non-NaN)
      final rotationRaw = 90 - (atan2(dy, dx) * (180 / pi));
      expect(
        rotationRaw.isNaN,
        false,
        reason: 'Rotation calculation produced NaN',
      );
      expect(
        rotationRaw.isInfinite,
        false,
        reason: 'Rotation calculation produced infinity',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Muscle mode: leftHip + rightHip stabilization
  // ---------------------------------------------------------------------------
  group('Muscle Pose Detection', () {
    testWidgets('muscle1 detects at least 1 person', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('muscle1.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('muscle1.jpg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      expect(poses, isNotEmpty, reason: 'Expected at least 1 person');
    });

    testWidgets('muscle1 has leftHip and rightHip', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('muscle1.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('muscle1.jpg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      expect(poses, isNotEmpty);
      final pose = poses.first;
      expect(pose.hasLandmarks, true);

      final leftHip = pose.getLandmark(PoseLandmarkType.leftHip);
      final rightHip = pose.getLandmark(PoseLandmarkType.rightHip);

      expect(leftHip, isNotNull, reason: 'Left hip not detected');
      expect(rightHip, isNotNull, reason: 'Right hip not detected');
    });

    testWidgets('muscle2 detects at least 1 person', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('muscle2.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('muscle2.jpg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      expect(poses, isNotEmpty, reason: 'Expected at least 1 person');
    });

    testWidgets('muscle2 has leftHip and rightHip', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('muscle2.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('muscle2.jpg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      expect(poses, isNotEmpty);
      final pose = poses.first;
      expect(pose.hasLandmarks, true);

      final leftHip = pose.getLandmark(PoseLandmarkType.leftHip);
      final rightHip = pose.getLandmark(PoseLandmarkType.rightHip);

      expect(leftHip, isNotNull, reason: 'Left hip not detected');
      expect(rightHip, isNotNull, reason: 'Right hip not detected');
    });

    testWidgets('muscle landmarks have reasonable visibility', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('muscle2.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('muscle2.jpg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      final pose = poses.first;
      final leftHip = pose.getLandmark(PoseLandmarkType.leftHip)!;
      final rightHip = pose.getLandmark(PoseLandmarkType.rightHip)!;

      expect(
        leftHip.visibility,
        greaterThan(0.3),
        reason: 'Left hip visibility too low for muscle stabilization',
      );
      expect(
        rightHip.visibility,
        greaterThan(0.3),
        reason: 'Right hip visibility too low for muscle stabilization',
      );
    });

    testWidgets('muscle scale factor inputs are computable', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('muscle1.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('muscle1.jpg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      final pose = poses.first;
      final leftHip = pose.getLandmark(PoseLandmarkType.leftHip)!;
      final rightHip = pose.getLandmark(PoseLandmarkType.rightHip)!;

      // Replicate the muscle scale computation from FaceStabilizer
      final dx = (rightHip.x - leftHip.x).abs();
      final dy = (rightHip.y - leftHip.y).abs();
      final hypotenuse = sqrt(dx * dx + dy * dy);

      expect(
        hypotenuse,
        greaterThan(0),
        reason: 'Hip-to-hip distance is zero — cannot compute scale',
      );

      // Rotation should be computable
      final rotationDegrees =
          atan2(dy, dx) * (180 / pi) * (rightHip.y > leftHip.y ? -1 : 1);
      expect(
        rotationDegrees.isNaN,
        false,
        reason: 'Rotation calculation produced NaN',
      );
    });

    testWidgets('upper body landmarks present for dynamic poses', (
      tester,
    ) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('muscle2.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('muscle2.jpg not found');
        return;
      }

      final poses = await detectPosesFromFile(path);
      final pose = poses.first;

      final upperBody = [
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.leftWrist,
        PoseLandmarkType.rightWrist,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
      ];

      for (final type in upperBody) {
        expect(
          pose.getLandmark(type),
          isNotNull,
          reason: '$type missing from upper body',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Pose Stabilization (shared image transform pipeline)
  // ---------------------------------------------------------------------------
  group('Pose Stabilization Pipeline', () {
    testWidgets('generates stabilized image bytes', (tester) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('pregnancy1.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('pregnancy1.jpg not found');
        return;
      }

      final bytes = await File(path).readAsBytes();

      final result = await StabUtils.generateStabilizedImageBytesCVAsync(
        bytes,
        5.0,
        1.1,
        10.0,
        20.0,
        1920,
        1080,
      );

      expect(result, isNotNull);
      expect(result!.length, greaterThan(0));
    });

    testWidgets('pregnancy end-to-end: detect → compute → stabilize', (
      tester,
    ) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('pregnancy1.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('pregnancy1.jpg not found');
        return;
      }

      final bytes = await File(path).readAsBytes();
      final poses = await detector.detect(bytes);
      if (poses.isEmpty || !poses.first.hasLandmarks) {
        markTestSkipped('Pose detection returned no landmarks');
        return;
      }

      final pose = poses.first;
      final nose = pose.getLandmark(PoseLandmarkType.nose);
      final rightAnkle = pose.getLandmark(PoseLandmarkType.rightAnkle);
      if (nose == null || rightAnkle == null) {
        markTestSkipped('Nose or right ankle not detected');
        return;
      }

      // Compute pregnancy stabilization params (matching FaceStabilizer logic)
      final dy = (rightAnkle.y - nose.y).abs();
      final dx = (rightAnkle.x - nose.x).abs();
      final hypotenuse = sqrt(dx * dx + dy * dy);
      final scaleFactor = 800.0 / hypotenuse; // bodyDistanceGoal analog
      final rotationRaw = 90 - (atan2(dy, dx) * (180 / pi));
      final rotationDegrees = 6.0 - rotationRaw; // rotationGoal analog

      final stabilized = await StabUtils.generateStabilizedImageBytesCVAsync(
        bytes,
        rotationDegrees,
        scaleFactor,
        0.0,
        0.0,
        1920,
        1080,
      );

      expect(stabilized, isNotNull);
      expect(stabilized!.length, greaterThan(0));
    });

    testWidgets('muscle end-to-end: detect → compute → stabilize', (
      tester,
    ) async {
      if (!await initAppAndFixtures(tester)) return;

      final path = await getSamplePosePathAsync('muscle1.jpg');
      if (!await File(path).exists()) {
        markTestSkipped('muscle1.jpg not found');
        return;
      }

      final bytes = await File(path).readAsBytes();
      final poses = await detector.detect(bytes);
      if (poses.isEmpty || !poses.first.hasLandmarks) {
        markTestSkipped('Pose detection returned no landmarks');
        return;
      }

      final pose = poses.first;
      final leftHip = pose.getLandmark(PoseLandmarkType.leftHip);
      final rightHip = pose.getLandmark(PoseLandmarkType.rightHip);
      if (leftHip == null || rightHip == null) {
        markTestSkipped('Hips not detected');
        return;
      }

      // Compute muscle stabilization params (matching FaceStabilizer logic)
      final dy = (rightHip.y - leftHip.y).abs();
      final dx = (rightHip.x - leftHip.x).abs();
      final hypotenuse = sqrt(dx * dx + dy * dy);
      final scaleFactor = 200.0 / hypotenuse; // eyeDistanceGoal analog
      final rotationDegrees =
          atan2(dy, dx) * (180 / pi) * (rightHip.y > leftHip.y ? -1 : 1);

      final stabilized = await StabUtils.generateStabilizedImageBytesCVAsync(
        bytes,
        rotationDegrees,
        scaleFactor,
        0.0,
        0.0,
        1920,
        1080,
      );

      expect(stabilized, isNotNull);
      expect(stabilized!.length, greaterThan(0));
    });
  });
}
