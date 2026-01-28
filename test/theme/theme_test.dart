import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/theme/theme.dart';

void main() {
  group('MaterialTheme', () {
    late MaterialTheme theme;

    setUp(() {
      theme = const MaterialTheme(TextTheme());
    });

    group('constructor', () {
      test('creates instance with text theme', () {
        const textTheme = TextTheme();
        const materialTheme = MaterialTheme(textTheme);
        expect(materialTheme.textTheme, equals(textTheme));
      });
    });

    group('lightScheme', () {
      test('returns MaterialScheme with light brightness', () {
        final scheme = MaterialTheme.lightScheme();
        expect(scheme.brightness, equals(Brightness.light));
      });

      test('has non-null primary color', () {
        final scheme = MaterialTheme.lightScheme();
        expect(scheme.primary, isNotNull);
      });

      test('has non-null surface color', () {
        final scheme = MaterialTheme.lightScheme();
        expect(scheme.surface, isNotNull);
      });
    });

    group('darkScheme', () {
      test('returns MaterialScheme with dark brightness', () {
        final scheme = MaterialTheme.darkScheme();
        expect(scheme.brightness, equals(Brightness.dark));
      });

      test('has non-null primary color', () {
        final scheme = MaterialTheme.darkScheme();
        expect(scheme.primary, isNotNull);
      });

      test('has non-null surface color', () {
        final scheme = MaterialTheme.darkScheme();
        expect(scheme.surface, isNotNull);
      });
    });

    group('light()', () {
      test('returns ThemeData', () {
        final themeData = theme.light();
        expect(themeData, isA<ThemeData>());
      });

      test('returns light theme', () {
        final themeData = theme.light();
        expect(themeData.brightness, equals(Brightness.light));
      });

      test('uses material 3', () {
        final themeData = theme.light();
        expect(themeData.useMaterial3, isTrue);
      });
    });

    group('dark()', () {
      test('returns ThemeData', () {
        final themeData = theme.dark();
        expect(themeData, isA<ThemeData>());
      });

      test('returns dark theme', () {
        final themeData = theme.dark();
        expect(themeData.brightness, equals(Brightness.dark));
      });

      test('uses material 3', () {
        final themeData = theme.dark();
        expect(themeData.useMaterial3, isTrue);
      });
    });

    group('lightMediumContrastScheme', () {
      test('returns MaterialScheme with light brightness', () {
        final scheme = MaterialTheme.lightMediumContrastScheme();
        expect(scheme.brightness, equals(Brightness.light));
      });
    });

    group('lightHighContrastScheme', () {
      test('returns MaterialScheme with light brightness', () {
        final scheme = MaterialTheme.lightHighContrastScheme();
        expect(scheme.brightness, equals(Brightness.light));
      });
    });

    group('darkMediumContrastScheme', () {
      test('returns MaterialScheme with dark brightness', () {
        final scheme = MaterialTheme.darkMediumContrastScheme();
        expect(scheme.brightness, equals(Brightness.dark));
      });
    });

    group('darkHighContrastScheme', () {
      test('returns MaterialScheme with dark brightness', () {
        final scheme = MaterialTheme.darkHighContrastScheme();
        expect(scheme.brightness, equals(Brightness.dark));
      });
    });

    group('contrast theme methods', () {
      test('lightMediumContrast returns ThemeData', () {
        final themeData = theme.lightMediumContrast();
        expect(themeData, isA<ThemeData>());
        expect(themeData.brightness, equals(Brightness.light));
      });

      test('lightHighContrast returns ThemeData', () {
        final themeData = theme.lightHighContrast();
        expect(themeData, isA<ThemeData>());
        expect(themeData.brightness, equals(Brightness.light));
      });

      test('darkMediumContrast returns ThemeData', () {
        final themeData = theme.darkMediumContrast();
        expect(themeData, isA<ThemeData>());
        expect(themeData.brightness, equals(Brightness.dark));
      });

      test('darkHighContrast returns ThemeData', () {
        final themeData = theme.darkHighContrast();
        expect(themeData, isA<ThemeData>());
        expect(themeData.brightness, equals(Brightness.dark));
      });
    });

    group('extendedColors', () {
      test('returns empty list', () {
        expect(theme.extendedColors, isEmpty);
      });

      test('returns list of ExtendedColor', () {
        expect(theme.extendedColors, isA<List<ExtendedColor>>());
      });
    });
  });

  group('MaterialScheme', () {
    test('constructor creates instance with all required properties', () {
      const scheme = MaterialScheme(
        brightness: Brightness.light,
        primary: Color(0xFF000000),
        surfaceTint: Color(0xFF000000),
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFF000000),
        onPrimaryContainer: Color(0xFFFFFFFF),
        secondary: Color(0xFF000000),
        onSecondary: Color(0xFFFFFFFF),
        secondaryContainer: Color(0xFF000000),
        onSecondaryContainer: Color(0xFFFFFFFF),
        tertiary: Color(0xFF000000),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFF000000),
        onTertiaryContainer: Color(0xFFFFFFFF),
        error: Color(0xFFFF0000),
        onError: Color(0xFFFFFFFF),
        errorContainer: Color(0xFFFFCCCC),
        onErrorContainer: Color(0xFF000000),
        background: Color(0xFFFFFFFF),
        onBackground: Color(0xFF000000),
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF000000),
        surfaceVariant: Color(0xFFCCCCCC),
        onSurfaceVariant: Color(0xFF333333),
        outline: Color(0xFF666666),
        outlineVariant: Color(0xFF999999),
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFF000000),
        inverseOnSurface: Color(0xFFFFFFFF),
        inversePrimary: Color(0xFFCCCCCC),
        primaryFixed: Color(0xFF000000),
        onPrimaryFixed: Color(0xFFFFFFFF),
        primaryFixedDim: Color(0xFF000000),
        onPrimaryFixedVariant: Color(0xFFFFFFFF),
        secondaryFixed: Color(0xFF000000),
        onSecondaryFixed: Color(0xFFFFFFFF),
        secondaryFixedDim: Color(0xFF000000),
        onSecondaryFixedVariant: Color(0xFFFFFFFF),
        tertiaryFixed: Color(0xFF000000),
        onTertiaryFixed: Color(0xFFFFFFFF),
        tertiaryFixedDim: Color(0xFF000000),
        onTertiaryFixedVariant: Color(0xFFFFFFFF),
        surfaceDim: Color(0xFFDDDDDD),
        surfaceBright: Color(0xFFFFFFFF),
        surfaceContainerLowest: Color(0xFFFFFFFF),
        surfaceContainerLow: Color(0xFFFAFAFA),
        surfaceContainer: Color(0xFFF5F5F5),
        surfaceContainerHigh: Color(0xFFF0F0F0),
        surfaceContainerHighest: Color(0xFFEBEBEB),
      );

      expect(scheme.brightness, equals(Brightness.light));
      expect(scheme.primary, equals(const Color(0xFF000000)));
    });
  });

  group('MaterialSchemeUtils', () {
    test('toColorScheme converts to ColorScheme', () {
      final scheme = MaterialTheme.lightScheme();
      final colorScheme = scheme.toColorScheme();

      expect(colorScheme, isA<ColorScheme>());
      expect(colorScheme.brightness, equals(scheme.brightness));
      expect(colorScheme.primary, equals(scheme.primary));
      expect(colorScheme.secondary, equals(scheme.secondary));
      expect(colorScheme.error, equals(scheme.error));
    });

    test('light scheme converts to light ColorScheme', () {
      final scheme = MaterialTheme.lightScheme();
      final colorScheme = scheme.toColorScheme();

      expect(colorScheme.brightness, equals(Brightness.light));
    });

    test('dark scheme converts to dark ColorScheme', () {
      final scheme = MaterialTheme.darkScheme();
      final colorScheme = scheme.toColorScheme();

      expect(colorScheme.brightness, equals(Brightness.dark));
    });
  });

  group('ExtendedColor', () {
    test('constructor creates instance with all required properties', () {
      const extendedColor = ExtendedColor(
        seed: Color(0xFF000000),
        value: Color(0xFF111111),
        light: ColorFamily(
          color: Color(0xFF222222),
          onColor: Color(0xFFFFFFFF),
          colorContainer: Color(0xFF333333),
          onColorContainer: Color(0xFFFFFFFF),
        ),
        lightHighContrast: ColorFamily(
          color: Color(0xFF444444),
          onColor: Color(0xFFFFFFFF),
          colorContainer: Color(0xFF555555),
          onColorContainer: Color(0xFFFFFFFF),
        ),
        lightMediumContrast: ColorFamily(
          color: Color(0xFF666666),
          onColor: Color(0xFFFFFFFF),
          colorContainer: Color(0xFF777777),
          onColorContainer: Color(0xFFFFFFFF),
        ),
        dark: ColorFamily(
          color: Color(0xFF888888),
          onColor: Color(0xFF000000),
          colorContainer: Color(0xFF999999),
          onColorContainer: Color(0xFF000000),
        ),
        darkHighContrast: ColorFamily(
          color: Color(0xFFAAAAAA),
          onColor: Color(0xFF000000),
          colorContainer: Color(0xFFBBBBBB),
          onColorContainer: Color(0xFF000000),
        ),
        darkMediumContrast: ColorFamily(
          color: Color(0xFFCCCCCC),
          onColor: Color(0xFF000000),
          colorContainer: Color(0xFFDDDDDD),
          onColorContainer: Color(0xFF000000),
        ),
      );

      expect(extendedColor.seed, equals(const Color(0xFF000000)));
      expect(extendedColor.value, equals(const Color(0xFF111111)));
      expect(extendedColor.light, isNotNull);
      expect(extendedColor.dark, isNotNull);
    });
  });

  group('ColorFamily', () {
    test('constructor creates instance with all required properties', () {
      const colorFamily = ColorFamily(
        color: Color(0xFF000000),
        onColor: Color(0xFFFFFFFF),
        colorContainer: Color(0xFF333333),
        onColorContainer: Color(0xFFFFFFFF),
      );

      expect(colorFamily.color, equals(const Color(0xFF000000)));
      expect(colorFamily.onColor, equals(const Color(0xFFFFFFFF)));
      expect(colorFamily.colorContainer, equals(const Color(0xFF333333)));
      expect(colorFamily.onColorContainer, equals(const Color(0xFFFFFFFF)));
    });
  });
}
