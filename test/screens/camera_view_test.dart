import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/camera_page/camera_view.dart';

/// Unit tests for camera_view.dart.
/// Tests the getRotation helper and RotatingIconButton widget.
void main() {
  group('getRotation', () {
    test('returns 0.25 for Landscape Left', () {
      expect(getRotation('Landscape Left'), 0.25);
    });

    test('returns -0.25 for Landscape Right', () {
      expect(getRotation('Landscape Right'), -0.25);
    });

    test('returns 0.0 for Portrait', () {
      expect(getRotation('Portrait'), 0.0);
    });

    test('returns 0.0 for empty string', () {
      expect(getRotation(''), 0.0);
    });

    test('returns 0.0 for unknown orientation', () {
      expect(getRotation('Unknown'), 0.0);
    });
  });

  group('RotatingIconButton', () {
    test('can be referenced', () {
      expect(RotatingIconButton, isNotNull);
    });
  });
}
