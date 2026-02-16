import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/gallery_page/gallery_image_menu.dart';

/// Unit tests for GalleryImageMenu.
void main() {
  group('GalleryImageMenu', () {
    test('class can be referenced', () {
      expect(GalleryImageMenu, isNotNull);
    });

    test('show is a static method', () {
      expect(GalleryImageMenu.show, isA<Function>());
    });
  });
}
