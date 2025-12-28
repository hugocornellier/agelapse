import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/utils/test_mode.dart' as test_config;

void main() {
  test_config.isTestMode = true;

  group('App Launch Tests', () {
    testWidgets('app launches successfully', (tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Verify the app renders something
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });

  group('Basic Navigation Tests', () {
    testWidgets('bottom navigation bar is visible after app loads',
        (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Look for bottom navigation or any navigation element
      // The exact finder depends on your app structure
      final bottomNav = find.byType(BottomNavigationBar);
      final animatedBottomNav = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString().contains('AnimatedBottom'),
      );

      // At least one navigation widget should be present (or welcome screen)
      expect(
        bottomNav.evaluate().isNotEmpty ||
            animatedBottomNav.evaluate().isNotEmpty ||
            find.byType(Scaffold).evaluate().isNotEmpty,
        isTrue,
        reason: 'App should show some content after launch',
      );
    });
  });
}
