import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
      throw Exception('Asset not found. Tried paths: ${pathsToTry.join(", ")}. '
          'Ensure assets are declared in pubspec.yaml under flutter > assets');
    }

    final tempDir = await getTemporaryDirectory();
    final tempFile =
        File(p.join(tempDir.path, 'test_fixtures', normalizedPath));

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
        'Sync access is only available after async extraction.');
  }
  return p.join(getProjectRoot(), 'assets', 'test_fixtures', relativePath);
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
    'sample-avif.avif',
    'sample-heic.HEIC',
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
