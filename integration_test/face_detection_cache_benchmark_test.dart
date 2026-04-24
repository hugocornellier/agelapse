import 'dart:io';

import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/services/face_stabilizer.dart';
import 'package:agelapse/services/isolate_pool.dart';
import 'package:agelapse/services/stabilization_settings.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/photo_fingerprint.dart';
import 'package:agelapse/utils/stabilizer_utils/stabilizer_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'test_utils.dart';

/// Benchmarks the exact scenario where FaceDetectionCache should help and
/// TransformCache must not participate:
///
/// 1. Stabilize at 1080p with cache enabled to seed FaceDetectionCache.
/// 2. Switch to 4K, which changes the transform settings hash.
/// 3. Compare 4K no-cache vs 4K FaceDetectionCache-only runs.
///
/// Recommended command:
///
/// flutter test integration_test/face_detection_cache_benchmark_test.dart \
///   -d macos \
///   --dart-define=FACE_CACHE_BENCH_DIR=/path/to/face/photos \
///   --dart-define=FACE_CACHE_BENCH_MAX_PHOTOS=30 \
///   --dart-define=FACE_CACHE_BENCH_ROUNDS=5 \
///   --dart-define=FACE_CACHE_MIN_SPEEDUP_PCT=5
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  const configuredSourceDir = String.fromEnvironment('FACE_CACHE_BENCH_DIR');
  const maxPhotos = int.fromEnvironment(
    'FACE_CACHE_BENCH_MAX_PHOTOS',
    defaultValue: 20,
  );
  const rounds = int.fromEnvironment(
    'FACE_CACHE_BENCH_ROUNDS',
    defaultValue: 5,
  );
  const minSpeedupPctText = String.fromEnvironment(
    'FACE_CACHE_MIN_SPEEDUP_PCT',
  );

  group('FaceDetectionCache 1080p seed -> 4K benchmark', () {
    setUpAll(() async {
      initDatabase();
      await DB.instance.createTablesIfNotExist();
      await IsolatePool.instance.initialize();
    });

    tearDownAll(() async {
      FaceStabilizer.faceDetectionCacheEnabled = true;
      await IsolatePool.instance.dispose();
      await cleanupFixtures();
    });

    testWidgets('FaceDetectionCache-only 4K speed comparison', (tester) async {
      app.main();
      await pumpUntilAppReady(tester, maxSeconds: 20);

      final sources = await _loadBenchmarkSources(
        configuredSourceDir: configuredSourceDir,
        maxPhotos: maxPhotos,
      );
      if (sources.length < 2) {
        markTestSkipped(
          'Need at least 2 unique face photos for the benchmark. '
          'Set FACE_CACHE_BENCH_DIR to a folder of face photos.',
        );
        return;
      }

      final minSpeedupPct = double.tryParse(minSpeedupPctText);
      final comparisons = <_RoundComparison>[];

      debugPrint('');
      debugPrint('══════════════════════════════════════════════════════════');
      debugPrint(' FaceDetectionCache-only 4K benchmark');
      debugPrint(' Photos: ${sources.length}');
      debugPrint(' Rounds: $rounds');
      debugPrint(
        ' Source: ${configuredSourceDir.isEmpty ? _defaultBenchDirOrFixtures : configuredSourceDir}',
      );
      debugPrint('══════════════════════════════════════════════════════════');

      for (int round = 0; round < rounds; round++) {
        final cachedFirst = round.isOdd;
        final projectId = await _createBenchmarkProject(
          'FaceCacheBench_R$round',
          sources,
        );

        try {
          await _configureProject(projectId, resolution: '1080p');
          await DB.instance.clearFaceDetectionCacheForProject(projectId);
          await DB.instance.clearTransformCacheForProject(projectId);
          FaceStabilizer.faceDetectionCacheEnabled = true;

          final seed = await _runMeasuredStabilization(
            projectId: projectId,
            mode: 'seed_1080p',
          );
          expect(
            seed.successCount,
            sources.length,
            reason: 'Seed run must stabilize every benchmark source.',
          );
          await _expectFaceCacheSeeded(projectId, sources.length);

          await _configureProject(projectId, resolution: '4K');
          await _resetStabilizationOutputs(projectId);

          _RunSummary baseline;
          _RunSummary cached;
          if (cachedFirst) {
            cached = await _runFaceCacheOnly4K(projectId);
            await _resetStabilizationOutputs(projectId);
            baseline = await _runNoCache4K(projectId);
          } else {
            baseline = await _runNoCache4K(projectId);
            await _resetStabilizationOutputs(projectId);
            cached = await _runFaceCacheOnly4K(projectId);
          }

          _expectEquivalentOutputs(baseline, cached);

          final comparison = _RoundComparison(
            round: round + 1,
            cachedFirst: cachedFirst,
            baseline: baseline,
            cached: cached,
          );
          comparisons.add(comparison);
          _printRoundComparison(comparison);
        } finally {
          FaceStabilizer.faceDetectionCacheEnabled = true;
          await _cleanupProject(projectId);
          await IsolatePool.instance.clearMatCache();
        }
      }

      final aggregate = _aggregateComparisons(comparisons);
      _printAggregate(aggregate);

      expect(
        comparisons,
        isNotEmpty,
        reason: 'Benchmark should produce at least one comparison round.',
      );
      expect(
        aggregate.cachedTransformHits,
        0,
        reason: 'TransformCache must never hit in this benchmark.',
      );
      expect(
        aggregate.cachedFaceHits,
        greaterThan(0),
        reason: 'FaceDetectionCache must hit in the cached 4K run.',
      );

      if (minSpeedupPct != null) {
        expect(
          aggregate.medianSpeedupPct,
          greaterThanOrEqualTo(minSpeedupPct),
          reason: 'FACE_CACHE_MIN_SPEEDUP_PCT=$minSpeedupPct was requested.',
        );
      }
    });
  });
}

const _defaultBenchDir = '/tmp/taylor-swift-bench';
const _defaultBenchDirOrFixtures =
    '$_defaultBenchDir if present, else fixtures';
const _projectOrientation = 'portrait';
const _aspectRatio = '16:9';
const _modelVersion = 'face';
const _allowedExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.heic',
  '.heif',
  '.avif',
  '.webp',
  '.tif',
  '.tiff',
  '.jp2',
};

class _BenchSource {
  final String path;
  final String fingerprint;

  const _BenchSource({
    required this.path,
    required this.fingerprint,
  });
}

class _PhotoResult {
  final String timestamp;
  final int elapsedMs;
  final bool success;
  final double? finalScore;
  final double? translateX;
  final double? translateY;
  final double? rotationDegrees;
  final double? scaleFactor;

  const _PhotoResult({
    required this.timestamp,
    required this.elapsedMs,
    required this.success,
    required this.finalScore,
    required this.translateX,
    required this.translateY,
    required this.rotationDegrees,
    required this.scaleFactor,
  });
}

class _RunSummary {
  final String mode;
  final List<_PhotoResult> results;
  final int faceCacheHits;
  final int noFacesSentinelHits;
  final int transformCacheHits;
  final int transformCacheMisses;
  final int transformCacheRenderFailures;

  const _RunSummary({
    required this.mode,
    required this.results,
    required this.faceCacheHits,
    required this.noFacesSentinelHits,
    required this.transformCacheHits,
    required this.transformCacheMisses,
    required this.transformCacheRenderFailures,
  });

  int get totalMs => results.fold(0, (sum, r) => sum + r.elapsedMs);
  int get successCount => results.where((r) => r.success).length;
  double get meanMs => results.isEmpty ? 0 : totalMs / results.length;
  double get medianMs => _percentile(
        results.map((r) => r.elapsedMs).toList(),
        50,
      );
  double get p95Ms => _percentile(
        results.map((r) => r.elapsedMs).toList(),
        95,
      );
}

class _RoundComparison {
  final int round;
  final bool cachedFirst;
  final _RunSummary baseline;
  final _RunSummary cached;

  const _RoundComparison({
    required this.round,
    required this.cachedFirst,
    required this.baseline,
    required this.cached,
  });

  double get medianSpeedupPct =>
      _speedupPct(baseline.medianMs, cached.medianMs);
  double get meanSpeedupPct => _speedupPct(baseline.meanMs, cached.meanMs);
}

class _AggregateComparison {
  final int rounds;
  final double baselineMedianOfMedians;
  final double cachedMedianOfMedians;
  final double baselineMeanOfMeans;
  final double cachedMeanOfMeans;
  final double medianSpeedupPct;
  final double meanSpeedupPct;
  final int cachedFaceHits;
  final int cachedTransformHits;

  const _AggregateComparison({
    required this.rounds,
    required this.baselineMedianOfMedians,
    required this.cachedMedianOfMedians,
    required this.baselineMeanOfMeans,
    required this.cachedMeanOfMeans,
    required this.medianSpeedupPct,
    required this.meanSpeedupPct,
    required this.cachedFaceHits,
    required this.cachedTransformHits,
  });
}

Future<List<_BenchSource>> _loadBenchmarkSources({
  required String configuredSourceDir,
  required int maxPhotos,
}) async {
  final paths = <String>[];

  if (configuredSourceDir.isNotEmpty) {
    paths.addAll(await _listImageFiles(configuredSourceDir));
  } else if (await Directory(_defaultBenchDir).exists()) {
    paths.addAll(await _listImageFiles(_defaultBenchDir));
  } else {
    await preloadFixtures();
    if (fixturesUnavailable) return [];
    for (final day in [1, 2, 3]) {
      paths.add(await getSampleFacePathAsync(day));
    }
  }

  final unique = <_BenchSource>[];
  final seenFingerprints = <String>{};
  for (final imagePath in paths) {
    if (unique.length >= maxPhotos) break;
    try {
      final fingerprint = await PhotoFingerprint.compute(imagePath);
      if (!seenFingerprints.add(fingerprint)) continue;
      unique.add(_BenchSource(path: imagePath, fingerprint: fingerprint));
    } catch (_) {
      continue;
    }
  }

  return unique;
}

Future<List<String>> _listImageFiles(String dirPath) async {
  final dir = Directory(dirPath);
  if (!await dir.exists()) return [];

  final paths = <String>[];
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final basename = p.basename(entity.path);
    if (basename.startsWith('.') || entity.path.contains('__MACOSX')) continue;
    final ext = p.extension(entity.path).toLowerCase();
    if (!_allowedExtensions.contains(ext)) continue;
    paths.add(entity.path);
  }
  paths.sort();
  return paths;
}

Future<int> _createBenchmarkProject(
  String name,
  List<_BenchSource> sources,
) async {
  final createdAt = DateTime.now().millisecondsSinceEpoch;
  final projectId = await DB.instance.addProject(name, 'face', createdAt);

  await _configureProject(projectId, resolution: '1080p');
  await _createProjectDirs(projectId);

  final rawDir = await DirUtils.getRawPhotoDirPath(projectId);
  for (int i = 0; i < sources.length; i++) {
    final source = sources[i];
    final extension = p.extension(source.path).toLowerCase();
    final timestamp = (1000000000 + i * 1000).toString();
    final destination = p.join(rawDir, '$timestamp$extension');
    await File(source.path).copy(destination);
    final fileSize = await File(destination).length();

    final inserted = await DB.instance.addPhoto(
      timestamp,
      projectId,
      extension,
      fileSize,
      p.basename(source.path),
      _projectOrientation,
      fingerprint: source.fingerprint,
    );
    expect(inserted, isTrue, reason: 'Benchmark photo insert failed.');
  }

  return projectId;
}

Future<void> _configureProject(
  int projectId, {
  required String resolution,
}) async {
  final pid = projectId.toString();
  await DB.instance.setSettingByTitle(
    'project_orientation',
    _projectOrientation,
    pid,
  );
  await DB.instance.setSettingByTitle('video_resolution', resolution, pid);
  await DB.instance.setSettingByTitle('aspect_ratio', _aspectRatio, pid);
  await DB.instance.setSettingByTitle('background_color', '#000000', pid);
  await DB.instance.setSettingByTitle('auto_compile_video', 'false', pid);
}

Future<void> _createProjectDirs(int projectId) async {
  await Directory(await DirUtils.getRawPhotoDirPath(projectId))
      .create(recursive: true);
  final stabDir = await DirUtils.getStabilizedDirPath(projectId);
  await Directory(p.join(stabDir, _projectOrientation)).create(recursive: true);
  final thumbDir = await DirUtils.getThumbnailDirPath(projectId);
  await Directory(p.join(thumbDir, 'stabilized', _projectOrientation))
      .create(recursive: true);
  await Directory(await DirUtils.getFailureDirPath(projectId))
      .create(recursive: true);
}

Future<_RunSummary> _runNoCache4K(int projectId) async {
  FaceStabilizer.faceDetectionCacheEnabled = false;
  await DB.instance.clearTransformCacheForProject(projectId);
  await IsolatePool.instance.clearMatCache();
  final summary = await _runMeasuredStabilization(
    projectId: projectId,
    mode: 'baseline_4k_no_cache',
  );
  expect(summary.faceCacheHits, 0);
  expect(summary.transformCacheHits, 0);
  return summary;
}

Future<_RunSummary> _runFaceCacheOnly4K(int projectId) async {
  FaceStabilizer.faceDetectionCacheEnabled = true;
  await DB.instance.clearTransformCacheForProject(projectId);
  await IsolatePool.instance.clearMatCache();
  final summary = await _runMeasuredStabilization(
    projectId: projectId,
    mode: 'face_cache_only_4k',
  );
  expect(
    summary.faceCacheHits,
    greaterThan(0),
    reason: 'The cached 4K run must hit FaceDetectionCache.',
  );
  expect(
    summary.noFacesSentinelHits,
    0,
    reason: 'No-face sentinels would benchmark a different shortcut.',
  );
  expect(
    summary.transformCacheHits,
    0,
    reason: 'TransformCache must be excluded from this benchmark.',
  );
  return summary;
}

Future<_RunSummary> _runMeasuredStabilization({
  required int projectId,
  required String mode,
}) async {
  FaceStabilizer.resetCacheCounters();

  final settings = await StabilizationSettings.load(projectId);
  final stabilizer = FaceStabilizer(projectId, () {}, settings: settings);
  await stabilizer.init();

  final results = <_PhotoResult>[];
  try {
    final rawDir = await DirUtils.getRawPhotoDirPath(projectId);
    final photos = await DB.instance.getUnstabilizedPhotos(
      projectId,
      _projectOrientation,
      maxAttempts: 100,
    );

    for (final photo in photos) {
      final timestamp = photo['timestamp'] as String;
      final extension = photo['fileExtension'] as String;
      final rawPath = p.join(rawDir, '$timestamp$extension');

      final sw = Stopwatch()..start();
      final result = await stabilizer.stabilize(rawPath, null, () {});
      sw.stop();

      results.add(
        _PhotoResult(
          timestamp: timestamp,
          elapsedMs: sw.elapsedMilliseconds,
          success: result.success,
          finalScore: result.finalScore,
          translateX: result.translateX,
          translateY: result.translateY,
          rotationDegrees: result.rotationDegrees,
          scaleFactor: result.scaleFactor,
        ),
      );

      debugPrint(
        'CSV,$mode,$timestamp,${sw.elapsedMilliseconds},'
        '${result.success},${FaceStabilizer.cacheHits},'
        '${FaceStabilizer.transformCacheHits}',
      );
    }
  } finally {
    await stabilizer.dispose();
  }

  return _RunSummary(
    mode: mode,
    results: results,
    faceCacheHits: FaceStabilizer.cacheHits,
    noFacesSentinelHits: FaceStabilizer.noFacesSentinelHits,
    transformCacheHits: FaceStabilizer.transformCacheHits,
    transformCacheMisses: FaceStabilizer.transformCacheMisses,
    transformCacheRenderFailures: FaceStabilizer.transformCacheRenderFailures,
  );
}

Future<void> _expectFaceCacheSeeded(
  int projectId,
  int expectedCount,
) async {
  final photos = await DB.instance.getPhotosByProjectID(projectId);
  expect(photos.length, expectedCount);

  int cacheRows = 0;
  for (final photo in photos) {
    final timestamp = photo['timestamp'] as String;
    final extension = photo['fileExtension'] as String;
    final rawPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
      timestamp,
      projectId,
      fileExtension: extension,
    );
    final fingerprint = await PhotoFingerprint.compute(rawPath);
    final cached = await DB.instance.getFaceDetectionCache(
      timestamp,
      projectId,
      StabUtils.detectorModelVersionForProjectType(_modelVersion),
      fingerprint,
    );
    expect(
      cached,
      isNotNull,
      reason: '$timestamp did not seed FaceDetectionCache.',
    );
    expect(
      cached!.isNoFaces,
      isFalse,
      reason: '$timestamp seeded a no_faces sentinel; use face-only sources.',
    );
    cacheRows++;
  }

  expect(cacheRows, expectedCount);
}

Future<void> _resetStabilizationOutputs(int projectId) async {
  final photos = await DB.instance.getPhotosByProjectID(projectId);
  for (final photo in photos) {
    final timestamp = photo['timestamp'] as String;
    final extension = photo['fileExtension'] as String;
    final rawPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
      timestamp,
      projectId,
      fileExtension: extension,
    );
    await DB.instance.resetPhotoStabilizationState(
      timestamp: timestamp,
      projectId: projectId,
      orientation: _projectOrientation,
    );

    final pngPath =
        await DirUtils.getStabilizedImagePathFromRawPathAndProjectOrientation(
      projectId,
      rawPath,
      _projectOrientation,
    );
    final jpgPath = p.setExtension(pngPath, '.jpg');
    await DirUtils.deleteFileIfExists(pngPath);
    await DirUtils.deleteFileIfExists(jpgPath);
    await DirUtils.deleteFileIfExists(
      FaceStabilizer.getStabThumbnailPath(pngPath, preserveAlpha: true),
    );
    await DirUtils.deleteFileIfExists(
      FaceStabilizer.getStabThumbnailPath(pngPath, preserveAlpha: false),
    );
  }
}

void _expectEquivalentOutputs(_RunSummary baseline, _RunSummary cached) {
  expect(
    cached.results.length,
    baseline.results.length,
    reason: 'Baseline and cached runs must process the same photo count.',
  );
  expect(
    cached.successCount,
    baseline.successCount,
    reason: 'FaceDetectionCache-only run must preserve success count.',
  );

  final cachedByTimestamp = {
    for (final result in cached.results) result.timestamp: result,
  };

  for (final baselineResult in baseline.results) {
    final cachedResult = cachedByTimestamp[baselineResult.timestamp];
    expect(
      cachedResult,
      isNotNull,
      reason: '${baselineResult.timestamp} missing from cached run.',
    );
    expect(cachedResult!.success, baselineResult.success);
    if (!baselineResult.success) continue;

    _expectCloseOrBothNull(
      baselineResult.translateX,
      cachedResult.translateX,
      '${baselineResult.timestamp} translateX',
    );
    _expectCloseOrBothNull(
      baselineResult.translateY,
      cachedResult.translateY,
      '${baselineResult.timestamp} translateY',
    );
    _expectCloseOrBothNull(
      baselineResult.rotationDegrees,
      cachedResult.rotationDegrees,
      '${baselineResult.timestamp} rotationDegrees',
    );
    _expectCloseOrBothNull(
      baselineResult.scaleFactor,
      cachedResult.scaleFactor,
      '${baselineResult.timestamp} scaleFactor',
    );
    _expectCloseOrBothNull(
      baselineResult.finalScore,
      cachedResult.finalScore,
      '${baselineResult.timestamp} finalScore',
      tolerance: 1e-4,
    );
  }
}

void _expectCloseOrBothNull(
  double? a,
  double? b,
  String label, {
  double tolerance = 1e-6,
}) {
  if (a == null && b == null) return;
  expect(a, isNotNull, reason: '$label baseline is null');
  expect(b, isNotNull, reason: '$label cached is null');
  expect(a!, closeTo(b!, tolerance), reason: label);
}

void _printRoundComparison(_RoundComparison comparison) {
  debugPrint('');
  debugPrint(
    'Round ${comparison.round} '
    'order=${comparison.cachedFirst ? 'cached→baseline' : 'baseline→cached'}',
  );
  _printSummary(comparison.baseline);
  _printSummary(comparison.cached);
  debugPrint(
    '  speedup median=${comparison.medianSpeedupPct.toStringAsFixed(1)}% '
    'mean=${comparison.meanSpeedupPct.toStringAsFixed(1)}%',
  );
}

void _printSummary(_RunSummary summary) {
  debugPrint(
    '  ${summary.mode}: total=${summary.totalMs}ms '
    'mean=${summary.meanMs.toStringAsFixed(0)}ms/photo '
    'median=${summary.medianMs.toStringAsFixed(0)}ms/photo '
    'p95=${summary.p95Ms.toStringAsFixed(0)}ms/photo '
    'success=${summary.successCount}/${summary.results.length} '
    'faceHits=${summary.faceCacheHits} '
    'noFaceHits=${summary.noFacesSentinelHits} '
    'transformHits=${summary.transformCacheHits} '
    'transformMisses=${summary.transformCacheMisses} '
    'transformRenderFailures=${summary.transformCacheRenderFailures}',
  );
}

_AggregateComparison _aggregateComparisons(
  List<_RoundComparison> comparisons,
) {
  final baselineMedians = comparisons.map((c) => c.baseline.medianMs).toList();
  final cachedMedians = comparisons.map((c) => c.cached.medianMs).toList();
  final baselineMeans = comparisons.map((c) => c.baseline.meanMs).toList();
  final cachedMeans = comparisons.map((c) => c.cached.meanMs).toList();

  final baselineMedianOfMedians = _percentileDouble(baselineMedians, 50);
  final cachedMedianOfMedians = _percentileDouble(cachedMedians, 50);
  final baselineMeanOfMeans = _mean(baselineMeans);
  final cachedMeanOfMeans = _mean(cachedMeans);

  return _AggregateComparison(
    rounds: comparisons.length,
    baselineMedianOfMedians: baselineMedianOfMedians,
    cachedMedianOfMedians: cachedMedianOfMedians,
    baselineMeanOfMeans: baselineMeanOfMeans,
    cachedMeanOfMeans: cachedMeanOfMeans,
    medianSpeedupPct: _speedupPct(
      baselineMedianOfMedians,
      cachedMedianOfMedians,
    ),
    meanSpeedupPct: _speedupPct(baselineMeanOfMeans, cachedMeanOfMeans),
    cachedFaceHits: comparisons.fold(
      0,
      (sum, c) => sum + c.cached.faceCacheHits,
    ),
    cachedTransformHits: comparisons.fold(
      0,
      (sum, c) => sum + c.cached.transformCacheHits,
    ),
  );
}

void _printAggregate(_AggregateComparison aggregate) {
  debugPrint('');
  debugPrint('══════════════════════════════════════════════════════════');
  debugPrint(' FaceDetectionCache-only aggregate');
  debugPrint(' Rounds: ${aggregate.rounds}');
  debugPrint(
    ' Median of medians: baseline=${aggregate.baselineMedianOfMedians.toStringAsFixed(0)}ms/photo '
    'cached=${aggregate.cachedMedianOfMedians.toStringAsFixed(0)}ms/photo '
    'speedup=${aggregate.medianSpeedupPct.toStringAsFixed(1)}%',
  );
  debugPrint(
    ' Mean of means:     baseline=${aggregate.baselineMeanOfMeans.toStringAsFixed(0)}ms/photo '
    'cached=${aggregate.cachedMeanOfMeans.toStringAsFixed(0)}ms/photo '
    'speedup=${aggregate.meanSpeedupPct.toStringAsFixed(1)}%',
  );
  debugPrint(' Cached FaceDetectionCache hits: ${aggregate.cachedFaceHits}');
  debugPrint(' Cached TransformCache hits: ${aggregate.cachedTransformHits}');
  debugPrint('══════════════════════════════════════════════════════════');
  debugPrint('');
}

Future<void> _cleanupProject(int projectId) async {
  try {
    final projectDir = await DirUtils.getProjectDirPath(projectId);
    if (await Directory(projectDir).exists()) {
      await Directory(projectDir).delete(recursive: true);
    }
    await DB.instance.deleteProjectCascade(projectId);
  } catch (_) {}
}

double _speedupPct(double baseline, double cached) {
  if (baseline <= 0) return 0;
  return (baseline - cached) * 100 / baseline;
}

double _mean(List<double> values) {
  if (values.isEmpty) return 0;
  return values.reduce((a, b) => a + b) / values.length;
}

double _percentile(List<int> values, int percentile) {
  return _percentileDouble(
      values.map((v) => v.toDouble()).toList(), percentile);
}

double _percentileDouble(List<double> values, int percentile) {
  if (values.isEmpty) return 0;
  final sorted = List<double>.from(values)..sort();
  if (sorted.length == 1) return sorted.first;

  final position = (percentile / 100) * (sorted.length - 1);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];

  final fraction = position - lower;
  return sorted[lower] * (1 - fraction) + sorted[upper] * fraction;
}
