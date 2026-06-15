import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/models/transform_cache_entry.dart';
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/services/face_stabilizer.dart';
import 'package:agelapse/services/isolate_pool.dart';
import 'package:agelapse/services/stabilization_settings.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/stabilizer_utils/stabilizer_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:agelapse/utils/transform_cache_key.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'test_utils.dart';

/// Integration tests for the FaceDetectionCache DB API and cache-enabled
/// stabilization pipeline.
///
/// Run with: `flutter test integration_test/stab_cache_test.dart -d macos`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('FaceDetectionCache DB round-trip', () {
    int? projectId;

    setUpAll(() async {
      initDatabase();
      await DB.instance.createTablesIfNotExist();
    });

    setUp(() async {
      final ts = DateTime.now().millisecondsSinceEpoch;
      projectId = await DB.instance.addProject('CacheDBTest_$ts', 'face', ts);
    });

    tearDown(() async {
      if (projectId != null) {
        await DB.instance.clearFaceDetectionCacheForProject(projectId!);
        try {
          await DB.instance.deleteProject(projectId!);
        } catch (_) {}
        projectId = null;
      }
    });

    testWidgets(
      'writeFaceDetectionCache with 2 faces returns both with correct coordinates',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));

        const ts = '1000000001';
        const fingerprint = '12345:abcdef1234567890abcdef1234567890';
        const modelVersion = 'v1';

        await DB.instance.writeFaceDetectionCache(
          ts,
          projectId!,
          'original',
          [
            {
              'boundingBoxLeft': 10.0,
              'boundingBoxTop': 20.0,
              'boundingBoxRight': 110.0,
              'boundingBoxBottom': 120.0,
              'leftEyeX': 40.0,
              'leftEyeY': 60.0,
              'rightEyeX': 80.0,
              'rightEyeY': 60.0,
            },
            {
              'boundingBoxLeft': 200.0,
              'boundingBoxTop': 50.0,
              'boundingBoxRight': 300.0,
              'boundingBoxBottom': 150.0,
              'leftEyeX': 220.0,
              'leftEyeY': 90.0,
              'rightEyeX': 280.0,
              'rightEyeY': 90.0,
            },
          ],
          modelVersion,
          fingerprint,
          selectedFaceIndex: 1,
        );

        final result = await DB.instance.getFaceDetectionCache(
          ts,
          projectId!,
          modelVersion,
          fingerprint,
        );

        expect(result, isNotNull);
        expect(result!.orientation, 'original');
        expect(result.faces.length, 2);
        expect(result.selectedFaceIndex, 1);

        final f0 = result.faces[0];
        expect(f0.boundingBox.left, closeTo(10.0, 1e-9));
        expect(f0.boundingBox.top, closeTo(20.0, 1e-9));
        expect(f0.boundingBox.right, closeTo(110.0, 1e-9));
        expect(f0.boundingBox.bottom, closeTo(120.0, 1e-9));
        expect(f0.leftEye!.x, closeTo(40.0, 1e-9));
        expect(f0.leftEye!.y, closeTo(60.0, 1e-9));
        expect(f0.rightEye!.x, closeTo(80.0, 1e-9));
        expect(f0.rightEye!.y, closeTo(60.0, 1e-9));

        final f1 = result.faces[1];
        expect(f1.boundingBox.left, closeTo(200.0, 1e-9));
        expect(f1.boundingBox.right, closeTo(300.0, 1e-9));
      },
    );

    testWidgets(
      'writeNoFacesSentinel returns orientation=no_faces and empty faces',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));

        const ts = '1000000002';
        const fingerprint = '99999:ffffffffffffffffffffffffffffffff';
        const modelVersion = 'v1';

        await DB.instance.writeNoFacesSentinel(
          ts,
          projectId!,
          modelVersion,
          fingerprint,
        );

        final result = await DB.instance.getFaceDetectionCache(
          ts,
          projectId!,
          modelVersion,
          fingerprint,
        );

        expect(result, isNotNull);
        expect(result!.isNoFaces, isTrue);
        expect(result.faces, isEmpty);
      },
    );

    testWidgets('getFaceDetectionCache returns null on wrong modelVersion', (
      tester,
    ) async {
      app.main();
      await tester.pump(const Duration(seconds: 2));

      const ts = '1000000003';
      const fingerprint = '11111:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

      await DB.instance.writeFaceDetectionCache(
        ts,
        projectId!,
        'original',
        [
          {
            'boundingBoxLeft': 0.0,
            'boundingBoxTop': 0.0,
            'boundingBoxRight': 100.0,
            'boundingBoxBottom': 100.0,
            'leftEyeX': 30.0,
            'leftEyeY': 40.0,
            'rightEyeX': 70.0,
            'rightEyeY': 40.0,
          },
        ],
        'v1',
        fingerprint,
      );

      final miss = await DB.instance.getFaceDetectionCache(
        ts,
        projectId!,
        'v2',
        fingerprint,
      );
      expect(miss, isNull);
    });

    testWidgets('getFaceDetectionCache returns null on wrong fingerprint', (
      tester,
    ) async {
      app.main();
      await tester.pump(const Duration(seconds: 2));

      const ts = '1000000004';
      const fingerprint = '22222:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      const modelVersion = 'v1';

      await DB.instance.writeFaceDetectionCache(
        ts,
        projectId!,
        'original',
        [
          {
            'boundingBoxLeft': 5.0,
            'boundingBoxTop': 5.0,
            'boundingBoxRight': 95.0,
            'boundingBoxBottom': 95.0,
            'leftEyeX': null,
            'leftEyeY': null,
            'rightEyeX': null,
            'rightEyeY': null,
          },
        ],
        modelVersion,
        fingerprint,
      );

      final miss = await DB.instance.getFaceDetectionCache(
        ts,
        projectId!,
        modelVersion,
        'wrongfingerprint',
      );
      expect(miss, isNull);
    });

    testWidgets(
      'clearFaceDetectionCacheForProject deletes all rows for that project only',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));

        const fp = '33333:cccccccccccccccccccccccccccccccc';
        const mv = 'v1';

        await DB.instance.writeFaceDetectionCache(
          '2000000001',
          projectId!,
          'original',
          [
            {
              'boundingBoxLeft': 0.0,
              'boundingBoxTop': 0.0,
              'boundingBoxRight': 10.0,
              'boundingBoxBottom': 10.0,
              'leftEyeX': null,
              'leftEyeY': null,
              'rightEyeX': null,
              'rightEyeY': null,
            },
          ],
          mv,
          fp,
        );
        await DB.instance.writeNoFacesSentinel(
          '2000000002',
          projectId!,
          mv,
          fp,
        );

        final otherTs = DateTime.now().millisecondsSinceEpoch;
        final otherId = await DB.instance.addProject(
          'OtherProject_$otherTs',
          'face',
          otherTs,
        );
        await DB.instance.writeFaceDetectionCache(
          '2000000001',
          otherId,
          'original',
          [
            {
              'boundingBoxLeft': 0.0,
              'boundingBoxTop': 0.0,
              'boundingBoxRight': 10.0,
              'boundingBoxBottom': 10.0,
              'leftEyeX': null,
              'leftEyeY': null,
              'rightEyeX': null,
              'rightEyeY': null,
            },
          ],
          mv,
          fp,
        );

        await DB.instance.clearFaceDetectionCacheForProject(projectId!);

        expect(
          await DB.instance.getFaceDetectionCache(
            '2000000001',
            projectId!,
            mv,
            fp,
          ),
          isNull,
          reason: 'cleared entry should be gone',
        );
        expect(
          await DB.instance.getFaceDetectionCache(
            '2000000002',
            projectId!,
            mv,
            fp,
          ),
          isNull,
          reason: 'cleared entry should be gone',
        );
        expect(
          await DB.instance.getFaceDetectionCache(
            '2000000001',
            otherId,
            mv,
            fp,
          ),
          isNotNull,
          reason: 'other project entry should remain',
        );

        await DB.instance.clearFaceDetectionCacheForProject(otherId);
        try {
          await DB.instance.deleteProject(otherId);
        } catch (_) {}
      },
    );

    testWidgets(
      'second write for same (timestamp, projectId) replaces first (idempotent)',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));

        const ts = '3000000001';
        const fp = '44444:dddddddddddddddddddddddddddddddd';
        const mv = 'v1';

        await DB.instance.writeFaceDetectionCache(
          ts,
          projectId!,
          'original',
          [
            {
              'boundingBoxLeft': 1.0,
              'boundingBoxTop': 2.0,
              'boundingBoxRight': 3.0,
              'boundingBoxBottom': 4.0,
              'leftEyeX': null,
              'leftEyeY': null,
              'rightEyeX': null,
              'rightEyeY': null,
            },
          ],
          mv,
          fp,
        );

        await DB.instance.writeFaceDetectionCache(
          ts,
          projectId!,
          'flipped',
          [
            {
              'boundingBoxLeft': 50.0,
              'boundingBoxTop': 60.0,
              'boundingBoxRight': 150.0,
              'boundingBoxBottom': 160.0,
              'leftEyeX': 70.0,
              'leftEyeY': 80.0,
              'rightEyeX': 130.0,
              'rightEyeY': 80.0,
            },
          ],
          mv,
          fp,
        );

        final result = await DB.instance.getFaceDetectionCache(
          ts,
          projectId!,
          mv,
          fp,
        );
        expect(result, isNotNull);
        expect(result!.orientation, 'flipped');
        expect(result.faces.length, 1);
        expect(result.faces.first.boundingBox.left, closeTo(50.0, 1e-9));
      },
    );
  });

  group('TransformCache DB round-trip', () {
    int? projectId;

    setUpAll(() async {
      initDatabase();
      await DB.instance.createTablesIfNotExist();
    });

    setUp(() async {
      final ts = DateTime.now().millisecondsSinceEpoch;
      projectId = await DB.instance.addProject(
        'TransformCacheDBTest_$ts',
        'face',
        ts,
      );
    });

    tearDown(() async {
      if (projectId != null) {
        await DB.instance.clearTransformCacheForProject(projectId!);
        try {
          await DB.instance.deleteProject(projectId!);
        } catch (_) {}
        projectId = null;
      }
    });

    testWidgets('writeTransformCache inserts and reads an entry', (
      tester,
    ) async {
      app.main();
      await tester.pump(const Duration(seconds: 2));

      final entry = _makeTransformEntry(projectId!);

      await DB.instance.writeTransformCache(entry);
      final cached = await DB.instance.getTransformCache(entry.cacheKey);

      expect(cached, isNotNull);
      expect(cached!.projectId, projectId);
      expect(cached.fingerprint, entry.fingerprint);
      expect(cached.sourceOrientation, 'original');
      expect(cached.selectedFaceIndex, 1);
      expect(cached.canvasWidth, 1920);
      expect(cached.canvasHeight, 1080);
      expect(cached.translateX, closeTo(10.25, 1e-9));
      expect(cached.translateY, closeTo(-3.5, 1e-9));
      expect(cached.rotationDegrees, closeTo(1.25, 1e-9));
      expect(cached.scaleFactor, closeTo(1.1, 1e-9));
      expect(cached.isEstimated, isFalse);
    });

    testWidgets(
        'writeTransformCache upserts by cacheKey and preserves id/createdAt',
        (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 2));

      final entry = _makeTransformEntry(projectId!);
      await DB.instance.writeTransformCache(entry);

      final first = await DB.instance.getTransformCache(entry.cacheKey);
      expect(first, isNotNull);

      final replacement = entry.copyWith(
        translateX: 22.0,
        translateY: 33.0,
        rotationDegrees: -2.0,
        scaleFactor: 0.95,
        updatedAt: entry.updatedAt + 1000,
      );
      await DB.instance.writeTransformCache(replacement);

      final cached = await DB.instance.getTransformCache(entry.cacheKey);
      expect(cached, isNotNull);
      expect(cached!.id, first!.id);
      expect(cached.createdAt, first.createdAt);
      expect(cached.translateX, closeTo(22.0, 1e-9));
      expect(cached.translateY, closeTo(33.0, 1e-9));
      expect(cached.rotationDegrees, closeTo(-2.0, 1e-9));
      expect(cached.scaleFactor, closeTo(0.95, 1e-9));
    });

    testWidgets(
      'clearTransformCacheForFingerprint respects scope and settings',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));

        final autoA = _makeTransformEntry(
          projectId!,
          cacheKey: 'auto-a',
          settingsHash: 'settings-a',
        );
        final autoB = _makeTransformEntry(
          projectId!,
          cacheKey: 'auto-b',
          settingsHash: 'settings-b',
        );
        final manualA = _makeTransformEntry(
          projectId!,
          cacheKey: 'manual-a',
          settingsHash: 'settings-a',
          scope: 'manual',
        );
        await DB.instance.writeTransformCache(autoA);
        await DB.instance.writeTransformCache(autoB);
        await DB.instance.writeTransformCache(manualA);

        await DB.instance.clearTransformCacheForFingerprint(
          projectId!,
          autoA.fingerprint,
          settingsHash: 'settings-a',
        );

        expect(await DB.instance.getTransformCache(autoA.cacheKey), isNull);
        expect(await DB.instance.getTransformCache(autoB.cacheKey), isNotNull);
        expect(
          await DB.instance.getTransformCache(manualA.cacheKey),
          isNotNull,
        );

        await DB.instance.clearTransformCacheForFingerprint(
          projectId!,
          autoA.fingerprint,
          scope: 'manual',
        );

        expect(await DB.instance.getTransformCache(manualA.cacheKey), isNull);
      },
    );

    testWidgets('deleteProjectCascade removes transform cache rows', (
      tester,
    ) async {
      app.main();
      await tester.pump(const Duration(seconds: 2));

      final entry = _makeTransformEntry(projectId!);
      await DB.instance.writeTransformCache(entry);

      expect(await DB.instance.getTransformCache(entry.cacheKey), isNotNull);
      expect(await DB.instance.deleteProjectCascade(projectId!), isTrue);
      expect(await DB.instance.getTransformCache(entry.cacheKey), isNull);
      projectId = null;
    });

    testWidgets('multi-face transform cache entry is stored for diagnostics', (
      tester,
    ) async {
      app.main();
      await tester.pump(const Duration(seconds: 2));

      final entry = _makeTransformEntry(projectId!, faceCount: 2);
      await DB.instance.writeTransformCache(entry);

      final cached = await DB.instance.getTransformCache(entry.cacheKey);
      expect(cached, isNotNull);
      expect(cached!.faceCount, 2);
      expect(cached.selectedFaceIndex, 1);
    });
  });

  group('Cache-enabled stabilization pipeline', () {
    int? projectId;
    List<String> rawPaths = [];

    setUpAll(() async {
      initDatabase();
      await DB.instance.createTablesIfNotExist();
      await IsolatePool.instance.initialize();
    });

    tearDownAll(() async {
      await IsolatePool.instance.dispose();
    });

    setUp(() async {
      rawPaths = [];
      FaceStabilizer.faceDetectionCacheEnabled = true;
    });

    tearDown(() async {
      FaceStabilizer.faceDetectionCacheEnabled = true;
      FaceStabilizer.resetCacheCounters();
      if (projectId != null) {
        try {
          final dir = await DirUtils.getProjectDirPath(projectId!);
          if (await Directory(dir).exists()) {
            await Directory(dir).delete(recursive: true);
          }
          await DB.instance.deleteProject(projectId!);
        } catch (_) {}
        projectId = null;
      }
    });

    Future<int> createFaceProject() async {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final pid = await DB.instance.addProject('StabCacheTest_$ts', 'face', ts);
      final pidStr = pid.toString();

      await DB.instance.setSettingByTitle(
        'project_orientation',
        'portrait',
        pidStr,
      );
      await DB.instance.setSettingByTitle('video_resolution', '1080p', pidStr);
      await DB.instance.setSettingByTitle('aspect_ratio', '9:16', pidStr);
      await DB.instance.setSettingByTitle(
        'background_color',
        '#000000',
        pidStr,
      );
      await DB.instance.setSettingByTitle(
        'auto_compile_video',
        'false',
        pidStr,
      );

      final rawDir = await DirUtils.getRawPhotoDirPath(pid);
      await Directory(rawDir).create(recursive: true);

      final stabDir = await DirUtils.getStabilizedDirPath(pid);
      await Directory(p.join(stabDir, 'portrait')).create(recursive: true);

      final thumbDir = await DirUtils.getThumbnailDirPath(pid);
      await Directory(
        p.join(thumbDir, 'stabilized', 'portrait'),
      ).create(recursive: true);

      final failDir = await DirUtils.getFailureDirPath(pid);
      await Directory(failDir).create(recursive: true);

      return pid;
    }

    Future<List<String>> addFacePhotos(int pid, int count) async {
      final rawDir = await DirUtils.getRawPhotoDirPath(pid);
      final paths = <String>[];

      for (int i = 0; i < count; i++) {
        final facePath = await getSampleFacePathAsync((i % 3) + 1);
        final ts = (2000000000 + i * 1000).toString();
        final dest = p.join(rawDir, '$ts.jpg');
        await File(facePath).copy(dest);
        final fileSize = await File(dest).length();
        await DB.instance.addPhoto(
          ts,
          pid,
          '.jpg',
          fileSize,
          '$ts.jpg',
          'portrait',
        );
        paths.add(dest);
      }
      return paths;
    }

    Future<Map<String, Map<String, dynamic>>> collectStabValues(int pid) async {
      final photos = await DB.instance.getPhotosByProjectID(pid);
      final result = <String, Map<String, dynamic>>{};
      for (final photo in photos) {
        final ts = photo['timestamp'] as String;
        result[ts] = {
          'stabilizedPortrait': photo['stabilizedPortrait'],
          'noFacesFound': photo['noFacesFound'],
          'translateX': photo['stabilizedPortraitTranslateX'],
          'translateY': photo['stabilizedPortraitTranslateY'],
          'rotationDegrees': photo['stabilizedPortraitRotationDegrees'],
          'scaleFactor': photo['stabilizedPortraitScaleFactor'],
        };
      }
      return result;
    }

    Future<void> resetStabilizedFlags(int pid, {bool clearCache = true}) async {
      final photos = await DB.instance.getPhotosByProjectID(pid);
      for (final photo in photos) {
        final ts = photo['timestamp'] as String;
        await DB.instance.resetStabilizedColumnByTimestamp('portrait', ts, pid);
      }
      if (clearCache) {
        await DB.instance.clearFaceDetectionCacheForProject(pid);
      }
    }

    testWidgets(
      'bit-for-bit restab equivalence: cache=off vs cache=on produce identical stab values',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 3));

        await preloadFixtures();
        if (fixturesUnavailable) {
          markTestSkipped('Fixtures unavailable');
          return;
        }

        projectId = await createFaceProject();
        rawPaths = await addFacePhotos(projectId!, 3);

        final settings = await StabilizationSettings.load(projectId!);

        // Pass 1: cache disabled, collect baseline stab values
        FaceStabilizer.faceDetectionCacheEnabled = false;
        var stabilizer = FaceStabilizer(projectId!, () {}, settings: settings);
        for (final path in rawPaths) {
          await stabilizer.stabilize(path, null, () {});
        }
        await stabilizer.dispose();
        final baselineValues = await collectStabValues(projectId!);

        // Reset stab flags (no cache to clear since it was disabled)
        await resetStabilizedFlags(projectId!, clearCache: false);

        // Pass 2: cache enabled, populates cache rows
        FaceStabilizer.faceDetectionCacheEnabled = true;
        stabilizer = FaceStabilizer(projectId!, () {}, settings: settings);
        for (final path in rawPaths) {
          await stabilizer.stabilize(path, null, () {});
        }
        await stabilizer.dispose();
        final cachedValues = await collectStabValues(projectId!);

        // Verify cache has rows for each photo after first cache-enabled run
        for (final path in rawPaths) {
          final ts = p.basenameWithoutExtension(path);
          final fingerprint = await StabUtils.computeRawPhotoFingerprint(path);
          final cached = await DB.instance.getFaceDetectionCache(
            ts,
            projectId!,
            StabUtils.detectorModelVersionForProjectType('face'),
            fingerprint,
          );
          expect(
            cached,
            isNotNull,
            reason:
                'Cache should have entry for $ts after first cache-enabled run',
          );
        }

        // Assert pass-2 (cache-miss write) values match baseline
        for (final ts in baselineValues.keys) {
          final base = baselineValues[ts]!;
          final cached = cachedValues[ts]!;

          if (base['noFacesFound'] == 1) {
            expect(
              cached['noFacesFound'],
              1,
              reason: '$ts: noFacesFound should match',
            );
            continue;
          }
          if (base['stabilizedPortrait'] != 1) continue;

          expect(
            cached['stabilizedPortrait'],
            1,
            reason: '$ts: should be stabilized',
          );
          _expectCloseOrBothNull(
            base['translateX'],
            cached['translateX'],
            '$ts translateX',
          );
          _expectCloseOrBothNull(
            base['translateY'],
            cached['translateY'],
            '$ts translateY',
          );
          _expectCloseOrBothNull(
            base['rotationDegrees'],
            cached['rotationDegrees'],
            '$ts rotationDegrees',
          );
          _expectCloseOrBothNull(
            base['scaleFactor'],
            cached['scaleFactor'],
            '$ts scaleFactor',
          );
        }

        // Pass 3: reset stab flags but KEEP cache rows, then re-stabilize.
        // This run should read from cache (hits) and produce identical values.
        await resetStabilizedFlags(projectId!, clearCache: false);

        FaceStabilizer.resetCacheCounters();
        stabilizer = FaceStabilizer(projectId!, () {}, settings: settings);
        for (final path in rawPaths) {
          await stabilizer.stabilize(path, null, () {});
        }
        await stabilizer.dispose();

        final hitRunValues = await collectStabValues(projectId!);

        // Values from cache-hit run should match baseline
        for (final ts in baselineValues.keys) {
          final base = baselineValues[ts]!;
          final hit = hitRunValues[ts]!;

          if (base['noFacesFound'] == 1) {
            expect(
              hit['noFacesFound'],
              1,
              reason: '$ts: noFacesFound should match on cache hit',
            );
            continue;
          }
          if (base['stabilizedPortrait'] != 1) continue;

          _expectCloseOrBothNull(
            base['translateX'],
            hit['translateX'],
            '$ts hit translateX',
          );
          _expectCloseOrBothNull(
            base['translateY'],
            hit['translateY'],
            '$ts hit translateY',
          );
          _expectCloseOrBothNull(
            base['rotationDegrees'],
            hit['rotationDegrees'],
            '$ts hit rotationDegrees',
          );
          _expectCloseOrBothNull(
            base['scaleFactor'],
            hit['scaleFactor'],
            '$ts hit scaleFactor',
          );
        }

        // At least one cache hit should have been recorded in pass 3
        expect(
          FaceStabilizer.transformCacheHits +
              FaceStabilizer.cacheHits +
              FaceStabilizer.noFacesSentinelHits,
          greaterThan(0),
          reason: 'Should have recorded at least one cache hit',
        );
      },
    );

    testWidgets(
      'multi-face transform cache entry is ignored and falls through',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 3));

        projectId = await createFaceProject();

        final rawDir = await DirUtils.getRawPhotoDirPath(projectId!);
        const ts = '5000000000';
        final rawPath = p.join(rawDir, '$ts.jpg');

        final solidImage = img.Image(width: 100, height: 100);
        img.fill(solidImage, color: img.ColorRgb8(64, 96, 128));
        await File(rawPath).writeAsBytes(img.encodeJpg(solidImage));
        final fileSize = await File(rawPath).length();
        await DB.instance.addPhoto(
          ts,
          projectId!,
          '.jpg',
          fileSize,
          '$ts.jpg',
          'portrait',
        );

        final settings = await StabilizationSettings.load(projectId!);
        final dims = StabUtils.getOutputDimensions(
          settings.resolution,
          settings.aspectRatio,
          settings.projectOrientation,
        )!;
        final fingerprint = await StabUtils.computeRawPhotoFingerprint(rawPath);
        final settingsHash = TransformCacheKey.buildSettingsHash(
          settings: settings,
          canvasWidth: dims.$1,
          canvasHeight: dims.$2,
        );
        final cacheKey = TransformCacheKey.buildCacheKey(
          projectId: projectId!,
          fingerprint: fingerprint,
          projectType: settings.projectType,
          modelVersion: StabUtils.detectorModelVersionForProjectType('face'),
          settingsHash: settingsHash,
        );

        await DB.instance.writeTransformCache(
          TransformCacheEntry(
            cacheKey: cacheKey,
            projectId: projectId!,
            fingerprint: fingerprint,
            projectType: settings.projectType,
            modelVersion: StabUtils.detectorModelVersionForProjectType('face'),
            transformAlgorithmVersion:
                TransformCacheKey.transformAlgorithmVersion,
            settingsHash: settingsHash,
            scope: TransformCacheKey.defaultScope,
            sourceOrientation: 'original',
            selectedFaceIndex: 1,
            faceCount: 2,
            canvasWidth: dims.$1,
            canvasHeight: dims.$2,
            translateX: 0,
            translateY: 0,
            rotationDegrees: 0,
            scaleFactor: 1,
            finalScore: 0,
            createdAt: 1000,
            updatedAt: 1000,
          ),
        );

        FaceStabilizer.resetCacheCounters();
        final stabilizer = FaceStabilizer(
          projectId!,
          () {},
          settings: settings,
        );
        await stabilizer.stabilize(rawPath, null, () {});
        await stabilizer.dispose();

        final photos = await DB.instance.getPhotosByProjectID(projectId!);
        expect(photos.first['noFacesFound'], 1);
        expect(
          FaceStabilizer.transformCacheHits,
          0,
          reason: 'multi-face transform cache entries must not direct-render',
        );
      },
    );

    testWidgets(
      'no-face sentinel: solid-color frame writes sentinel, re-stab hits it',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 3));

        projectId = await createFaceProject();

        // Create a solid-color PNG (no face) as raw photo
        final rawDir = await DirUtils.getRawPhotoDirPath(projectId!);
        const ts = '5000000001';
        final rawPath = p.join(rawDir, '$ts.jpg');

        final solidImage = img.Image(width: 100, height: 100);
        img.fill(solidImage, color: img.ColorRgb8(128, 64, 32));
        await File(rawPath).writeAsBytes(img.encodeJpg(solidImage));
        final fileSize = await File(rawPath).length();
        await DB.instance.addPhoto(
          ts,
          projectId!,
          '.jpg',
          fileSize,
          '$ts.jpg',
          'portrait',
        );

        final settings = await StabilizationSettings.load(projectId!);

        // Pass 1: should detect no face and write sentinel
        FaceStabilizer.faceDetectionCacheEnabled = true;
        var stabilizer = FaceStabilizer(projectId!, () {}, settings: settings);
        await stabilizer.stabilize(rawPath, null, () {});
        await stabilizer.dispose();

        final photos1 = await DB.instance.getPhotosByProjectID(projectId!);
        expect(
          photos1.first['noFacesFound'],
          1,
          reason:
              'noFacesFound should be set after first stabilization of no-face image',
        );

        final fingerprint = await StabUtils.computeRawPhotoFingerprint(rawPath);
        final cached = await DB.instance.getFaceDetectionCache(
          ts,
          projectId!,
          StabUtils.detectorModelVersionForProjectType('face'),
          fingerprint,
        );
        expect(
          cached,
          isNotNull,
          reason: 'Cache should have entry for no-face image',
        );
        expect(
          cached!.isNoFaces,
          isTrue,
          reason: 'Cache entry should be no_faces sentinel',
        );

        // Reset flags (but keep cache rows)
        await DB.instance.resetStabilizedColumnByTimestamp(
          'portrait',
          ts,
          projectId!,
        );

        // Pass 2: should hit the sentinel from cache
        FaceStabilizer.resetCacheCounters();
        stabilizer = FaceStabilizer(projectId!, () {}, settings: settings);
        await stabilizer.stabilize(rawPath, null, () {});
        await stabilizer.dispose();

        final photos2 = await DB.instance.getPhotosByProjectID(projectId!);
        expect(
          photos2.first['noFacesFound'],
          1,
          reason: 'noFacesFound should still be set after cache-hit run',
        );

        expect(
          FaceStabilizer.noFacesSentinelHits,
          1,
          reason: 'Should have recorded one no_faces sentinel hit',
        );
        expect(
          FaceStabilizer.cacheHits,
          1,
          reason: 'cacheHits counter should include the sentinel hit',
        );
      },
    );
  });
}

TransformCacheEntry _makeTransformEntry(
  int projectId, {
  String cacheKey = 'transform-cache-key',
  String fingerprint = '12345:abcdef1234567890abcdef1234567890',
  String settingsHash = 'settings-hash',
  String scope = 'auto',
  int faceCount = 2,
  int? selectedFaceIndex = 1,
}) {
  return TransformCacheEntry(
    cacheKey: cacheKey,
    projectId: projectId,
    fingerprint: fingerprint,
    projectType: 'face',
    modelVersion: 'face-model-v1',
    transformAlgorithmVersion: 'face_stabilizer_transform_v1',
    settingsHash: settingsHash,
    scope: scope,
    sourceOrientation: 'original',
    selectedFaceIndex: selectedFaceIndex,
    faceCount: faceCount,
    sourceWidth: 4000,
    sourceHeight: 3000,
    canvasWidth: 1920,
    canvasHeight: 1080,
    translateX: 10.25,
    translateY: -3.5,
    rotationDegrees: 1.25,
    scaleFactor: 1.1,
    finalScore: 0.95,
    finalEyeDeltaY: 0.1,
    finalEyeDistance: 280.0,
    goalEyeDistance: 300.0,
    preScore: 0.4,
    rotationPassScore: 0.6,
    scalePassScore: 0.8,
    translationPassScore: 0.95,
    createdAt: 1000,
    updatedAt: 1000,
  );
}

void _expectCloseOrBothNull(dynamic a, dynamic b, String label) {
  if (a == null && b == null) return;
  expect(
    a,
    isNotNull,
    reason: '$label: baseline is non-null but cached is null',
  );
  expect(
    b,
    isNotNull,
    reason: '$label: cached is non-null but baseline is null',
  );
  expect(
    (a as num).toDouble(),
    closeTo((b as num).toDouble(), 1e-6),
    reason: '$label: values should be equal within 1e-6',
  );
}
