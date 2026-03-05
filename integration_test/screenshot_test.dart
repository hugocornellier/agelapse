// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as path;

/// Screenshot test suite for generating documentation screenshots.
///
/// Run with: `flutter test integration_test/screenshot_test.dart -d macos`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  // Directory to save screenshots — use env var or temp dir for CI
  final screenshotDir = Platform.environment['SCREENSHOT_DIR'] ??
      '${Directory.systemTemp.path}/agelapse_screenshots';

  group('Documentation Screenshots', () {
    setUpAll(() async {
      initDatabase();

      // Create screenshot directory if it doesn't exist
      final dir = Directory(screenshotDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      print('Screenshot directory: $screenshotDir');

      // Initialize database and set dark theme BEFORE app launches
      await DB.instance.createTablesIfNotExist();
      await DB.instance.setSettingByTitle('theme', 'dark', 'global');
      print('Dark theme set in database.');
    });

    testWidgets('screenshot: main project page', (tester) async {
      print('Starting screenshot test...');

      // Create a test project and set as default
      final projectId = await _ensureProjectExists(
        projectName: 'My Timelapse',
        setAsDefault: true,
      );
      print('Created project with ID: $projectId');

      // Launch the app
      app.main();
      print('App launched, waiting for initialization...');

      // Use pump with fixed duration instead of pumpAndSettle
      // (pumpAndSettle hangs if there are continuous animations)
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      print('Initial pump complete.');

      // Try to settle but with a timeout
      try {
        await tester.pumpAndSettle(const Duration(seconds: 3));
      } catch (e) {
        print('pumpAndSettle timed out or errored: $e');
        // Continue anyway
        await tester.pump(const Duration(seconds: 1));
      }
      print('App should be loaded now.');

      // Navigate to home tab if visible
      final homeIcon = find.byIcon(Icons.home);
      if (homeIcon.evaluate().isNotEmpty) {
        print('Found home icon, tapping...');
        await tester.tap(homeIcon.first);
        await tester.pump(const Duration(seconds: 2));
      } else {
        print('Home icon not found, continuing anyway.');
      }

      // Take screenshot
      print('Taking screenshot...');
      final success = await _takeScreenshotFromWidget(
        tester,
        screenshotDir,
        'project_page',
      );

      if (success) {
        print('SUCCESS: Screenshot saved to $screenshotDir/project_page.png');
      } else {
        print('FAILED: Could not take screenshot');
      }

      // Verify screenshot file exists
      final screenshotFile = File(path.join(screenshotDir, 'project_page.png'));
      expect(
        await screenshotFile.exists(),
        isTrue,
        reason: 'Screenshot file should exist',
      );
    });
  });
}

/// Takes a screenshot by finding the root RenderRepaintBoundary and capturing it.
/// Returns true if successful, false otherwise.
Future<bool> _takeScreenshotFromWidget(
  WidgetTester tester,
  String directory,
  String name,
) async {
  // Get the render view
  final RenderView renderView = tester.binding.renderViews.first;

  // Get the layer
  // ignore: invalid_use_of_protected_member
  final OffsetLayer layer = renderView.layer! as OffsetLayer;

  try {
    // Get the bounds
    final bounds = renderView.size;
    print('Render view size: ${bounds.width}x${bounds.height}');

    // Create image from layer
    final ui.Image image = await layer.toImage(
      Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      pixelRatio: 2.0,
    );
    print('Image captured: ${image.width}x${image.height}');

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      print('ERROR: Could not convert image to bytes');
      return false;
    }

    // Save to file
    final filePath = path.join(directory, '$name.png');
    final file = File(filePath);
    await file.writeAsBytes(byteData.buffer.asUint8List());

    final fileSize = await file.length();
    print('Screenshot saved: $filePath ($fileSize bytes)');
    return true;
  } catch (e, stack) {
    print('ERROR taking screenshot: $e');
    print('Stack trace: $stack');
    return false;
  }
}

/// Clears all test data from the database for a fresh test state.
Future<void> _clearTestData() async {
  try {
    await DB.instance.createTablesIfNotExist();

    final projects = await DB.instance.getAllProjects();
    for (final project in projects) {
      await DB.instance.deleteProject(project['id'] as int);
    }

    await DB.instance.setSettingByTitle('default_project', 'none');
  } catch (e) {
    print('Error clearing test data: $e');
  }
}

/// Ensures a project exists for testing.
Future<int> _ensureProjectExists({
  String projectName = 'Screenshot Test Project',
  bool setAsDefault = false,
}) async {
  await DB.instance.createTablesIfNotExist();
  await _clearTestData();

  final projectId = await DB.instance.addProject(
    projectName,
    'face',
    DateTime.now().millisecondsSinceEpoch,
  );

  if (setAsDefault) {
    await DB.instance.setSettingByTitle(
      'default_project',
      projectId.toString(),
    );
  }

  return projectId;
}
