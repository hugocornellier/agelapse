import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/services/face_stabilizer.dart';
import 'package:agelapse/services/isolate_pool.dart';
import 'package:agelapse/services/stabilization_settings.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as p;

import 'test_utils.dart';

/// Benchmark integration test for the stabilization pipeline.
///
/// Measures per-photo stabilization time across multiple rounds to establish
/// a reliable baseline. Used to validate performance optimizations.
///
/// Run with:
///   flutter test integration_test/stabilization_benchmark_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  /// Number of complete rounds to run for timing stability.
  const int rounds = 3;

  /// Face fixture days available.
  const List<int> faceDays = [1, 2, 3];

  group('Stabilization Benchmark', () {
    int? testProjectId;
    bool fixturesReady = false;
    final List<String> fixturePaths = [];

    setUpAll(() async {
      initDatabase();
      await DB.instance.createTablesIfNotExist();

      // Pre-initialize the isolate pool once
      await IsolatePool.instance.initialize();
    });

    tearDownAll(() async {
      await IsolatePool.instance.dispose();
      await cleanupFixtures();
    });

    /// Creates a fresh project with raw face photos ready for stabilization.
    /// Returns the project ID.
    Future<int> createBenchmarkProject(String name) async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final projectId = await DB.instance.addProject(name, 'face', timestamp);
      final pid = projectId.toString();

      // Configure project settings
      await DB.instance
          .setSettingByTitle('project_orientation', 'portrait', pid);
      await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
      await DB.instance.setSettingByTitle('aspect_ratio', '16:9', pid);
      await DB.instance.setSettingByTitle('background_color', '#000000', pid);

      // Create raw photos directory and copy fixtures
      final rawDir = await DirUtils.getRawPhotoDirPath(projectId);
      await Directory(rawDir).create(recursive: true);

      // Also create stabilized + thumbnail dirs (stabilizer writes there)
      final stabDir = await DirUtils.getStabilizedDirPath(projectId);
      await Directory(p.join(stabDir, 'portrait')).create(recursive: true);
      final thumbDir = await DirUtils.getThumbnailDirPath(projectId);
      await Directory(p.join(thumbDir, 'stabilized', 'portrait'))
          .create(recursive: true);
      // Failure dir
      final failDir = await DirUtils.getFailureDirPath(projectId);
      await Directory(failDir).create(recursive: true);

      for (int i = 0; i < fixturePaths.length; i++) {
        final ts = (1000000000 + (i * 1000)).toString();
        final destPath = p.join(rawDir, '$ts.jpg');

        // Copy fixture face image to raw photo dir
        await File(fixturePaths[i]).copy(destPath);

        final fileSize = await File(destPath).length();

        // Register in DB as unstabilized
        await DB.instance.addPhoto(
          ts,
          projectId,
          '.jpg',
          fileSize,
          '$ts.jpg',
          'portrait',
        );
      }

      return projectId;
    }

    /// Cleans up a benchmark project.
    Future<void> cleanupProject(int projectId) async {
      try {
        final projectDir = await DirUtils.getProjectDirPath(projectId);
        if (await Directory(projectDir).exists()) {
          await Directory(projectDir).delete(recursive: true);
        }
        await DB.instance.deleteProject(projectId);
      } catch (_) {}
    }

    /// Runs one full stabilization round on all photos in a project.
    /// Returns list of (photoTimestamp, elapsedMs, success, score).
    Future<List<Map<String, dynamic>>> runStabilizationRound(
      int projectId,
    ) async {
      final results = <Map<String, dynamic>>[];

      // Load settings and create stabilizer
      final settings = await StabilizationSettings.load(projectId);
      final stabilizer = FaceStabilizer(projectId, () {}, settings: settings);
      await stabilizer.init();

      try {
        // Get unstabilized photos
        final rawDir = await DirUtils.getRawPhotoDirPath(projectId);
        final photos = await DB.instance.getUnstabilizedPhotos(
          projectId,
          'portrait',
        );

        for (final photo in photos) {
          final ts = photo['timestamp'] as String;
          final ext = photo['fileExtension'] as String;
          final rawPath = p.join(rawDir, '$ts$ext');

          final sw = Stopwatch()..start();
          final result = await stabilizer.stabilize(rawPath, null, () {});
          sw.stop();

          results.add({
            'timestamp': ts,
            'elapsedMs': sw.elapsedMilliseconds,
            'success': result.success,
            'score': result.finalScore,
            'eyeDeltaY': result.finalEyeDeltaY,
            'eyeDistance': result.finalEyeDistance,
          });
        }
      } finally {
        await stabilizer.dispose();
      }

      return results;
    }

    // ── Load fixtures once ──────────────────────────────────────────────

    testWidgets('load fixtures', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await preloadFixtures();
      if (fixturesUnavailable) {
        markTestSkipped('Test fixtures not available');
        return;
      }

      for (final day in faceDays) {
        final path = await getSampleFacePathAsync(day);
        if (!await File(path).exists()) {
          markTestSkipped('Face fixture day$day.jpg not found');
          return;
        }
        fixturePaths.add(path);
      }

      fixturesReady = true;
      expect(fixturePaths.length, faceDays.length);
    });

    // ── SLOW MODE benchmark ─────────────────────────────────────────────

    testWidgets('benchmark: slow mode ($rounds rounds)', (tester) async {
      if (!fixturesReady) {
        markTestSkipped('Fixtures not loaded');
        return;
      }

      final allRoundResults = <List<Map<String, dynamic>>>[];

      for (int round = 0; round < rounds; round++) {
        // Create fresh project each round (photos must be unstabilized)
        testProjectId = await createBenchmarkProject('SlowBench_R$round');

        final roundResults = await runStabilizationRound(testProjectId!);
        allRoundResults.add(roundResults);

        // Print per-round results
        final roundTotalMs = roundResults.fold<int>(
            0, (sum, r) => sum + (r['elapsedMs'] as int));
        final roundAvgMs = roundTotalMs / roundResults.length;

        debugPrint(
          '  [SLOW] Round ${round + 1}/$rounds: '
          '${roundResults.length} photos, '
          'total=${roundTotalMs}ms, '
          'avg=${roundAvgMs.toStringAsFixed(0)}ms/photo',
        );

        for (final r in roundResults) {
          final score = r['score'] as double?;
          debugPrint(
            '    photo ${r['timestamp']}: '
            '${r['elapsedMs']}ms, '
            'success=${r['success']}, '
            'score=${score?.toStringAsFixed(2) ?? 'n/a'}',
          );
        }

        await cleanupProject(testProjectId!);
        testProjectId = null;

        // Clear mat cache between rounds
        await IsolatePool.instance.clearMatCache();
      }

      // Aggregate
      final allTimes = allRoundResults
          .expand((r) => r)
          .map((r) => r['elapsedMs'] as int)
          .toList();
      final totalPhotos = allTimes.length;
      final grandTotalMs = allTimes.fold<int>(0, (a, b) => a + b);
      final grandAvgMs = grandTotalMs / totalPhotos;
      allTimes.sort();
      final medianMs = allTimes[allTimes.length ~/ 2];
      final minMs = allTimes.first;
      final maxMs = allTimes.last;

      final successCount = allRoundResults
          .expand((r) => r)
          .where((r) => r['success'] == true)
          .length;

      debugPrint('');
      debugPrint('═══════════════════════════════════════════════');
      debugPrint('  SLOW MODE BENCHMARK RESULTS');
      debugPrint('═══════════════════════════════════════════════');
      debugPrint('  Rounds: $rounds');
      debugPrint('  Photos per round: ${faceDays.length}');
      debugPrint('  Total stabilizations: $totalPhotos');
      debugPrint('  Successful: $successCount/$totalPhotos');
      debugPrint('  ─────────────────────────────────────────');
      debugPrint('  Avg:    ${grandAvgMs.toStringAsFixed(0)} ms/photo');
      debugPrint('  Median: $medianMs ms/photo');
      debugPrint('  Min:    $minMs ms/photo');
      debugPrint('  Max:    $maxMs ms/photo');
      debugPrint('  Total:  ${grandTotalMs}ms');
      debugPrint('═══════════════════════════════════════════════');
      debugPrint('');

      // At least some photos should succeed
      expect(successCount, greaterThan(0));
    });
  });
}
