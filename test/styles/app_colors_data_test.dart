import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/styles/app_colors_data.dart';

/// Unit tests for PhotoOverlayColors, AppColorsData, and AppColorsContext.
void main() {
  group('PhotoOverlayColors', () {
    test('text is white', () {
      expect(PhotoOverlayColors.text, const Color(0xFFFFFFFF));
    });

    test('textShadow is black at 54%', () {
      expect(PhotoOverlayColors.textShadow, const Color(0x8A000000));
    });

    test('textShadowLight is black at 40%', () {
      expect(PhotoOverlayColors.textShadowLight, const Color(0x66000000));
    });

    test('textShadowLighter is black at 25%', () {
      expect(PhotoOverlayColors.textShadowLighter, const Color(0x40000000));
    });

    test('cameraGuide is white at 50%', () {
      expect(PhotoOverlayColors.cameraGuide, const Color(0x80FFFFFF));
    });

    test('ghostImage is white at 95%', () {
      expect(PhotoOverlayColors.ghostImage, const Color(0xF2FFFFFF));
    });

    test('textBackground is black at 50%', () {
      expect(PhotoOverlayColors.textBackground, const Color(0x80000000));
    });
  });

  group('AppColorsData', () {
    test('can be instantiated with all required parameters', () {
      final colors = AppColorsData(
        background: Colors.white,
        backgroundDark: Colors.grey,
        surface: Colors.grey.shade100,
        surfaceElevated: Colors.grey.shade200,
        textPrimary: Colors.black,
        textSecondary: Colors.grey,
        textTertiary: Colors.grey.shade400,
        danger: Colors.red,
        success: Colors.green,
        warning: Colors.orange,
        warningMuted: Colors.brown,
        info: Colors.blue,
        accentLight: Colors.lightBlue,
        accent: Colors.blue,
        accentDark: Colors.blue.shade800,
        accentDarker: Colors.blue.shade900,
        overlay: Colors.black,
        disabled: Colors.grey,
        guideCorner: Colors.brown,
        galleryBackground: Colors.black,
      );
      expect(colors, isA<AppColorsData>());
    });
  });

  group('AppColorsData.light()', () {
    test('creates light theme colors', () {
      final light = AppColorsData.light();
      expect(light, isA<AppColorsData>());
    });

    test('has white background', () {
      final light = AppColorsData.light();
      expect(light.background, const Color(0xFFFFFFFF));
    });

    test('has black text primary', () {
      final light = AppColorsData.light();
      expect(light.textPrimary, const Color(0xFF000000));
    });
  });

  group('AppColorsData.dark()', () {
    test('creates dark theme colors', () {
      final dark = AppColorsData.dark();
      expect(dark, isA<AppColorsData>());
    });

    test('has dark background', () {
      final dark = AppColorsData.dark();
      expect(dark.background, const Color(0xFF0F0F0F));
    });

    test('has white text primary', () {
      final dark = AppColorsData.dark();
      expect(dark.textPrimary, const Color(0xFFFFFFFF));
    });
  });

  group('AppColorsData.copyWith', () {
    test('returns new instance with updated field', () {
      final original = AppColorsData.light();
      final copy = original.copyWith(background: Colors.red);
      expect(copy.background, Colors.red);
      expect(copy.textPrimary, original.textPrimary);
    });

    test('preserves all fields when no overrides', () {
      final original = AppColorsData.dark();
      final copy = original.copyWith();
      expect(copy.background, original.background);
      expect(copy.textPrimary, original.textPrimary);
      expect(copy.danger, original.danger);
      expect(copy.success, original.success);
      expect(copy.galleryBackground, original.galleryBackground);
    });

    test('can override multiple fields', () {
      final original = AppColorsData.light();
      final copy = original.copyWith(
        background: Colors.red,
        textPrimary: Colors.green,
        danger: Colors.purple,
      );
      expect(copy.background, Colors.red);
      expect(copy.textPrimary, Colors.green);
      expect(copy.danger, Colors.purple);
      expect(copy.surface, original.surface);
    });
  });

  group('AppColorsData.lerp', () {
    test('returns self when other is null', () {
      final light = AppColorsData.light();
      final result = light.lerp(null, 0.5);
      expect(result.background, light.background);
    });

    test('returns self at t=0', () {
      final light = AppColorsData.light();
      final dark = AppColorsData.dark();
      final result = light.lerp(dark, 0.0);
      expect(result.background, light.background);
    });

    test('returns other at t=1', () {
      final light = AppColorsData.light();
      final dark = AppColorsData.dark();
      final result = light.lerp(dark, 1.0);
      expect(result.background, dark.background);
    });

    test('interpolates at t=0.5', () {
      final light = AppColorsData.light();
      final dark = AppColorsData.dark();
      final result = light.lerp(dark, 0.5);
      // Interpolated color should be between light and dark
      expect(result.background, isNot(equals(light.background)));
      expect(result.background, isNot(equals(dark.background)));
    });
  });

  group('AppColorsData is ThemeExtension', () {
    test('extends ThemeExtension<AppColorsData>', () {
      final colors = AppColorsData.light();
      expect(colors, isA<ThemeExtension<AppColorsData>>());
    });
  });
}
