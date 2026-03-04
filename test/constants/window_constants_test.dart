import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/constants/window_constants.dart';

/// Unit tests for window_constants.dart.
void main() {
  group('Window Size Constants', () {
    test('kWindowSizeDefault is 1440x910', () {
      expect(kWindowSizeDefault, const Size(1440, 910));
    });

    test('kWindowSizeWelcome is 840x820', () {
      expect(kWindowSizeWelcome, const Size(840, 820));
    });

    test('kWindowMinSizeDefault is 840x450', () {
      expect(kWindowMinSizeDefault, const Size(840, 450));
    });

    test('kWindowMinSizeWelcome is 840x820', () {
      expect(kWindowMinSizeWelcome, const Size(840, 820));
    });

    test('default size is larger than welcome size in width', () {
      expect(kWindowSizeDefault.width, greaterThan(kWindowSizeWelcome.width));
    });

    test('default size is larger than its minimum', () {
      expect(
        kWindowSizeDefault.width,
        greaterThanOrEqualTo(kWindowMinSizeDefault.width),
      );
      expect(
        kWindowSizeDefault.height,
        greaterThanOrEqualTo(kWindowMinSizeDefault.height),
      );
    });

    test('welcome size meets its minimum', () {
      expect(
        kWindowSizeWelcome.width,
        greaterThanOrEqualTo(kWindowMinSizeWelcome.width),
      );
      expect(
        kWindowSizeWelcome.height,
        greaterThanOrEqualTo(kWindowMinSizeWelcome.height),
      );
    });
  });
}
