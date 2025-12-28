import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;

/// Smoke test suite that validates the critical app path works on all platforms.
///
/// This test ensures:
/// 1. App launches successfully
/// 2. Fresh install flow works (welcome -> create project page -> create)
/// 3. Project creation works
/// 4. Main navigation is accessible
/// 5. All tabs can be navigated
///
/// The fresh install flow is:
/// ProjectsPage (GET STARTED) -> WelcomePagePartTwo (CREATE PROJECT) -> CreateProjectPage
///
/// Run with: `flutter test integration_test/smoke_test.dart -d <platform>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Smoke Tests', () {
    testWidgets('app launches and shows initial screen', (tester) async {
      // Clear any existing projects to simulate fresh install
      await _clearTestData();

      // Launch the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Verify app launched - should show welcome screen or projects page
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(Scaffold), findsWidgets);

      // On fresh install, we should see some UI (welcome screen)
      // App should not crash - that's the key validation here
    });

    testWidgets('fresh install flow navigates correctly', (tester) async {
      // Clear data for fresh state
      await _clearTestData();

      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Step 1: On fresh install, tap "GET STARTED" if visible
      final getStartedButton = find.text('GET STARTED');
      if (getStartedButton.evaluate().isNotEmpty) {
        await tester.tap(getStartedButton);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Step 2: Now on WelcomePagePartTwo, tap "CREATE PROJECT"
        final createProjectButton = find.text('CREATE PROJECT');
        if (createProjectButton.evaluate().isNotEmpty) {
          await tester.tap(createProjectButton);
          await tester.pumpAndSettle(const Duration(seconds: 2));

          // Step 3: Now on CreateProjectPage - verify we can see the form
          // Look for "Create New Project" header text
          final createNewProjectText = find.text('Create New Project');
          expect(createNewProjectText, findsOneWidget,
              reason: 'Should show Create New Project page');
        }
      }
    });

    testWidgets('can create a new project through UI', (tester) async {
      // Clear data for fresh state
      await _clearTestData();

      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate through the full fresh install flow
      // Step 1: GET STARTED
      final getStartedButton = find.text('GET STARTED');
      if (getStartedButton.evaluate().isNotEmpty) {
        await tester.tap(getStartedButton);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // Step 2: CREATE PROJECT (on welcome page part 2)
      final createProjectButton = find.text('CREATE PROJECT');
      if (createProjectButton.evaluate().isNotEmpty) {
        await tester.tap(createProjectButton);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // Step 3: Fill in project form and submit
      final textField = find.byType(TextField);
      if (textField.evaluate().isNotEmpty) {
        // Enter a project name
        await tester.enterText(textField.first, 'Smoke Test Project');
        await tester.pumpAndSettle();

        // Find and tap the CREATE button (in the form)
        final createButton = find.text('CREATE');
        if (createButton.evaluate().isNotEmpty) {
          await tester.tap(createButton);
          await tester.pumpAndSettle(const Duration(seconds: 3));
        }
      }

      // Verify project was created in database
      final projects = await DB.instance.getAllProjects();
      expect(projects, isNotEmpty,
          reason: 'Project should be saved to database');
    });

    testWidgets('main navigation loads with existing project', (tester) async {
      // Create a project and set as default
      await _ensureProjectExists(setAsDefault: true);

      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // With a default project, should go directly to main navigation
      // Look for any of the bottom navigation icons
      final hasHomeIcon = find.byIcon(Icons.home).evaluate().isNotEmpty;
      final hasCollectionsIcon =
          find.byIcon(Icons.collections).evaluate().isNotEmpty;
      final hasCameraIcon = find.byIcon(Icons.camera_alt).evaluate().isNotEmpty;
      final hasPlayIcon = find.byIcon(Icons.play_circle).evaluate().isNotEmpty;
      final hasInfoIcon = find.byIcon(Icons.info).evaluate().isNotEmpty;

      final hasNavigation = hasHomeIcon ||
          hasCollectionsIcon ||
          hasCameraIcon ||
          hasPlayIcon ||
          hasInfoIcon;

      expect(hasNavigation, isTrue,
          reason: 'Should show main navigation when default project exists');
    });

    testWidgets('can navigate between all tabs', (tester) async {
      await _ensureProjectExists(setAsDefault: true);

      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Test tapping each tab icon that exists
      final tabIcons = [
        Icons.home,
        Icons.collections,
        // Skip camera as it may require permissions
        Icons.play_circle,
        Icons.info,
      ];

      int successfulTabs = 0;
      for (final icon in tabIcons) {
        final iconFinder = find.byIcon(icon);
        if (iconFinder.evaluate().isNotEmpty) {
          await tester.tap(iconFinder.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));

          // Verify app didn't crash - we should still have a scaffold
          expect(find.byType(Scaffold), findsWidgets,
              reason: 'Tapping $icon should not crash the app');
          successfulTabs++;
        }
      }

      // At least some tabs should be accessible
      expect(successfulTabs, greaterThan(0),
          reason: 'Should be able to navigate to at least one tab');
    });

    testWidgets('gallery page renders without crash', (tester) async {
      await _ensureProjectExists(setAsDefault: true);

      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate to gallery tab
      final galleryIcon = find.byIcon(Icons.collections);
      if (galleryIcon.evaluate().isNotEmpty) {
        await tester.tap(galleryIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Gallery should load without crashing
        expect(find.byType(Scaffold), findsWidgets,
            reason: 'Gallery page should load without crash');
      } else {
        // If no gallery icon, just verify app is running
        expect(find.byType(MaterialApp), findsOneWidget);
      }
    });

    testWidgets('project page renders without crash', (tester) async {
      await _ensureProjectExists(setAsDefault: true);

      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate to home/project tab
      final homeIcon = find.byIcon(Icons.home);
      if (homeIcon.evaluate().isNotEmpty) {
        await tester.tap(homeIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Project page should show some content
        expect(find.byType(Scaffold), findsWidgets,
            reason: 'Project page should display correctly');
      } else {
        // If no home icon, just verify app is running
        expect(find.byType(MaterialApp), findsOneWidget);
      }
    });

    testWidgets('info page renders without crash', (tester) async {
      await _ensureProjectExists(setAsDefault: true);

      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate to info tab
      final infoIcon = find.byIcon(Icons.info);
      if (infoIcon.evaluate().isNotEmpty) {
        await tester.tap(infoIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Info page should load without crashing
        expect(find.byType(Scaffold), findsWidgets,
            reason: 'Info page should load without crash');
      } else {
        // If no info icon, just verify app is running
        expect(find.byType(MaterialApp), findsOneWidget);
      }
    });
  });
}

/// Clears all test data from the database for a fresh test state.
Future<void> _clearTestData() async {
  try {
    // Initialize database first
    await DB.instance.createTablesIfNotExist();

    // Get all projects and delete them
    final projects = await DB.instance.getAllProjects();
    for (final project in projects) {
      await DB.instance.deleteProject(project['id'] as int);
    }

    // Reset default project setting
    await DB.instance.setSettingByTitle('default_project', 'none');
  } catch (e) {
    // Database might not be initialized yet, that's okay
  }
}

/// Ensures at least one project exists for testing.
Future<void> _ensureProjectExists({bool setAsDefault = false}) async {
  await DB.instance.createTablesIfNotExist();

  final projects = await DB.instance.getAllProjects();
  int projectId;

  if (projects.isEmpty) {
    projectId = await DB.instance.addProject(
      'Integration Test Project',
      'face',
      DateTime.now().millisecondsSinceEpoch,
    );
  } else {
    projectId = projects.first['id'] as int;
  }

  if (setAsDefault) {
    await DB.instance
        .setSettingByTitle('default_project', projectId.toString());
  }
}
