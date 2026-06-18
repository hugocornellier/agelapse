import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
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
/// Measures per-photo stabilization time across multiple rounds AND captures a
/// content hash of every stabilized output, so performance changes can be
/// validated for both speed and byte-for-byte output parity.
///
/// Speed: per-photo wall-clock, aggregated as median over the measured rounds
/// (the first [warmupRounds] are discarded as warm-up).
///
/// Parity: each stabilized PNG is SHA-256 hashed. Stabilization is expected to
/// be deterministic, so every round must produce the same hash for a given
/// fixture (an intra-run determinism check enforces this). The per-fixture
/// hash + transform are written to a manifest file named by the PERF_LABEL
/// env var, so a BEFORE run and an AFTER run can be diffed:
///
///   PERF_LABEL=baseline flutter test integration_test/stabilization_benchmark_test.dart -d macos
///   # ...apply one optimization...
///   PERF_LABEL=change_a1 flutter test integration_test/stabilization_benchmark_test.dart -d macos
///   diff /tmp/agelapse_perf/baseline.manifest /tmp/agelapse_perf/change_a1.manifest
///
/// An empty diff = byte-identical output (parity holds); compare the printed
/// median ms/photo for the speed delta.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  /// Number of complete rounds to run for timing stability.
  const int rounds = 6;

  /// Leading rounds discarded from the speed median (cold caches / JIT warm-up).
  const int warmupRounds = 1;

  /// Label for the output parity manifest. Prefer a compile-time define
  /// (--dart-define=PERF_LABEL=...), which is reliably available on desktop
  /// integration tests; fall back to the process env var, then a default.
  const String perfLabelDefine = String.fromEnvironment('PERF_LABEL');
  final String perfLabel = perfLabelDefine.isNotEmpty
      ? perfLabelDefine
      : (Platform.environment['PERF_LABEL'] ?? 'run');

  /// When set (--dart-define=PERF_LARGE=true), fixtures are upscaled to ~12 MP
  /// before stabilization. The 640x480 fixtures hide decode-bound costs (a full
  /// decode is sub-ms there but ~16 ms at 12 MP); this exercises the real
  /// large-photo / old-hardware regime.
  const String perfLargeDefine = String.fromEnvironment('PERF_LARGE');
  final bool perfLarge =
      perfLargeDefine == 'true' || Platform.environment['PERF_LARGE'] == 'true';

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

        if (perfLarge) {
          // Upscale the fixture to ~12 MP (4000x3000) and re-encode, to
          // exercise the decode-bound regime real photos hit.
          final mat = cv.imdecode(
            await File(fixturePaths[i]).readAsBytes(),
            cv.IMREAD_COLOR,
          );
          final big =
              cv.resize(mat, (4000, 3000), interpolation: cv.INTER_CUBIC);
          final (ok, jpg) = cv.imencode('.jpg', big);
          mat.dispose();
          big.dispose();
          if (!ok) throw StateError('Failed to encode large fixture');
          await File(destPath).writeAsBytes(jpg);
        } else {
          // Copy fixture face image to raw photo dir
          await File(fixturePaths[i]).copy(destPath);
        }

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
    /// Returns per-photo maps including elapsed time and an output content hash.
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
        final stabDir = await DirUtils.getStabilizedDirPath(projectId);
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

          // Hash the stabilized output for parity checking. saveStabilizedImage
          // always writes a .png in the orientation subdir, regardless of the
          // .jpg path naming.
          final outPath = p.join(stabDir, 'portrait', '$ts.png');
          String outputHash = 'MISSING';
          int outputBytes = 0;
          final outFile = File(outPath);
          if (await outFile.exists()) {
            final bytes = await outFile.readAsBytes();
            outputBytes = bytes.length;
            outputHash = sha256.convert(bytes).toString();
          }

          // Capture the stored face embedding (single-face photos) so changes
          // to the embedding path can be verified bit-identical, not just the
          // PNG. The embedding is a stored side effect of stabilize().
          String embeddingHash = 'none';
          final row =
              await DB.instance.getActivePhotoByTimestamp(ts, projectId);
          final emb = row?['faceEmbedding'] as Uint8List?;
          if (emb != null) {
            embeddingHash = '${emb.length}:${sha256.convert(emb)}';
          }

          results.add({
            'timestamp': ts,
            'elapsedMs': sw.elapsedMilliseconds,
            'success': result.success,
            'score': result.finalScore,
            'eyeDeltaY': result.finalEyeDeltaY,
            'eyeDistance': result.finalEyeDistance,
            'translateX': result.translateX,
            'translateY': result.translateY,
            'rotationDegrees': result.rotationDegrees,
            'scaleFactor': result.scaleFactor,
            'outputHash': outputHash,
            'outputBytes': outputBytes,
            'embeddingHash': embeddingHash,
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

      // ── Speed aggregate (measured rounds only; warm-up discarded) ──────
      final measuredResults = <Map<String, dynamic>>[];
      for (int round = warmupRounds; round < allRoundResults.length; round++) {
        measuredResults.addAll(allRoundResults[round]);
      }
      final measuredTimes =
          measuredResults.map((r) => r['elapsedMs'] as int).toList()..sort();
      final totalPhotos = measuredTimes.length;
      final grandTotalMs = measuredTimes.fold<int>(0, (a, b) => a + b);
      final grandAvgMs = grandTotalMs / totalPhotos;
      final medianMs = measuredTimes[measuredTimes.length ~/ 2];
      final p25Ms = measuredTimes[(measuredTimes.length * 0.25).floor()];
      final p75Ms = measuredTimes[(measuredTimes.length * 0.75).floor()];
      final minMs = measuredTimes.first;
      final maxMs = measuredTimes.last;

      final successCount =
          measuredResults.where((r) => r['success'] == true).length;

      // ── Parity: per-fixture output hash + determinism check ────────────
      // Group every round's result by timestamp; a deterministic pipeline
      // must yield one identical hash per fixture across all rounds.
      final byTimestamp = <String, List<Map<String, dynamic>>>{};
      for (final r in allRoundResults.expand((x) => x)) {
        (byTimestamp[r['timestamp'] as String] ??= []).add(r);
      }
      final sortedTimestamps = byTimestamp.keys.toList()..sort();

      final nonDeterministic = <String>[];
      final manifestLines = <String>[];
      for (final ts in sortedTimestamps) {
        final entries = byTimestamp[ts]!;
        // Determinism over both the PNG and the stored embedding.
        final hashes = entries
            .map((e) => '${e['outputHash']}|${e['embeddingHash']}')
            .toSet();
        if (hashes.length > 1) nonDeterministic.add(ts);
        final first = entries.first;
        String fmt(Object? v) =>
            v is double ? v.toStringAsFixed(6) : v.toString();
        manifestLines.add(
          'ts=$ts '
          'hash=${first['outputHash']} '
          'bytes=${first['outputBytes']} '
          'success=${first['success']} '
          'score=${fmt(first['score'])} '
          'tx=${fmt(first['translateX'])} '
          'ty=${fmt(first['translateY'])} '
          'rot=${fmt(first['rotationDegrees'])} '
          'scale=${fmt(first['scaleFactor'])} '
          'emb=${first['embeddingHash']}',
        );
      }

      // Write the manifest for BEFORE/AFTER diffing.
      final manifestDir = Directory('/tmp/agelapse_perf');
      await manifestDir.create(recursive: true);
      final manifestFile =
          File(p.join(manifestDir.path, '$perfLabel.manifest'));
      await manifestFile.writeAsString('${manifestLines.join('\n')}\n');

      debugPrint('');
      debugPrint('═══════════════════════════════════════════════');
      debugPrint('  STABILIZATION BENCHMARK — label="$perfLabel" '
          '(${perfLarge ? "~12MP upscaled" : "640x480 fixture"})');
      debugPrint('═══════════════════════════════════════════════');
      debugPrint('  Rounds: $rounds (warm-up discarded: $warmupRounds)');
      debugPrint('  Photos per round: ${faceDays.length}');
      debugPrint('  Measured stabilizations: $totalPhotos');
      debugPrint('  Successful: $successCount/$totalPhotos');
      debugPrint('  ───────────── SPEED (measured rounds) ─────────');
      debugPrint('  Median: $medianMs ms/photo');
      debugPrint('  Avg:    ${grandAvgMs.toStringAsFixed(0)} ms/photo');
      debugPrint('  p25/p75: $p25Ms / $p75Ms ms/photo');
      debugPrint('  Min/Max: $minMs / $maxMs ms/photo');
      debugPrint('  ───────────── PARITY ──────────────────────────');
      if (nonDeterministic.isEmpty) {
        debugPrint('  Determinism: OK (identical hash across all rounds)');
      } else {
        debugPrint(
          '  Determinism: FAILED for ${nonDeterministic.join(', ')} '
          '(hash-based parity is unreliable for these)',
        );
      }
      debugPrint('  Manifest: ${manifestFile.path}');
      for (final line in manifestLines) {
        debugPrint('    $line');
      }
      debugPrint('═══════════════════════════════════════════════');
      debugPrint('');

      // At least some photos should succeed
      expect(successCount, greaterThan(0));
      // Output must be deterministic for hash-based parity to be meaningful.
      expect(nonDeterministic, isEmpty,
          reason: 'Stabilization output is non-deterministic across rounds; '
              'hash-based parity checking will not work.');
    });
  });
}
