import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Waits for the app to be fully ready after [app.main()] is called.
///
/// Two-phase:
///   1. Poll every 500 ms until a [Scaffold] appears (runApp has fired).
///      On warm runners this takes ~3-5 s; on cold/loaded CI runners up to ~8 s.
///      A fixed pump was the cause of recurring cold-cache Windows/Linux/macOS
///      flakes.
///   2. Try to settle the tree so that navigation widgets and buttons are fully
///      rendered before the test proceeds.  Uses a 5 s timeout so it does not
///      hang on the FlashingBox animation (which keeps the tree permanently
///      dirty); if it times out the exception is caught and we fall back to two
///      short fixed pumps.
Future<void> pumpUntilAppReady(
  WidgetTester tester, {
  int maxSeconds = 15,
}) async {
  // Phase 1: wait until runApp has been called.
  for (int i = 0; i < maxSeconds * 2; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (find.byType(Scaffold).evaluate().isNotEmpty) break;
  }

  // Phase 2: settle so that content (buttons, nav icons) finishes rendering.
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
  } catch (_) {
    // Continuous animation (e.g. FlashingBox) kept the tree dirty — pump a
    // couple more frames and move on.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Cache for extracted fixture files on mobile platforms
final Map<String, String> _fixtureCache = {};

/// Tracks if fixtures failed to load on mobile (skip tests gracefully)
bool _fixturesFailedToLoad = false;
String _fixtureLoadError = '';

/// Returns true if fixtures failed to load (tests should be skipped)
bool get fixturesUnavailable => _fixturesFailedToLoad;
String get fixtureLoadError => _fixtureLoadError;

/// Returns true if running on a mobile platform (iOS/Android)
bool get _isMobile => Platform.isIOS || Platform.isAndroid;

/// Returns the project root directory.
/// When running via `flutter test`, the current working directory is the project root.
/// On mobile, this returns an empty string as we use assets instead.
String getProjectRoot() {
  if (_isMobile) {
    return '';
  }
  return Directory.current.path;
}

/// Returns the absolute path to a fixture file.
/// [relativePath] is relative to assets/test_fixtures/
/// On mobile platforms, this extracts the asset to a temp file and returns its path.
Future<String> getFixturePathAsync(String relativePath) async {
  // Normalize path separators to forward slashes
  final normalizedPath = relativePath.replaceAll('\\', '/');
  final assetPath = 'assets/test_fixtures/$normalizedPath';

  if (_isMobile) {
    // Check cache first
    if (_fixtureCache.containsKey(assetPath)) {
      final cachedPath = _fixtureCache[assetPath]!;
      if (await File(cachedPath).exists()) {
        return cachedPath;
      }
    }

    // Load from assets and write to temp file
    // Try multiple path formats for iOS/Android compatibility
    final pathsToTry = [
      assetPath,
      'packages/agelapse/$assetPath',
      normalizedPath,
    ];

    ByteData? byteData;

    for (final tryPath in pathsToTry) {
      try {
        byteData = await rootBundle.load(tryPath);
        break;
      } catch (_) {
        continue;
      }
    }

    if (byteData == null) {
      throw Exception(
        'Asset not found. Tried paths: ${pathsToTry.join(", ")}. '
        'Ensure assets are declared in pubspec.yaml under flutter > assets',
      );
    }

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      p.join(tempDir.path, 'test_fixtures', normalizedPath),
    );

    // Create parent directories if needed
    await tempFile.parent.create(recursive: true);

    // Write the asset to the temp file
    await tempFile.writeAsBytes(byteData.buffer.asUint8List());

    // Verify file was written successfully
    if (!await tempFile.exists()) {
      throw Exception('Failed to write fixture file: ${tempFile.path}');
    }

    // Cache the path
    _fixtureCache[assetPath] = tempFile.path;

    return tempFile.path;
  } else {
    // On desktop, use filesystem directly
    return p.join(getProjectRoot(), assetPath);
  }
}

/// Synchronous version for backwards compatibility on desktop.
/// On mobile, this will throw - use getFixturePathAsync instead.
String getFixturePath(String relativePath) {
  if (_isMobile) {
    // Check if we have a cached path
    final assetPath = p.join('assets', 'test_fixtures', relativePath);
    if (_fixtureCache.containsKey(assetPath)) {
      return _fixtureCache[assetPath]!;
    }
    throw StateError(
      'On mobile platforms, call getFixturePathAsync() first to extract the asset. '
      'Sync access is only available after async extraction.',
    );
  }
  return p.join(getProjectRoot(), 'assets', 'test_fixtures', relativePath);
}

/// Supported format sample names for format_samples/ fixture directories.
const formatSampleFormats = [
  'jpg',
  'png',
  'webp',
  'bmp',
  'tiff',
  'heic',
  'avif',
  'jp2',
];

/// File extensions for each format sample directory.
const formatSampleExtensions = {
  'jpg': 'jpg',
  'png': 'png',
  'webp': 'webp',
  'bmp': 'bmp',
  'tiff': 'tiff',
  'heic': 'heic',
  'avif': 'avif',
  'jp2': 'jp2',
};

/// Sample day numbers available in format_samples/.
const formatSampleDays = ['day1', 'day11', 'day12'];

/// Returns the path to a format sample image.
/// [format] is one of: jpg, png, webp, bmp, tiff, gif, heic, avif, jp2
/// [day] is one of: 'day1', 'day11', 'day12'
Future<String> getFormatSamplePathAsync(String format, String day) async {
  final ext = formatSampleExtensions[format] ?? format;
  return getFixturePathAsync(p.join('format_samples', format, '$day.$ext'));
}

/// Synchronous version for backwards compatibility on desktop.
String getFormatSamplePath(String format, String day) {
  final ext = formatSampleExtensions[format] ?? format;
  return getFixturePath(p.join('format_samples', format, '$day.$ext'));
}

/// Returns the path to a sample face image by day number (1, 2, or 3).
/// On mobile platforms, this extracts the asset to a temp file first.
Future<String> getSampleFacePathAsync(int day) async {
  return getFixturePathAsync(p.join('sample_faces', 'day$day.jpg'));
}

/// Synchronous version for backwards compatibility.
/// On mobile, call getSampleFacePathAsync first.
String getSampleFacePath(int day) {
  return getFixturePath(p.join('sample_faces', 'day$day.jpg'));
}

/// Returns the path to a sample dog image by day number (1, 2, or 3).
/// On mobile platforms, this extracts the asset to a temp file first.
Future<String> getSampleDogPathAsync(int day) async {
  return getFixturePathAsync(p.join('sample_dogs', 'day$day.jpg'));
}

/// Synchronous version for backwards compatibility.
/// On mobile, call getSampleDogPathAsync first.
String getSampleDogPath(int day) {
  return getFixturePath(p.join('sample_dogs', 'day$day.jpg'));
}

/// Returns the path to a sample cat image by day number (1-4).
/// On mobile platforms, this extracts the asset to a temp file first.
Future<String> getSampleCatPathAsync(int day) async {
  return getFixturePathAsync(p.join('sample_cats', 'day$day.jpg'));
}

/// Synchronous version for backwards compatibility.
/// On mobile, call getSampleCatPathAsync first.
String getSampleCatPath(int day) {
  return getFixturePath(p.join('sample_cats', 'day$day.jpg'));
}

/// Returns the path to a sample pose image by filename.
/// Valid filenames: pregnancy1.jpg, pregnancy2.jpg, muscle1.jpg, muscle2.jpg, two_people.jpeg
/// On mobile platforms, this extracts the asset to a temp file first.
Future<String> getSamplePosePathAsync(String filename) async {
  return getFixturePathAsync(p.join('sample_poses', filename));
}

/// Synchronous version for backwards compatibility.
/// On mobile, call getSamplePosePathAsync first.
String getSamplePosePath(String filename) {
  return getFixturePath(p.join('sample_poses', filename));
}

/// Returns the absolute path to a sample file for testing.
/// [filename] is the name of the file in samples_for_testing/
String getSampleForTestingPath(String filename) {
  return p.join(getProjectRoot(), 'samples_for_testing', filename);
}

/// Preloads all fixture files on mobile platforms.
/// Call this in setUpAll() for tests that use fixtures.
/// On failure, sets [fixturesUnavailable] to true so tests can be skipped.
Future<void> preloadFixtures() async {
  _fixturesFailedToLoad = false;
  _fixtureLoadError = '';

  if (!_isMobile) return;

  // Preload all known fixtures
  final fixtures = [
    'sample_faces/day1.jpg',
    'sample_faces/day2.jpg',
    'sample_faces/day3.jpg',
    'sample_dogs/day1.jpg',
    'sample_dogs/day2.jpg',
    'sample_dogs/day3.jpg',
    'sample_cats/day1.jpg',
    'sample_cats/day2.jpg',
    'sample_cats/day3.jpg',
    'sample_cats/day4.jpg',
    'sample_poses/pregnancy1.jpg',
    'sample_poses/pregnancy2.jpg',
    'sample_poses/muscle1.jpg',
    'sample_poses/muscle2.jpg',
    'sample_poses/two_people.jpeg',
    'sample-avif.avif',
    'sample-heic.HEIC',
    // Format samples for comprehensive format testing
    for (final fmt in formatSampleFormats)
      for (final day in formatSampleDays)
        'format_samples/$fmt/$day.${formatSampleExtensions[fmt]}',
  ];

  final errors = <String>[];

  for (final fixture in fixtures) {
    try {
      await getFixturePathAsync(fixture);
    } catch (e) {
      errors.add('$fixture: $e');
    }
  }

  if (errors.isNotEmpty) {
    _fixturesFailedToLoad = true;
    _fixtureLoadError =
        'Failed to preload fixtures on mobile:\n${errors.join('\n')}\n\n'
        'Ensure fixtures are declared in pubspec.yaml under flutter > assets';
    // Don't throw - let tests handle this gracefully
  }
}

/// Cleans up extracted fixture files.
/// Call this in tearDownAll() if needed.
Future<void> cleanupFixtures() async {
  if (!_isMobile) return;

  final tempDir = await getTemporaryDirectory();
  final fixturesDir = Directory(p.join(tempDir.path, 'test_fixtures'));

  if (await fixturesDir.exists()) {
    await fixturesDir.delete(recursive: true);
  }

  _fixtureCache.clear();
}
