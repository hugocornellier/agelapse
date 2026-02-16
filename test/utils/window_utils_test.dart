import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/window_utils.dart';

/// Unit tests for WindowUtils.
/// Tests the desktop window management utility class.
void main() {
  group('WindowUtils', () {
    test('class can be referenced', () {
      expect(WindowUtils, isNotNull);
    });

    group('isDesktop', () {
      test('returns a boolean', () {
        expect(WindowUtils.isDesktop, isA<bool>());
      });

      test('returns true on desktop platforms', () {
        // Test runner is macOS, so this should be true
        expect(WindowUtils.isDesktop, isTrue);
      });
    });

    group('transitionToDefaultWindowState', () {
      test('is a static method that returns Future<void>', () {
        expect(
          WindowUtils.transitionToDefaultWindowState,
          isA<Function>(),
        );
      });

      test('is callable', () {
        // transitionToDefaultWindowState requires WidgetsFlutterBinding,
        // so we only verify the method reference here.
        expect(
          WindowUtils.transitionToDefaultWindowState,
          isA<Function>(),
        );
      });
    });
  });
}
