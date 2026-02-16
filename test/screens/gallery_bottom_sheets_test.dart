import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/gallery_page/gallery_bottom_sheets.dart';

/// Unit tests for GalleryBottomSheets.
void main() {
  group('GalleryBottomSheets', () {
    test('class can be referenced', () {
      expect(GalleryBottomSheets, isNotNull);
    });

    test('buildOptionsSheet is a static method', () {
      expect(GalleryBottomSheets.buildOptionsSheet, isA<Function>());
    });

    test('buildImportOptionTile is a static method', () {
      expect(GalleryBottomSheets.buildImportOptionTile, isA<Function>());
    });
  });
}
