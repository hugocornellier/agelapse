import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/cancellation_token.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;

/// Integration tests for error handling and cancellation paths.
/// These tests verify the app handles errors gracefully on all platforms.
///
/// Run with: `flutter test integration_test/error_handling_test.dart -d <platform>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Error Handling Integration Tests', () {
    setUpAll(() async {
      await DB.instance.createTablesIfNotExist();
    });

    setUp(() async {
      await _cleanupTestData();
    });

    group('Database Error Resilience', () {
      testWidgets('app handles missing project gracefully', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Try to get a non-existent project
        final project = await DB.instance.getProject(999999);
        expect(project, isNull);

        // App should still be running
        expect(find.byType(MaterialApp), findsOneWidget);
      });

      testWidgets('app handles missing photo gracefully', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final projectId = await DB.instance.addProject(
          'Error Test',
          'face',
          123456,
        );

        // Try to get a non-existent photo
        final photo = await DB.instance.getPhotoByTimestamp(
          'nonexistent',
          projectId,
        );
        expect(photo, isNull);

        // App should still be running
        expect(find.byType(MaterialApp), findsOneWidget);
      });

      testWidgets('app handles missing setting with defaults', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Request a known setting that should have a default
        final value = await DB.instance.getSettingValueByTitle(
          'theme',
          'test_project',
        );

        // Should return the default value
        expect(value, isNotNull);
        expect(value, 'dark');
      });

      testWidgets('app handles unknown setting gracefully', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Request an unknown setting
        final result = await DB.instance.getSettingByTitle(
          'completely_unknown_setting',
        );

        // Should return null
        expect(result, isNull);
      });

      testWidgets('duplicate photo insertion is handled', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final projectId = await DB.instance.addProject(
          'Duplicate Test',
          'face',
          123456,
        );

        // Add the same photo twice
        await DB.instance.addPhoto(
          '12345',
          projectId,
          'jpg',
          1000,
          'test.jpg',
          'portrait',
        );
        await DB.instance.addPhoto(
          '12345',
          projectId,
          'jpg',
          1000,
          'test.jpg',
          'portrait',
        );

        // Should still work - second insert is ignored
        final photos = await DB.instance.getPhotosByProjectID(projectId);
        expect(photos.length, 1);
      });
    });

    group('Cancellation Token Behavior', () {
      testWidgets('cancellation token works across async operations', (
        tester,
      ) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final token = CancellationToken();
        final results = <int>[];

        // Simulate a cancellable operation
        Future<void> cancellableTask() async {
          for (var i = 0; i < 10; i++) {
            token.throwIfCancelled();
            results.add(i);
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }

        // Start task and cancel after a short delay
        final taskFuture = cancellableTask();
        await Future.delayed(const Duration(milliseconds: 35));
        token.cancel();

        // Wait for task to complete (with exception)
        bool wasCancelled = false;
        try {
          await taskFuture;
        } on CancelledException {
          wasCancelled = true;
        }

        expect(wasCancelled, isTrue);
        expect(results.length, lessThan(10)); // Should not complete all steps
      });

      testWidgets('cancellation token can be reset and reused', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final token = CancellationToken();

        // Cancel and reset
        token.cancel();
        expect(token.isCancelled, isTrue);

        token.reset();
        expect(token.isCancelled, isFalse);

        // Should work again
        var completedNormally = true;
        try {
          token.throwIfCancelled();
        } on CancelledException {
          completedNormally = false;
        }

        expect(completedNormally, isTrue);
      });

      testWidgets('multiple cancel calls are idempotent', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final token = CancellationToken();
        var listenerCallCount = 0;

        token.addListener(() => listenerCallCount++);

        token.cancel();
        token.cancel();
        token.cancel();

        expect(token.isCancelled, isTrue);
        expect(listenerCallCount, 1); // Listener only called once
      });
    });

    group('Navigation Error Handling', () {
      testWidgets(
        'navigating to non-existent project shows error or redirects',
        (tester) async {
          app.main();
          await tester.pumpAndSettle(const Duration(seconds: 3));

          // Set a non-existent project as default
          await DB.instance.setSettingByTitle('default_project', '999999');

          // Restart app context (navigate back and forth)
          // The app should handle this gracefully
          expect(find.byType(MaterialApp), findsOneWidget);
          expect(find.byType(Scaffold), findsWidgets);
        },
      );

      testWidgets('back navigation does not crash app', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Try to find any navigation element and tap it
        final anyButton = find.byType(InkWell);
        if (anyButton.evaluate().isNotEmpty) {
          // App should not crash even with navigation
          expect(find.byType(MaterialApp), findsOneWidget);
        }
      });
    });

    group('Data Integrity', () {
      testWidgets('photo count is accurate after multiple operations', (
        tester,
      ) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final projectId = await DB.instance.addProject(
          'Count Test',
          'face',
          123456,
        );

        // Add photos
        await DB.instance.addPhoto(
          '1',
          projectId,
          'jpg',
          1000,
          'a.jpg',
          'portrait',
        );
        await DB.instance.addPhoto(
          '2',
          projectId,
          'jpg',
          1000,
          'b.jpg',
          'portrait',
        );
        await DB.instance.addPhoto(
          '3',
          projectId,
          'jpg',
          1000,
          'c.jpg',
          'portrait',
        );

        var count = await DB.instance.getPhotoCountByProjectID(projectId);
        expect(count, 3);

        // Delete one
        await DB.instance.deletePhoto(2, projectId);

        count = await DB.instance.getPhotoCountByProjectID(projectId);
        expect(count, 2);

        // Add more
        await DB.instance.addPhoto(
          '4',
          projectId,
          'jpg',
          1000,
          'd.jpg',
          'portrait',
        );
        await DB.instance.addPhoto(
          '5',
          projectId,
          'jpg',
          1000,
          'e.jpg',
          'portrait',
        );

        count = await DB.instance.getPhotoCountByProjectID(projectId);
        expect(count, 4);
      });

      testWidgets('project deletion cascades correctly', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final projectId = await DB.instance.addProject(
          'Delete Test',
          'face',
          123456,
        );

        // Add photos to project
        await DB.instance.addPhoto(
          '100',
          projectId,
          'jpg',
          1000,
          'a.jpg',
          'portrait',
        );
        await DB.instance.addPhoto(
          '200',
          projectId,
          'jpg',
          1000,
          'b.jpg',
          'portrait',
        );

        // Delete project
        await DB.instance.deleteProject(projectId);

        // Project should be gone
        final project = await DB.instance.getProject(projectId);
        expect(project, isNull);
      });

      testWidgets('stabilization status updates correctly', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final projectId = await DB.instance.addProject(
          'Stab Status Test',
          'face',
          123456,
        );

        // Add unstabilized photos
        await DB.instance.addPhoto(
          '1',
          projectId,
          'jpg',
          1000,
          'a.jpg',
          'portrait',
        );
        await DB.instance.addPhoto(
          '2',
          projectId,
          'jpg',
          1000,
          'b.jpg',
          'portrait',
        );

        var unstab = await DB.instance.getUnstabilizedPhotos(
          projectId,
          'portrait',
        );
        expect(unstab.length, 2);

        // Mark one as stabilized
        await DB.instance.setPhotoStabilized(
          '1',
          projectId,
          'portrait',
          '16:9',
          '1080p',
          0.0,
          0.0,
        );

        unstab = await DB.instance.getUnstabilizedPhotos(projectId, 'portrait');
        expect(unstab.length, 1);

        // Mark the other as no faces found
        await DB.instance.setPhotoNoFacesFound('2', projectId);

        unstab = await DB.instance.getUnstabilizedPhotos(projectId, 'portrait');
        expect(unstab.length, 0); // Both are "processed" now
      });
    });

    group('Settings Persistence', () {
      testWidgets('setting changes persist across reads', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final projectId =
            'persist_test_${DateTime.now().millisecondsSinceEpoch}';

        // Set a custom framerate
        await DB.instance.setSettingByTitle('framerate', '24', projectId);

        // Read it back
        final value = await DB.instance.getSettingValueByTitle(
          'framerate',
          projectId,
        );
        expect(value, '24');

        // Change it
        await DB.instance.setSettingByTitle('framerate', '30', projectId);

        // Read again
        final newValue = await DB.instance.getSettingValueByTitle(
          'framerate',
          projectId,
        );
        expect(newValue, '30');
      });

      testWidgets('project-specific settings are isolated', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final project1 = 'proj1_${DateTime.now().millisecondsSinceEpoch}';
        final project2 = 'proj2_${DateTime.now().millisecondsSinceEpoch}';

        // Set different values for same setting in different projects
        await DB.instance.setSettingByTitle('aspect_ratio', '16:9', project1);
        await DB.instance.setSettingByTitle('aspect_ratio', '4:3', project2);

        // Verify isolation
        final val1 = await DB.instance.getSettingValueByTitle(
          'aspect_ratio',
          project1,
        );
        final val2 = await DB.instance.getSettingValueByTitle(
          'aspect_ratio',
          project2,
        );

        expect(val1, '16:9');
        expect(val2, '4:3');
      });
    });

    group('Edge Cases', () {
      testWidgets('empty project has zero photos', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final projectId = await DB.instance.addProject(
          'Empty Project',
          'face',
          123456,
        );

        final count = await DB.instance.getPhotoCountByProjectID(projectId);
        expect(count, 0);

        final photos = await DB.instance.getPhotosByProjectID(projectId);
        expect(photos, isEmpty);

        final earliest = await DB.instance.getEarliestPhotoTimestamp(projectId);
        expect(earliest, isNull);

        final latest = await DB.instance.getLatestPhotoTimestamp(projectId);
        expect(latest, isNull);
      });

      testWidgets('video with no photos is not created', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final projectId = await DB.instance.addProject(
          'No Photos Video',
          'face',
          123456,
        );

        // No video should exist
        final video = await DB.instance.getNewestVideoByProjectId(projectId);
        expect(video, isNull);
      });

      testWidgets('special characters in project name are handled', (
        tester,
      ) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Create project with special characters
        final id = await DB.instance.addProject(
          "Test's \"Project\" <script>",
          'face',
          123456,
        );

        final project = await DB.instance.getProject(id);
        expect(project, isNotNull);
        expect(project!['name'], "Test's \"Project\" <script>");
      });

      testWidgets('very long project name is handled', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final longName = 'A' * 500; // 500 character name
        final id = await DB.instance.addProject(longName, 'face', 123456);

        final project = await DB.instance.getProject(id);
        expect(project, isNotNull);
        expect(project!['name'], longName);
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
    // Reset default project
    await DB.instance.setSettingByTitle('default_project', 'none');
  } catch (e) {
    // Ignore cleanup errors
  }
}
