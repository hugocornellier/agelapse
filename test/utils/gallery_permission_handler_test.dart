import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/gallery_permission_handler.dart';

/// Unit tests for GalleryPermissionHandler.
/// Tests the static API contract. Actual permission requests require
/// a real device/emulator and are covered by integration tests.
void main() {
  group('GalleryPermissionHandler', () {
    test('class can be referenced', () {
      expect(GalleryPermissionHandler, isNotNull);
    });

    test('requestGalleryPermissions is a static method', () {
      expect(
        GalleryPermissionHandler.requestGalleryPermissions,
        isA<Function>(),
      );
    });

    test('hasGalleryPermissions is a static method', () {
      expect(
        GalleryPermissionHandler.hasGalleryPermissions,
        isA<Function>(),
      );
    });

    test('requestGalleryPermissions returns Future<bool>', () {
      // On desktop (macOS), desktop platforms return true immediately
      final result = GalleryPermissionHandler.requestGalleryPermissions();
      expect(result, isA<Future<bool>>());
    });

    test('requestGalleryPermissions returns true on desktop', () async {
      // Desktop platforms don't need special permissions
      final result = await GalleryPermissionHandler.requestGalleryPermissions();
      expect(result, isTrue);
    });
  });
}
