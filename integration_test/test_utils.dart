import 'dart:io';
import 'package:path/path.dart' as p;

/// Returns the project root directory.
/// When running via `flutter test`, the current working directory is the project root.
String getProjectRoot() {
  return Directory.current.path;
}

/// Returns the absolute path to a fixture file.
/// [relativePath] is relative to integration_test/fixtures/
String getFixturePath(String relativePath) {
  return p.join(getProjectRoot(), 'integration_test', 'fixtures', relativePath);
}

/// Returns the path to a sample face image by day number (1, 2, or 3).
String getSampleFacePath(int day) {
  return getFixturePath(p.join('sample_faces', 'day$day.jpg'));
}

/// Returns the absolute path to a sample file for testing.
/// [filename] is the name of the file in samples_for_testing/
String getSampleForTestingPath(String filename) {
  return p.join(getProjectRoot(), 'samples_for_testing', filename);
}
