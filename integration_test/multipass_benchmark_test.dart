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

/// Multi-pass benchmark using Taylor Swift photo set.
///
/// Uses a larger, more varied photo set to exercise multi-pass stabilization
/// (2/3/4-pass correction). Run with:
///   flutter test integration_test/multipass_benchmark_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  /// Source directory containing extracted Taylor Swift JPGs.
  const String sourceDir = '/tmp/taylor-swift-bench';

  /// Max photos per round (use subset to keep runtime reasonable).
  const int maxPhotos = 20;

  group('Multi-Pass Benchmark', () {
    int? testProjectId;
    final List<String> fixturePaths = [];

    setUpAll(() async {
      initDatabase();
      await DB.instance.createTablesIfNotExist();
      await IsolatePool.instance.initialize();
    });

    tearDownAll(() async {
      await IsolatePool.instance.dispose();
    });

    Future<int> createBenchmarkProject(String name) async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final projectId = await DB.instance.addProject(name, 'face', timestamp);
      final pid = projectId.toString();

      await DB.instance
          .setSettingByTitle('project_orientation', 'portrait', pid);
      await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
      await DB.instance.setSettingByTitle('aspect_ratio', '16:9', pid);
      await DB.instance.setSettingByTitle('background_color', '#000000', pid);

      final rawDir = await DirUtils.getRawPhotoDirPath(projectId);
      await Directory(rawDir).create(recursive: true);
      final stabDir = await DirUtils.getStabilizedDirPath(projectId);
      await Directory(p.join(stabDir, 'portrait')).create(recursive: true);
      final thumbDir = await DirUtils.getThumbnailDirPath(projectId);
      await Directory(p.join(thumbDir, 'stabilized', 'portrait'))
          .create(recursive: true);
      final failDir = await DirUtils.getFailureDirPath(projectId);
      await Directory(failDir).create(recursive: true);

      for (int i = 0; i < fixturePaths.length; i++) {
        final ts = (1000000000 + (i * 1000)).toString();
        final destPath = p.join(rawDir, '$ts.jpg');
        await File(fixturePaths[i]).copy(destPath);
        final fileSize = await File(destPath).length();
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

    Future<void> cleanupProject(int projectId) async {
      try {
        final projectDir = await DirUtils.getProjectDirPath(projectId);
        if (await Directory(projectDir).exists()) {
          await Directory(projectDir).delete(recursive: true);
        }
        await DB.instance.deleteProject(projectId);
      } catch (_) {}
    }

    Future<List<Map<String, dynamic>>> runStabilizationRound(
      int projectId,
    ) async {
      final results = <Map<String, dynamic>>[];
      final settings = await StabilizationSettings.load(projectId);
      final stabilizer = FaceStabilizer(projectId, () {}, settings: settings);
      await stabilizer.init();

      try {
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
            'preScore': result.preScore,
            'twoPassScore': result.twoPassScore,
            'threePassScore': result.threePassScore,
            'fourPassScore': result.fourPassScore,
          });
        }
      } finally {
        await stabilizer.dispose();
      }

      return results;
    }

    // ── Load fixtures ──────────────────────────────────────────────────

    testWidgets('load fixtures', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final dir = Directory(sourceDir);
      if (!await dir.exists()) {
        markTestSkipped('Source dir $sourceDir not found');
        return;
      }

      final files =
          await dir.list().where((f) => f.path.endsWith('.jpg')).toList();
      files.sort((a, b) => a.path.compareTo(b.path));

      for (int i = 0; i < files.length && i < maxPhotos; i++) {
        fixturePaths.add(files[i].path);
      }

      debugPrint('Loaded ${fixturePaths.length} fixture photos');
      expect(fixturePaths, isNotEmpty);
    });

    // ── SLOW MODE benchmark ────────────────────────────────────────────

    testWidgets('benchmark: slow mode', (tester) async {
      if (fixturePaths.isEmpty) {
        markTestSkipped('Fixtures not loaded');
        return;
      }

      testProjectId = await createBenchmarkProject('SlowMultiPass');
      final results = await runStabilizationRound(testProjectId!);

      int multiPassCount = 0;
      int totalMs = 0;

      for (final r in results) {
        final ms = r['elapsedMs'] as int;
        totalMs += ms;
        final hasTwoPass = r['twoPassScore'] != null;
        final hasThreePass = r['threePassScore'] != null;
        final hasFourPass = r['fourPassScore'] != null;

        String passInfo = '1-pass';
        if (hasFourPass) {
          passInfo = '4-pass';
          multiPassCount++;
        } else if (hasThreePass) {
          passInfo = '3-pass';
          multiPassCount++;
        } else if (hasTwoPass) {
          passInfo = '2-pass';
          multiPassCount++;
        }

        final score = r['score'] as double?;
        debugPrint(
          '  ${r['timestamp']}: ${ms}ms [$passInfo] '
          'score=${score?.toStringAsFixed(2) ?? "n/a"} '
          'success=${r['success']}',
        );
      }

      final avgMs = totalMs / results.length;
      final successCount = results.where((r) => r['success'] == true).length;

      debugPrint('');
      debugPrint('═══════════════════════════════════════════════');
      debugPrint('  SLOW MODE MULTI-PASS BENCHMARK');
      debugPrint('═══════════════════════════════════════════════');
      debugPrint('  Photos: ${results.length}');
      debugPrint('  Successful: $successCount/${results.length}');
      debugPrint('  Multi-pass triggered: $multiPassCount/${results.length}');
      debugPrint('  ─────────────────────────────────────────');
      debugPrint('  Avg:   ${avgMs.toStringAsFixed(0)} ms/photo');
      debugPrint('  Total: ${totalMs}ms');
      debugPrint('═══════════════════════════════════════════════');
      debugPrint('');

      await cleanupProject(testProjectId!);
      testProjectId = null;
      await IsolatePool.instance.clearMatCache();

      expect(successCount, greaterThan(0));
    });
  });
}
