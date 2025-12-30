import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/models/setting_model.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;

/// Integration tests for DatabaseHelper (DB class).
/// These tests verify all CRUD operations work correctly on real devices.
///
/// Run with: `flutter test integration_test/database_test.dart -d <platform>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('DatabaseHelper Integration Tests', () {
    setUpAll(() async {
      await DB.instance.createTablesIfNotExist();
    });

    setUp(() async {
      await _cleanupTestData();
    });

    group('Projects CRUD', () {
      testWidgets('addProject creates a new project and returns id',
          (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final id =
            await DB.instance.addProject('Test Project', 'face', timestamp);

        expect(id, isPositive);
      });

      testWidgets('getProject returns project by id', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final id = await DB.instance.addProject('Get Test', 'face', timestamp);

        final project = await DB.instance.getProject(id);

        expect(project, isNotNull);
        expect(project!['name'], 'Get Test');
        expect(project['type'], 'face');
        expect(project['timestampCreated'], timestamp);
        expect(project['newVideoNeeded'], 0);
      });

      testWidgets('getProject returns null for non-existent id',
          (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final project = await DB.instance.getProject(999999);
        expect(project, isNull);
      });

      testWidgets('getProjectNameById returns name for existing project',
          (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final id =
            await DB.instance.addProject('Named Project', 'face', 123456);
        final name = await DB.instance.getProjectNameById(id);

        expect(name, 'Named Project');
      });

      testWidgets('getAllProjects returns all projects', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        await DB.instance.addProject('Project 1', 'face', 1);
        await DB.instance.addProject('Project 2', 'other', 2);
        await DB.instance.addProject('Project 3', 'face', 3);

        final projects = await DB.instance.getAllProjects();

        expect(projects.length, greaterThanOrEqualTo(3));
      });

      testWidgets('updateProjectName updates project name', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final id = await DB.instance.addProject('Old Name', 'face', 123456);
        final updated = await DB.instance.updateProjectName(id, 'New Name');

        expect(updated, 1);
        final project = await DB.instance.getProject(id);
        expect(project!['name'], 'New Name');
      });

      testWidgets('deleteProject removes project', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final id = await DB.instance.addProject('To Delete', 'face', 123456);
        final deleted = await DB.instance.deleteProject(id);

        expect(deleted, 1);
        final project = await DB.instance.getProject(id);
        expect(project, isNull);
      });

      testWidgets('setNewVideoNeeded and getNewVideoNeeded work correctly',
          (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final id = await DB.instance.addProject('Video Needed', 'face', 123456);

        var needed = await DB.instance.getNewVideoNeeded(id);
        expect(needed, 0);

        await DB.instance.setNewVideoNeeded(id);
        needed = await DB.instance.getNewVideoNeeded(id);
        expect(needed, 1);
      });
    });

    group('Settings CRUD', () {
      testWidgets('addSetting creates a new setting', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final setting = Setting(
          title: 'test_setting_${DateTime.now().millisecondsSinceEpoch}',
          value: 'test_value',
          projectId: 'global',
        );

        final id = await DB.instance.addSetting(setting);

        expect(id, isPositive);
      });

      testWidgets('getSettingByTitle returns existing setting', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final title = 'get_setting_${DateTime.now().millisecondsSinceEpoch}';
        final setting =
            Setting(title: title, value: 'my_value', projectId: 'global');
        await DB.instance.addSetting(setting);

        final result = await DB.instance.getSettingByTitle(title);

        expect(result, isNotNull);
        expect(result!['value'], 'my_value');
      });

      testWidgets('getSettingByTitle returns default for known settings',
          (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final result =
            await DB.instance.getSettingByTitle('theme', 'new_project_id');

        expect(result, isNotNull);
        expect(result!['value'], 'dark');
      });

      testWidgets('setSettingByTitle updates existing setting', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final title = 'update_test_${DateTime.now().millisecondsSinceEpoch}';
        await DB.instance.addSetting(
            Setting(title: title, value: 'old_value', projectId: 'global'));

        await DB.instance.setSettingByTitle(title, 'new_value');

        final result = await DB.instance.getSettingValueByTitle(title);
        expect(result, 'new_value');
      });

      testWidgets('settings are project-specific when projectId is set',
          (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final title =
            'project_specific_${DateTime.now().millisecondsSinceEpoch}';
        await DB.instance.addSetting(
            Setting(title: title, value: 'project1_value', projectId: '1'));
        await DB.instance.addSetting(
            Setting(title: title, value: 'project2_value', projectId: '2'));

        final value1 = await DB.instance.getSettingValueByTitle(title, '1');
        final value2 = await DB.instance.getSettingValueByTitle(title, '2');

        expect(value1, 'project1_value');
        expect(value2, 'project2_value');
      });
    });

    group('Photos CRUD', () {
      testWidgets('addPhoto creates a new photo record', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('Photo Test', 'face', 123456);
        await DB.instance.addPhoto(
            '1234567890', projectId, 'jpg', 1000, 'photo.jpg', 'portrait');

        final photos = await DB.instance.getPhotosByProjectID(projectId);
        expect(photos.length, 1);
        expect(photos.first['timestamp'], '1234567890');
      });

      testWidgets('getPhotoByTimestamp returns photo', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('Photo Get Test', 'face', 123456);
        await DB.instance.addPhoto(
            '9876543210', projectId, 'png', 2000, 'test.png', 'landscape');

        final photo =
            await DB.instance.getPhotoByTimestamp('9876543210', projectId);

        expect(photo, isNotNull);
        expect(photo!['fileExtension'], 'png');
        expect(photo['originalOrientation'], 'landscape');
      });

      testWidgets('doesPhotoExistByTimestamp works correctly', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('Photo Exists Test', 'face', 123456);
        await DB.instance.addPhoto(
            '1111111111', projectId, 'jpg', 1000, 'exists.jpg', 'portrait');

        final exists = await DB.instance
            .doesPhotoExistByTimestamp('1111111111', projectId);
        final notExists = await DB.instance
            .doesPhotoExistByTimestamp('9999999999', projectId);

        expect(exists, isTrue);
        expect(notExists, isFalse);
      });

      testWidgets('getPhotoCountByProjectID returns correct count',
          (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('Photo Count Test', 'face', 123456);
        await DB.instance
            .addPhoto('1', projectId, 'jpg', 1000, 'a.jpg', 'portrait');
        await DB.instance
            .addPhoto('2', projectId, 'jpg', 1000, 'b.jpg', 'portrait');
        await DB.instance
            .addPhoto('3', projectId, 'jpg', 1000, 'c.jpg', 'portrait');

        final count = await DB.instance.getPhotoCountByProjectID(projectId);

        expect(count, 3);
      });

      testWidgets('setPhotoStabilized marks photo as stabilized',
          (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('Stab Test', 'face', 123456);
        await DB.instance.addPhoto(
            '3333333333', projectId, 'jpg', 1000, 'stab.jpg', 'portrait');

        await DB.instance.setPhotoStabilized(
          '3333333333',
          projectId,
          'portrait',
          '16:9',
          '1080p',
          0.065,
          0.421875,
        );

        final photos = await DB.instance
            .getStabilizedPhotosByProjectID(projectId, 'portrait');
        expect(photos.length, 1);
      });

      testWidgets('getUnstabilizedPhotos returns only unstabilized photos',
          (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('Unstab Test', 'face', 123456);
        await DB.instance
            .addPhoto('4', projectId, 'jpg', 1000, 'd.jpg', 'portrait');
        await DB.instance
            .addPhoto('5', projectId, 'jpg', 1000, 'e.jpg', 'portrait');
        await DB.instance.setPhotoStabilized(
            '4', projectId, 'portrait', '16:9', '1080p', 0.0, 0.0);

        final unstabilized =
            await DB.instance.getUnstabilizedPhotos(projectId, 'portrait');

        expect(unstabilized.length, 1);
        expect(unstabilized.first['timestamp'], '5');
      });

      testWidgets('setPhotoNoFacesFound marks photo correctly', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('No Face Test', 'face', 123456);
        await DB.instance.addPhoto(
            '6666666666', projectId, 'jpg', 1000, 'noface.jpg', 'portrait');

        await DB.instance.setPhotoNoFacesFound('6666666666');

        final photo =
            await DB.instance.getPhotoByTimestamp('6666666666', projectId);
        expect(photo!['noFacesFound'], 1);
      });

      testWidgets('favorite photo operations work correctly', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('Fav Test', 'face', 123456);
        await DB.instance.addPhoto(
            '8888888888', projectId, 'jpg', 1000, 'fav.jpg', 'portrait');

        var isFav = await DB.instance.isFavoritePhoto('8888888888');
        expect(isFav, isFalse);

        await DB.instance.setPhotoAsFavorite('8888888888');

        isFav = await DB.instance.isFavoritePhoto('8888888888');
        expect(isFav, isTrue);
      });

      testWidgets('getPhotosByProjectIDNewestFirst returns sorted photos',
          (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('Sort Test', 'face', 123456);
        await DB.instance
            .addPhoto('100', projectId, 'jpg', 1000, 'first.jpg', 'portrait');
        await DB.instance
            .addPhoto('300', projectId, 'jpg', 1000, 'third.jpg', 'portrait');
        await DB.instance
            .addPhoto('200', projectId, 'jpg', 1000, 'second.jpg', 'portrait');

        final photos =
            await DB.instance.getPhotosByProjectIDNewestFirst(projectId);

        expect(photos[0]['timestamp'], '300');
        expect(photos[1]['timestamp'], '200');
        expect(photos[2]['timestamp'], '100');
      });

      testWidgets('getEarliestPhotoTimestamp and getLatestPhotoTimestamp work',
          (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('Timestamp Test', 'face', 123456);
        await DB.instance
            .addPhoto('500', projectId, 'jpg', 1000, 'a.jpg', 'portrait');
        await DB.instance
            .addPhoto('100', projectId, 'jpg', 1000, 'b.jpg', 'portrait');
        await DB.instance
            .addPhoto('900', projectId, 'jpg', 1000, 'c.jpg', 'portrait');

        final earliest = await DB.instance.getEarliestPhotoTimestamp(projectId);
        final latest = await DB.instance.getLatestPhotoTimestamp(projectId);

        expect(earliest, '100');
        expect(latest, '900');
      });

      testWidgets('face embedding storage and retrieval works', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('Embedding Test', 'face', 123456);
        await DB.instance.addPhoto(
            '9999999999', projectId, 'jpg', 1000, 'face.jpg', 'portrait');

        final embedding =
            Uint8List.fromList(List.generate(768, (i) => i % 256));
        await DB.instance
            .setPhotoFaceData('9999999999', projectId, 1, embedding: embedding);

        final stored =
            await DB.instance.getPhotoEmbedding('9999999999', projectId);
        expect(stored, isNotNull);
        expect(stored!.length, 768);
      });
    });

    group('Videos CRUD', () {
      testWidgets('addVideo creates a new video record', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('Video Test', 'face', 123456);
        final id = await DB.instance
            .addVideo(projectId, '1080p', 'true', 'lower left', 100, 14);

        expect(id, isPositive);
      });

      testWidgets('getNewestVideoByProjectId returns latest video',
          (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('Video Latest Test', 'face', 123456);
        await DB.instance
            .addVideo(projectId, '720p', 'false', 'upper left', 50, 10);
        await Future.delayed(const Duration(milliseconds: 10));
        await DB.instance
            .addVideo(projectId, '1080p', 'true', 'lower right', 100, 14);

        final newest = await DB.instance.getNewestVideoByProjectId(projectId);

        expect(newest, isNotNull);
        expect(newest!['resolution'], '1080p');
        expect(newest['photoCount'], 100);
      });

      testWidgets('getNewestVideoByProjectId returns null when no videos',
          (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('No Video Test', 'face', 123456);
        final newest = await DB.instance.getNewestVideoByProjectId(projectId);

        expect(newest, isNull);
      });
    });

    group('Photo Orientation Analysis', () {
      testWidgets('checkPhotoOrientationThreshold returns landscape majority',
          (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('Orientation Test', 'face', 123456);
        // Add 3 landscape, 2 portrait = 60% landscape
        await DB.instance
            .addPhoto('1', projectId, 'jpg', 1000, 'a.jpg', 'landscape');
        await DB.instance
            .addPhoto('2', projectId, 'jpg', 1000, 'b.jpg', 'landscape');
        await DB.instance
            .addPhoto('3', projectId, 'jpg', 1000, 'c.jpg', 'landscape');
        await DB.instance
            .addPhoto('4', projectId, 'jpg', 1000, 'd.jpg', 'portrait');
        await DB.instance
            .addPhoto('5', projectId, 'jpg', 1000, 'e.jpg', 'portrait');

        final threshold =
            await DB.instance.checkPhotoOrientationThreshold(projectId);

        expect(threshold, 'landscape');
      });

      testWidgets(
          'checkPhotoOrientationThreshold returns portrait when majority',
          (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final projectId =
            await DB.instance.addProject('Portrait Majority', 'face', 123456);
        // Add 1 landscape, 4 portrait = 20% landscape
        await DB.instance
            .addPhoto('1', projectId, 'jpg', 1000, 'a.jpg', 'landscape');
        await DB.instance
            .addPhoto('2', projectId, 'jpg', 1000, 'b.jpg', 'portrait');
        await DB.instance
            .addPhoto('3', projectId, 'jpg', 1000, 'c.jpg', 'portrait');
        await DB.instance
            .addPhoto('4', projectId, 'jpg', 1000, 'd.jpg', 'portrait');
        await DB.instance
            .addPhoto('5', projectId, 'jpg', 1000, 'e.jpg', 'portrait');

        final threshold =
            await DB.instance.checkPhotoOrientationThreshold(projectId);

        expect(threshold, 'portrait');
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
