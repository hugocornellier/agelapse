import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/camera_page/camera_grid.dart';
import 'package:agelapse/screens/camera_page/grid_mode.dart';

/// Unit tests for CameraGridOverlay widget.
void main() {
  group('CameraGridOverlay', () {
    test('can be instantiated with required parameters', () {
      const widget = CameraGridOverlay(1, GridMode.none, 0.12, 0.35);
      expect(widget, isA<CameraGridOverlay>());
    });

    test('stores projectId correctly', () {
      const widget = CameraGridOverlay(42, GridMode.gridOnly, 0.1, 0.3);
      expect(widget.projectId, 42);
    });

    test('stores gridMode correctly', () {
      const widget = CameraGridOverlay(1, GridMode.ghostOnly, 0.1, 0.3);
      expect(widget.gridMode, GridMode.ghostOnly);
    });

    test('stores offsetX correctly', () {
      const widget = CameraGridOverlay(1, GridMode.none, 0.15, 0.3);
      expect(widget.offsetX, 0.15);
    });

    test('stores offsetY correctly', () {
      const widget = CameraGridOverlay(1, GridMode.none, 0.1, 0.45);
      expect(widget.offsetY, 0.45);
    });

    test('orientation defaults to null', () {
      const widget = CameraGridOverlay(1, GridMode.none, 0.1, 0.3);
      expect(widget.orientation, isNull);
    });

    test('accepts optional orientation', () {
      const widget = CameraGridOverlay(
        1,
        GridMode.none,
        0.1,
        0.3,
        orientation: 'portrait',
      );
      expect(widget.orientation, 'portrait');
    });

    test('creates state', () {
      const widget = CameraGridOverlay(1, GridMode.none, 0.1, 0.3);
      expect(widget.createState(), isA<CameraGridOverlayState>());
    });
  });
}
