import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/test_mode.dart';

/// Unit tests for test_mode.dart.
/// Tests the global isTestMode flag used to isolate test databases.
void main() {
  group('isTestMode', () {
    test('isTestMode is a boolean', () {
      expect(isTestMode, isA<bool>());
    });

    test('isTestMode defaults to false', () {
      expect(isTestMode, isFalse);
    });

    test('isTestMode can be set to true', () {
      final original = isTestMode;
      isTestMode = true;
      expect(isTestMode, isTrue);
      // Restore
      isTestMode = original;
    });

    test('isTestMode can be toggled back to false', () {
      final original = isTestMode;
      isTestMode = true;
      isTestMode = false;
      expect(isTestMode, isFalse);
      // Restore
      isTestMode = original;
    });
  });
}
