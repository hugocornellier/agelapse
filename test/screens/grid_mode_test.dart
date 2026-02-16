import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/camera_page/grid_mode.dart';

/// Unit tests for GridMode enum.
void main() {
  group('GridMode', () {
    test('has four values', () {
      expect(GridMode.values.length, 4);
    });

    test('contains none', () {
      expect(GridMode.values, contains(GridMode.none));
    });

    test('contains ghostOnly', () {
      expect(GridMode.values, contains(GridMode.ghostOnly));
    });

    test('contains gridOnly', () {
      expect(GridMode.values, contains(GridMode.gridOnly));
    });

    test('contains doubleGhostGrid', () {
      expect(GridMode.values, contains(GridMode.doubleGhostGrid));
    });

    test('none has index 0', () {
      expect(GridMode.none.index, 0);
    });

    test('ghostOnly has index 1', () {
      expect(GridMode.ghostOnly.index, 1);
    });

    test('gridOnly has index 2', () {
      expect(GridMode.gridOnly.index, 2);
    });

    test('doubleGhostGrid has index 3', () {
      expect(GridMode.doubleGhostGrid.index, 3);
    });

    test('can be looked up by index', () {
      expect(GridMode.values[0], GridMode.none);
      expect(GridMode.values[1], GridMode.ghostOnly);
      expect(GridMode.values[2], GridMode.gridOnly);
      expect(GridMode.values[3], GridMode.doubleGhostGrid);
    });
  });
}
