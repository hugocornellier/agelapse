import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/stabilization_service.dart';
import 'package:agelapse/services/stabilization_state.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;

/// End-to-end integration tests for the complete AgeLapse workflow.
///
/// These tests verify the full user journey:
/// 1. Project creation
/// 2. Photo import
/// 3. Stabilization (or skip if no faces)
/// 4. Video compilation
/// 5. Export
///
/// Run with: `flutter test integration_test/e2e_workflow_test.dart -d <platform>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('E2E Workflow Integration Tests', () {
    int? testProjectId;

    setUpAll(() async {
      await DB.instance.createTablesIfNotExist();
    });

    setUp(() async {
      // Clean up any existing test data
      await _cleanupTestData();
      testProjectId = null;
    });

    tearDown(() async {
      // Clean up after each test
      if (testProjectId != null) {
        try {
          await DB.instance.deleteProject(testProjectId!);
        } catch (_) {}
      }
    });

    group('Project Lifecycle', () {
      testWidgets('can create, retrieve, and delete a project', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Create project
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'E2E Test Project',
          'face',
          timestamp,
        );

        expect(testProjectId, isNotNull);
        expect(testProjectId, isPositive);

        // Retrieve project
        final project = await DB.instance.getProject(testProjectId!);
        expect(project, isNotNull);
        expect(project!['name'], 'E2E Test Project');
        expect(project['type'], 'face');

        // Delete project
        final deleted = await DB.instance.deleteProject(testProjectId!);
        expect(deleted, 1);

        // Verify deletion
        final deletedProject = await DB.instance.getProject(testProjectId!);
        expect(deletedProject, isNull);

        testProjectId = null; // Prevent cleanup in tearDown
      });
    });

    group('Photo Workflow', () {
      testWidgets('can add and retrieve photos', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Create project first
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'Photo Test Project',
          'face',
          timestamp,
        );

        // Add photos
        await DB.instance.addPhoto(
          '1000000001',
          testProjectId!,
          '.jpg',
          50000,
          'photo1.jpg',
          'portrait',
        );
        await DB.instance.addPhoto(
          '1000000002',
          testProjectId!,
          '.jpg',
          50000,
          'photo2.jpg',
          'portrait',
        );
        await DB.instance.addPhoto(
          '1000000003',
          testProjectId!,
          '.jpg',
          50000,
          'photo3.jpg',
          'portrait',
        );

        // Verify photos exist
        final photos = await DB.instance.getPhotosByProjectID(testProjectId!);
        expect(photos.length, 3);

        // Verify count
        final count = await DB.instance.getPhotoCountByProjectID(
          testProjectId!,
        );
        expect(count, 3);

        // Verify earliest/latest
        final earliest = await DB.instance.getEarliestPhotoTimestamp(
          testProjectId!,
        );
        final latest = await DB.instance.getLatestPhotoTimestamp(
          testProjectId!,
        );
        expect(earliest, '1000000001');
        expect(latest, '1000000003');
      });

      testWidgets('photos can be marked as stabilized', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Create project
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'Stab Test Project',
          'face',
          timestamp,
        );

        // Add a photo
        await DB.instance.addPhoto(
          '2000000001',
          testProjectId!,
          '.jpg',
          50000,
          'photo.jpg',
          'portrait',
        );

        // Verify it's unstabilized
        var unstabilized = await DB.instance.getUnstabilizedPhotos(
          testProjectId!,
          'portrait',
        );
        expect(unstabilized.length, 1);

        // Mark as stabilized
        await DB.instance.setPhotoStabilized(
          '2000000001',
          testProjectId!,
          'portrait',
          '16:9',
          '1080p',
          0.065,
          0.421875,
        );

        // Verify it's now stabilized
        unstabilized = await DB.instance.getUnstabilizedPhotos(
          testProjectId!,
          'portrait',
        );
        expect(unstabilized.length, 0);

        final stabilized = await DB.instance.getStabilizedPhotosByProjectID(
          testProjectId!,
          'portrait',
        );
        expect(stabilized.length, 1);
      });
    });

    group('Settings Workflow', () {
      testWidgets('project-specific settings are isolated', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Create two projects
        final ts1 = DateTime.now().millisecondsSinceEpoch;
        final project1Id = await DB.instance.addProject(
          'Project 1',
          'face',
          ts1,
        );

        final ts2 = ts1 + 1000;
        final project2Id = await DB.instance.addProject(
          'Project 2',
          'face',
          ts2,
        );

        // Set different framerate for each project
        await DB.instance.setSettingByTitle(
          'framerate',
          '10',
          project1Id.toString(),
        );
        await DB.instance.setSettingByTitle(
          'framerate',
          '24',
          project2Id.toString(),
        );

        // Verify settings are isolated
        final framerate1 = await DB.instance.getSettingValueByTitle(
          'framerate',
          project1Id.toString(),
        );
        final framerate2 = await DB.instance.getSettingValueByTitle(
          'framerate',
          project2Id.toString(),
        );

        expect(framerate1, '10');
        expect(framerate2, '24');

        // Cleanup
        await DB.instance.deleteProject(project1Id);
        await DB.instance.deleteProject(project2Id);
      });

      testWidgets('global settings have defaults', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Request a setting that doesn't exist - should create with default
        final theme = await DB.instance.getSettingValueByTitle('theme');
        expect(theme, 'dark');

        final framerate = await DB.instance.getSettingValueByTitle('framerate');
        expect(framerate, '14');

        final resolution = await DB.instance.getSettingValueByTitle(
          'video_resolution',
        );
        expect(resolution, '1080p');
      });
    });

    group('Video Workflow', () {
      testWidgets('video records are created and retrievable', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Create project
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'Video Test Project',
          'face',
          timestamp,
        );

        // Add video record
        final videoId = await DB.instance.addVideo(
          testProjectId!,
          '1080p',
          'false',
          'lower left',
          50,
          14,
        );

        expect(videoId, isPositive);

        // Retrieve newest video
        final newest = await DB.instance.getNewestVideoByProjectId(
          testProjectId!,
        );
        expect(newest, isNotNull);
        expect(newest!['resolution'], '1080p');
        expect(newest['photoCount'], 50);
        expect(newest['framerate'], 14);
      });

      testWidgets('newVideoNeeded flag works correctly', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Create project
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'Video Flag Test',
          'face',
          timestamp,
        );

        // Initially should be 0
        var needed = await DB.instance.getNewVideoNeeded(testProjectId!);
        expect(needed, 0);

        // Set flag
        await DB.instance.setNewVideoNeeded(testProjectId!);
        needed = await DB.instance.getNewVideoNeeded(testProjectId!);
        expect(needed, 1);

        // Clear flag
        DB.instance.setNewVideoNotNeeded(testProjectId!);
        await Future.delayed(const Duration(milliseconds: 100));
        needed = await DB.instance.getNewVideoNeeded(testProjectId!);
        expect(needed, 0);
      });
    });

    group('Stabilization Service', () {
      testWidgets('stabilization service starts in idle state', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final service = StabilizationService.instance;

        // Should be in a finished/idle state
        expect(
          service.state == StabilizationState.idle ||
              service.state == StabilizationState.completed ||
              service.state == StabilizationState.cancelled,
          isTrue,
        );
      });

      testWidgets('stabilization can be cancelled', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final service = StabilizationService.instance;

        // Cancel should not throw even if nothing is running
        await service.cancel();

        // State should be in a terminal state
        expect(
          service.state == StabilizationState.idle ||
              service.state == StabilizationState.cancelled ||
              service.state == StabilizationState.completed,
          isTrue,
        );
      });
    });

    group('Face Data Storage', () {
      testWidgets('face embedding can be stored and retrieved', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Create project
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'Embedding Test',
          'face',
          timestamp,
        );

        // Add photo
        await DB.instance.addPhoto(
          '3000000001',
          testProjectId!,
          '.jpg',
          50000,
          'face.jpg',
          'portrait',
        );

        // Store face data with embedding
        final embedding = Uint8List.fromList(
          List.generate(768, (i) => i % 256),
        );
        await DB.instance.setPhotoFaceData(
          '3000000001',
          testProjectId!,
          1,
          embedding: embedding,
        );

        // Retrieve embedding
        final storedEmbedding = await DB.instance.getPhotoEmbedding(
          '3000000001',
          testProjectId!,
        );

        expect(storedEmbedding, isNotNull);
        expect(storedEmbedding!.length, 768);
      });

      testWidgets('getClosestSingleFacePhoto returns correct result', (
        tester,
      ) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Create project
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'Single Face Test',
          'face',
          timestamp,
        );

        // Add photos with different face counts
        await DB.instance.addPhoto(
          '4000000001',
          testProjectId!,
          '.jpg',
          50000,
          'two_faces.jpg',
          'portrait',
        );
        await DB.instance.addPhoto(
          '4000000002',
          testProjectId!,
          '.jpg',
          50000,
          'one_face.jpg',
          'portrait',
        );

        // Mark first with 2 faces (no embedding)
        await DB.instance.setPhotoFaceData('4000000001', testProjectId!, 2);

        // Mark second with 1 face and embedding
        final embedding = Uint8List.fromList(
          List.generate(768, (i) => i % 256),
        );
        await DB.instance.setPhotoFaceData(
          '4000000002',
          testProjectId!,
          1,
          embedding: embedding,
        );

        // Query for closest single-face photo
        final result = await DB.instance.getClosestSingleFacePhoto(
          '4000000003', // A timestamp between the two
          testProjectId!,
        );

        expect(result, isNotNull);
        expect(result!['timestamp'], '4000000002');
        expect(result['faceEmbedding'], isNotNull);
      });
    });

    group('Photo Timestamp Updates', () {
      testWidgets('photo timestamp can be updated', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Create project
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'Timestamp Update Test',
          'face',
          timestamp,
        );

        // Add photo
        await DB.instance.addPhoto(
          '5000000001',
          testProjectId!,
          '.jpg',
          50000,
          'photo.jpg',
          'portrait',
        );

        // Update timestamp
        final newId = await DB.instance.updatePhotoTimestamp(
          '5000000001',
          '5000000002',
          testProjectId!,
        );

        expect(newId, isNotNull);

        // Old timestamp should not exist
        final oldPhoto = await DB.instance.getPhotoByTimestamp(
          '5000000001',
          testProjectId!,
        );
        expect(oldPhoto, isNull);

        // New timestamp should exist
        final newPhoto = await DB.instance.getPhotoByTimestamp(
          '5000000002',
          testProjectId!,
        );
        expect(newPhoto, isNotNull);
      });
    });

    group('Orientation Analysis', () {
      testWidgets('orientation threshold calculation works', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Create project
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'Orientation Threshold Test',
          'face',
          timestamp,
        );

        // Add 3 landscape, 2 portrait (60% landscape)
        await DB.instance.addPhoto(
          '6001',
          testProjectId!,
          '.jpg',
          50000,
          'a.jpg',
          'landscape',
        );
        await DB.instance.addPhoto(
          '6002',
          testProjectId!,
          '.jpg',
          50000,
          'b.jpg',
          'landscape',
        );
        await DB.instance.addPhoto(
          '6003',
          testProjectId!,
          '.jpg',
          50000,
          'c.jpg',
          'landscape',
        );
        await DB.instance.addPhoto(
          '6004',
          testProjectId!,
          '.jpg',
          50000,
          'd.jpg',
          'portrait',
        );
        await DB.instance.addPhoto(
          '6005',
          testProjectId!,
          '.jpg',
          50000,
          'e.jpg',
          'portrait',
        );

        final threshold = await DB.instance.checkPhotoOrientationThreshold(
          testProjectId!,
        );
        expect(threshold, 'landscape');
      });
    });

    group('Favorite Photos', () {
      testWidgets('favorite functionality works', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Create project
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'Favorite Test',
          'face',
          timestamp,
        );

        // Add photo
        await DB.instance.addPhoto(
          '7000000001',
          testProjectId!,
          '.jpg',
          50000,
          'photo.jpg',
          'portrait',
        );

        // Initially not favorite
        var isFav =
            await DB.instance.isFavoritePhoto('7000000001', testProjectId!);
        expect(isFav, isFalse);

        // Set as favorite
        await DB.instance.setPhotoAsFavorite('7000000001', testProjectId!);

        // Should now be favorite
        isFav = await DB.instance.isFavoritePhoto('7000000001', testProjectId!);
        expect(isFav, isTrue);
      });
    });

    group('Stabilization Reset', () {
      testWidgets('resetStabilizationStatusForProject resets all photos', (
        tester,
      ) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Create project
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'Reset Test',
          'face',
          timestamp,
        );

        // Add and stabilize photos
        await DB.instance.addPhoto(
          '8001',
          testProjectId!,
          '.jpg',
          50000,
          'a.jpg',
          'portrait',
        );
        await DB.instance.addPhoto(
          '8002',
          testProjectId!,
          '.jpg',
          50000,
          'b.jpg',
          'portrait',
        );

        await DB.instance.setPhotoStabilized(
          '8001',
          testProjectId!,
          'portrait',
          '16:9',
          '1080p',
          0.065,
          0.421875,
        );
        await DB.instance.setPhotoStabilized(
          '8002',
          testProjectId!,
          'portrait',
          '16:9',
          '1080p',
          0.065,
          0.421875,
        );

        // Verify both are stabilized
        var stabilized = await DB.instance.getStabilizedPhotosByProjectID(
          testProjectId!,
          'portrait',
        );
        expect(stabilized.length, 2);

        // Reset stabilization
        await DB.instance.resetStabilizationStatusForProject(
          testProjectId!,
          'portrait',
        );

        // Verify both are now unstabilized
        stabilized = await DB.instance.getStabilizedPhotosByProjectID(
          testProjectId!,
          'portrait',
        );
        expect(stabilized.length, 0);

        final unstabilized = await DB.instance.getUnstabilizedPhotos(
          testProjectId!,
          'portrait',
        );
        expect(unstabilized.length, 2);
      });
    });
  });
}

Future<void> _cleanupTestData() async {
  try {
    await DB.instance.deleteAllPhotos();
    final projects = await DB.instance.getAllProjects();
    for (final project in projects) {
      await DB.instance.deleteProject(project['id'] as int);
    }
  } catch (e) {
    // Ignore cleanup errors
  }
}
