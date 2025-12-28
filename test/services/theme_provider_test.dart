import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/theme_provider.dart';
import 'package:agelapse/theme/theme.dart';

void main() {
  group('ThemeProvider', () {
    late ThemeProvider provider;
    late MaterialTheme materialTheme;

    setUp(() {
      materialTheme = const MaterialTheme(TextTheme());
      provider = ThemeProvider('light', materialTheme);
    });

    group('constructor', () {
      test('initializes with provided theme mode', () {
        final lightProvider = ThemeProvider('light', materialTheme);
        expect(lightProvider.themeMode, 'light');

        final darkProvider = ThemeProvider('dark', materialTheme);
        expect(darkProvider.themeMode, 'dark');

        final systemProvider = ThemeProvider('system', materialTheme);
        expect(systemProvider.themeMode, 'system');
      });
    });

    group('themeMode getter', () {
      test('returns current theme mode', () {
        expect(provider.themeMode, 'light');
      });
    });

    group('themeMode setter', () {
      test('updates theme mode', () {
        provider.themeMode = 'dark';
        expect(provider.themeMode, 'dark');
      });

      test('notifies listeners on change', () {
        var notificationCount = 0;
        provider.addListener(() => notificationCount++);

        provider.themeMode = 'dark';

        expect(notificationCount, 1);
      });

      test('notifies listeners even when setting same value', () {
        var notificationCount = 0;
        provider.addListener(() => notificationCount++);

        provider.themeMode = 'light'; // Same as initial

        // Current implementation notifies even for same value
        expect(notificationCount, 1);
      });

      test('notifies multiple listeners', () {
        var count1 = 0;
        var count2 = 0;
        provider.addListener(() => count1++);
        provider.addListener(() => count2++);

        provider.themeMode = 'dark';

        expect(count1, 1);
        expect(count2, 1);
      });
    });

    group('isLightMode', () {
      test('returns true for light mode', () {
        provider.themeMode = 'light';
        expect(provider.isLightMode, isTrue);
      });

      test('returns false for dark mode', () {
        provider.themeMode = 'dark';
        expect(provider.isLightMode, isFalse);
      });

      testWidgets('returns value based on platform brightness for system mode',
          (tester) async {
        provider.themeMode = 'system';

        // The actual value depends on platformDispatcher.platformBrightness
        // In test environment, we can access this safely after binding is initialized
        expect(() => provider.isLightMode, returnsNormally);
      });

      test('returns false for unknown mode', () {
        provider.themeMode = 'unknown';
        expect(provider.isLightMode, isFalse);
      });
    });

    group('themeData', () {
      test('returns light theme when isLightMode is true', () {
        provider.themeMode = 'light';
        final theme = provider.themeData;

        // MaterialTheme light() should be called
        expect(theme, isNotNull);
        expect(theme, isA<ThemeData>());
      });

      test('returns dark theme when isLightMode is false', () {
        provider.themeMode = 'dark';
        final theme = provider.themeData;

        expect(theme, isNotNull);
        expect(theme, isA<ThemeData>());
      });

      test('theme changes when mode changes', () {
        provider.themeMode = 'light';
        final lightTheme = provider.themeData;

        provider.themeMode = 'dark';
        final darkTheme = provider.themeData;

        // Light and dark themes should be different
        // (or at least the provider returns different instances)
        expect(lightTheme.brightness != darkTheme.brightness, isTrue);
      });
    });

    group('getActiveTheme static method', () {
      test('returns the same theme mode passed in', () {
        expect(ThemeProvider.getActiveTheme('light'), 'light');
        expect(ThemeProvider.getActiveTheme('dark'), 'dark');
        expect(ThemeProvider.getActiveTheme('system'), 'system');
      });

      test('returns any string passed', () {
        expect(ThemeProvider.getActiveTheme('custom'), 'custom');
        expect(ThemeProvider.getActiveTheme(''), '');
      });
    });

    group('ChangeNotifier behavior', () {
      test('can add and remove listeners', () {
        var called = false;
        void listener() => called = true;

        provider.addListener(listener);
        provider.themeMode = 'dark';
        expect(called, isTrue);

        called = false;
        provider.removeListener(listener);
        provider.themeMode = 'light';
        expect(called, isFalse);
      });

      test('listeners can be added and removed without error', () {
        void listener() {}
        provider.addListener(listener);
        provider.removeListener(listener);
        // No error thrown means listeners are working correctly
      });
    });

    group('integration scenarios', () {
      test('theme toggle cycle', () {
        final modes = <String>[];
        provider.addListener(() => modes.add(provider.themeMode));

        provider.themeMode = 'dark';
        provider.themeMode = 'light';
        provider.themeMode = 'system';
        provider.themeMode = 'dark';

        expect(modes, ['dark', 'light', 'system', 'dark']);
      });

      test('theme data matches mode', () {
        provider.themeMode = 'light';
        expect(provider.themeData.brightness, Brightness.light);

        provider.themeMode = 'dark';
        expect(provider.themeData.brightness, Brightness.dark);
      });
    });
  });
}
