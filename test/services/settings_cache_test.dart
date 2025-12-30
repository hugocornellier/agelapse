import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/settings_cache.dart';

/// Unit tests for SettingsCache.
/// Tests constructor, fields, and default values.
void main() {
  group('SettingsCache Constructor', () {
    test('SettingsCache can be instantiated with all required parameters', () {
      final cache = SettingsCache(
        hasOpenedNonEmptyGallery: false,
        isLightTheme: true,
        noPhotos: true,
        hasViewedFirstVideo: false,
        hasOpenedNotifications: false,
        hasTakenMoreThanOnePhoto: false,
        hasSeenGuideModeTut: false,
        hasTakenFirstPhoto: false,
        streak: 0,
        photoCount: 0,
        firstPhotoDate: '',
        lastPhotoDate: '',
        lengthInDays: 0,
        projectOrientation: 'portrait',
        aspectRatio: '9:16',
        resolution: '1080p',
        watermarkEnabled: false,
        stabilizationMode: 'auto',
        image: null,
        eyeOffsetX: 0.5,
        eyeOffsetY: 0.5,
      );

      expect(cache, isNotNull);
      expect(cache, isA<SettingsCache>());
    });

    test('SettingsCache stores boolean fields correctly', () {
      final cache = SettingsCache(
        hasOpenedNonEmptyGallery: true,
        isLightTheme: false,
        noPhotos: false,
        hasViewedFirstVideo: true,
        hasOpenedNotifications: true,
        hasTakenMoreThanOnePhoto: true,
        hasSeenGuideModeTut: true,
        hasTakenFirstPhoto: true,
        streak: 5,
        photoCount: 10,
        firstPhotoDate: '2024-01-01',
        lastPhotoDate: '2024-12-01',
        lengthInDays: 335,
        projectOrientation: 'landscape',
        aspectRatio: '16:9',
        resolution: '4K',
        watermarkEnabled: true,
        stabilizationMode: 'manual',
        image: null,
        eyeOffsetX: 0.3,
        eyeOffsetY: 0.4,
      );

      expect(cache.hasOpenedNonEmptyGallery, isTrue);
      expect(cache.isLightTheme, isFalse);
      expect(cache.noPhotos, isFalse);
      expect(cache.hasViewedFirstVideo, isTrue);
      expect(cache.hasOpenedNotifications, isTrue);
      expect(cache.hasTakenMoreThanOnePhoto, isTrue);
      expect(cache.hasSeenGuideModeTut, isTrue);
      expect(cache.hasTakenFirstPhoto, isTrue);
      expect(cache.watermarkEnabled, isTrue);
    });

    test('SettingsCache stores numeric fields correctly', () {
      final cache = SettingsCache(
        hasOpenedNonEmptyGallery: false,
        isLightTheme: null,
        noPhotos: true,
        hasViewedFirstVideo: false,
        hasOpenedNotifications: false,
        hasTakenMoreThanOnePhoto: false,
        hasSeenGuideModeTut: false,
        hasTakenFirstPhoto: false,
        streak: 7,
        photoCount: 100,
        firstPhotoDate: '',
        lastPhotoDate: '',
        lengthInDays: 365,
        projectOrientation: 'portrait',
        aspectRatio: '9:16',
        resolution: '1080p',
        watermarkEnabled: false,
        stabilizationMode: 'auto',
        image: null,
        eyeOffsetX: 0.123,
        eyeOffsetY: 0.456,
      );

      expect(cache.streak, 7);
      expect(cache.photoCount, 100);
      expect(cache.lengthInDays, 365);
      expect(cache.eyeOffsetX, 0.123);
      expect(cache.eyeOffsetY, 0.456);
    });

    test('SettingsCache stores string fields correctly', () {
      final cache = SettingsCache(
        hasOpenedNonEmptyGallery: false,
        isLightTheme: null,
        noPhotos: true,
        hasViewedFirstVideo: false,
        hasOpenedNotifications: false,
        hasTakenMoreThanOnePhoto: false,
        hasSeenGuideModeTut: false,
        hasTakenFirstPhoto: false,
        streak: 0,
        photoCount: 0,
        firstPhotoDate: '2024-01-15',
        lastPhotoDate: '2024-12-31',
        lengthInDays: 0,
        projectOrientation: 'square',
        aspectRatio: '1:1',
        resolution: '720p',
        watermarkEnabled: false,
        stabilizationMode: 'none',
        image: null,
        eyeOffsetX: 0.5,
        eyeOffsetY: 0.5,
      );

      expect(cache.firstPhotoDate, '2024-01-15');
      expect(cache.lastPhotoDate, '2024-12-31');
      expect(cache.projectOrientation, 'square');
      expect(cache.aspectRatio, '1:1');
      expect(cache.resolution, '720p');
      expect(cache.stabilizationMode, 'none');
    });

    test('SettingsCache allows nullable isLightTheme', () {
      final cache = SettingsCache(
        hasOpenedNonEmptyGallery: false,
        isLightTheme: null,
        noPhotos: true,
        hasViewedFirstVideo: false,
        hasOpenedNotifications: false,
        hasTakenMoreThanOnePhoto: false,
        hasSeenGuideModeTut: false,
        hasTakenFirstPhoto: false,
        streak: 0,
        photoCount: 0,
        firstPhotoDate: '',
        lastPhotoDate: '',
        lengthInDays: 0,
        projectOrientation: 'portrait',
        aspectRatio: '9:16',
        resolution: '1080p',
        watermarkEnabled: false,
        stabilizationMode: 'auto',
        image: null,
        eyeOffsetX: 0.5,
        eyeOffsetY: 0.5,
      );

      expect(cache.isLightTheme, isNull);
    });
  });

  group('SettingsCache Dispose', () {
    test('dispose method exists', () {
      final cache = SettingsCache(
        hasOpenedNonEmptyGallery: false,
        isLightTheme: null,
        noPhotos: true,
        hasViewedFirstVideo: false,
        hasOpenedNotifications: false,
        hasTakenMoreThanOnePhoto: false,
        hasSeenGuideModeTut: false,
        hasTakenFirstPhoto: false,
        streak: 0,
        photoCount: 0,
        firstPhotoDate: '',
        lastPhotoDate: '',
        lengthInDays: 0,
        projectOrientation: 'portrait',
        aspectRatio: '9:16',
        resolution: '1080p',
        watermarkEnabled: false,
        stabilizationMode: 'auto',
        image: null,
        eyeOffsetX: 0.5,
        eyeOffsetY: 0.5,
      );

      // dispose should not throw when image is null
      expect(() => cache.dispose(), returnsNormally);
    });

    test('dispose sets image to null', () {
      final cache = SettingsCache(
        hasOpenedNonEmptyGallery: false,
        isLightTheme: null,
        noPhotos: true,
        hasViewedFirstVideo: false,
        hasOpenedNotifications: false,
        hasTakenMoreThanOnePhoto: false,
        hasSeenGuideModeTut: false,
        hasTakenFirstPhoto: false,
        streak: 0,
        photoCount: 0,
        firstPhotoDate: '',
        lastPhotoDate: '',
        lengthInDays: 0,
        projectOrientation: 'portrait',
        aspectRatio: '9:16',
        resolution: '1080p',
        watermarkEnabled: false,
        stabilizationMode: 'auto',
        image: null,
        eyeOffsetX: 0.5,
        eyeOffsetY: 0.5,
      );

      cache.dispose();
      expect(cache.image, isNull);
    });
  });

  group('SettingsCache Static Methods', () {
    test('initialize static method exists', () {
      expect(SettingsCache.initialize, isA<Function>());
    });

    test('initializeWithDefaults static method exists', () {
      expect(SettingsCache.initializeWithDefaults, isA<Function>());
    });
  });

  group('SettingsCache Edge Cases', () {
    test('handles zero streak', () {
      final cache = SettingsCache(
        hasOpenedNonEmptyGallery: false,
        isLightTheme: null,
        noPhotos: true,
        hasViewedFirstVideo: false,
        hasOpenedNotifications: false,
        hasTakenMoreThanOnePhoto: false,
        hasSeenGuideModeTut: false,
        hasTakenFirstPhoto: false,
        streak: 0,
        photoCount: 0,
        firstPhotoDate: '',
        lastPhotoDate: '',
        lengthInDays: 0,
        projectOrientation: 'portrait',
        aspectRatio: '9:16',
        resolution: '1080p',
        watermarkEnabled: false,
        stabilizationMode: 'auto',
        image: null,
        eyeOffsetX: 0.5,
        eyeOffsetY: 0.5,
      );

      expect(cache.streak, 0);
      expect(cache.noPhotos, isTrue);
    });

    test('handles large streak value', () {
      final cache = SettingsCache(
        hasOpenedNonEmptyGallery: false,
        isLightTheme: null,
        noPhotos: false,
        hasViewedFirstVideo: false,
        hasOpenedNotifications: false,
        hasTakenMoreThanOnePhoto: true,
        hasSeenGuideModeTut: false,
        hasTakenFirstPhoto: true,
        streak: 365,
        photoCount: 1000,
        firstPhotoDate: '',
        lastPhotoDate: '',
        lengthInDays: 365,
        projectOrientation: 'portrait',
        aspectRatio: '9:16',
        resolution: '1080p',
        watermarkEnabled: false,
        stabilizationMode: 'auto',
        image: null,
        eyeOffsetX: 0.5,
        eyeOffsetY: 0.5,
      );

      expect(cache.streak, 365);
      expect(cache.photoCount, 1000);
    });

    test('handles empty date strings', () {
      final cache = SettingsCache(
        hasOpenedNonEmptyGallery: false,
        isLightTheme: null,
        noPhotos: true,
        hasViewedFirstVideo: false,
        hasOpenedNotifications: false,
        hasTakenMoreThanOnePhoto: false,
        hasSeenGuideModeTut: false,
        hasTakenFirstPhoto: false,
        streak: 0,
        photoCount: 0,
        firstPhotoDate: '',
        lastPhotoDate: '',
        lengthInDays: 0,
        projectOrientation: 'portrait',
        aspectRatio: '9:16',
        resolution: '1080p',
        watermarkEnabled: false,
        stabilizationMode: 'auto',
        image: null,
        eyeOffsetX: 0.5,
        eyeOffsetY: 0.5,
      );

      expect(cache.firstPhotoDate, isEmpty);
      expect(cache.lastPhotoDate, isEmpty);
    });

    test('handles negative eyeOffset values', () {
      final cache = SettingsCache(
        hasOpenedNonEmptyGallery: false,
        isLightTheme: null,
        noPhotos: true,
        hasViewedFirstVideo: false,
        hasOpenedNotifications: false,
        hasTakenMoreThanOnePhoto: false,
        hasSeenGuideModeTut: false,
        hasTakenFirstPhoto: false,
        streak: 0,
        photoCount: 0,
        firstPhotoDate: '',
        lastPhotoDate: '',
        lengthInDays: 0,
        projectOrientation: 'portrait',
        aspectRatio: '9:16',
        resolution: '1080p',
        watermarkEnabled: false,
        stabilizationMode: 'auto',
        image: null,
        eyeOffsetX: -0.5,
        eyeOffsetY: -0.3,
      );

      expect(cache.eyeOffsetX, -0.5);
      expect(cache.eyeOffsetY, -0.3);
    });
  });
}
