import "package:flutter/material.dart";

class MaterialTheme {
  final TextTheme textTheme;

  const MaterialTheme(this.textTheme);

  static MaterialScheme lightScheme() {
    return const MaterialScheme(
      brightness: Brightness.light,
      primary: Color(0xFF415F91),
      surfaceTint: Color(0xFF415F91),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFD6E3FF),
      onPrimaryContainer: Color(0xFF001B3E),
      secondary: Color(0xFF565F71),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFDAE2F9),
      onSecondaryContainer: Color(0xFF131C2B),
      tertiary: Color(0xFF815512),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFFFDDB6),
      onTertiaryContainer: Color(0xFF2A1800),
      error: Color(0xFFBA1A1A),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      background: Color(0xFFF9F9FF),
      onBackground: Color(0xFF191C20),
      surface: Color(0xFFF9F9FF),
      onSurface: Color(0xFF191C20),
      surfaceVariant: Color(0xFFE0E2EC),
      onSurfaceVariant: Color(0xFF44474E),
      outline: Color(0xFF74777F),
      outlineVariant: Color(0xFFC4C6D0),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF2E3036),
      inverseOnSurface: Color(0xFFF0F0F7),
      inversePrimary: Color(0xFFAAC7FF),
      primaryFixed: Color(0xFFD6E3FF),
      onPrimaryFixed: Color(0xFF001B3E),
      primaryFixedDim: Color(0xFFAAC7FF),
      onPrimaryFixedVariant: Color(0xFF284777),
      secondaryFixed: Color(0xFFDAE2F9),
      onSecondaryFixed: Color(0xFF131C2B),
      secondaryFixedDim: Color(0xFFBEC6DC),
      onSecondaryFixedVariant: Color(0xFF3E4759),
      tertiaryFixed: Color(0xFFFFDDB6),
      onTertiaryFixed: Color(0xFF2A1800),
      tertiaryFixedDim: Color(0xFFF7BC70),
      onTertiaryFixedVariant: Color(0xFF643F00),
      surfaceDim: Color(0xFFD9D9E0),
      surfaceBright: Color(0xFFF9F9FF),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF3F3FA),
      surfaceContainer: Color(0xFFEDEDF4),
      surfaceContainerHigh: Color(0xFFE7E8EE),
      surfaceContainerHighest: Color(0xFFE2E2E9),
    );
  }

  ThemeData light() {
    return theme(lightScheme().toColorScheme());
  }

  static MaterialScheme lightMediumContrastScheme() {
    return const MaterialScheme(
      brightness: Brightness.light,
      primary: Color(0xFF234373),
      surfaceTint: Color(0xFF415F91),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFF5875A8),
      onPrimaryContainer: Color(0xFFFFFFFF),
      secondary: Color(0xFF3A4354),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFF6C7588),
      onSecondaryContainer: Color(0xFFFFFFFF),
      tertiary: Color(0xFF5F3B00),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFF9B6B28),
      onTertiaryContainer: Color(0xFFFFFFFF),
      error: Color(0xFF8C0009),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFDA342E),
      onErrorContainer: Color(0xFFFFFFFF),
      background: Color(0xFFF9F9FF),
      onBackground: Color(0xFF191C20),
      surface: Color(0xFFF9F9FF),
      onSurface: Color(0xFF191C20),
      surfaceVariant: Color(0xFFE0E2EC),
      onSurfaceVariant: Color(0xFF40434A),
      outline: Color(0xFF5C5F67),
      outlineVariant: Color(0xFF787A83),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF2E3036),
      inverseOnSurface: Color(0xFFF0F0F7),
      inversePrimary: Color(0xFFAAC7FF),
      primaryFixed: Color(0xFF5875A8),
      onPrimaryFixed: Color(0xFFFFFFFF),
      primaryFixedDim: Color(0xFF3E5C8E),
      onPrimaryFixedVariant: Color(0xFFFFFFFF),
      secondaryFixed: Color(0xFF6C7588),
      onSecondaryFixed: Color(0xFFFFFFFF),
      secondaryFixedDim: Color(0xFF535C6F),
      onSecondaryFixedVariant: Color(0xFFFFFFFF),
      tertiaryFixed: Color(0xFF9B6B28),
      onTertiaryFixed: Color(0xFFFFFFFF),
      tertiaryFixedDim: Color(0xFF7E530F),
      onTertiaryFixedVariant: Color(0xFFFFFFFF),
      surfaceDim: Color(0xFFD9D9E0),
      surfaceBright: Color(0xFFF9F9FF),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF3F3FA),
      surfaceContainer: Color(0xFFEDEDF4),
      surfaceContainerHigh: Color(0xFFE7E8EE),
      surfaceContainerHighest: Color(0xFFE2E2E9),
    );
  }

  ThemeData lightMediumContrast() {
    return theme(lightMediumContrastScheme().toColorScheme());
  }

  static MaterialScheme lightHighContrastScheme() {
    return const MaterialScheme(
      brightness: Brightness.light,
      primary: Color(0xFF00214A),
      surfaceTint: Color(0xFF415F91),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFF234373),
      onPrimaryContainer: Color(0xFFFFFFFF),
      secondary: Color(0xFF192232),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFF3A4354),
      onSecondaryContainer: Color(0xFFFFFFFF),
      tertiary: Color(0xFF331E00),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFF5F3B00),
      onTertiaryContainer: Color(0xFFFFFFFF),
      error: Color(0xFF4E0002),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFF8C0009),
      onErrorContainer: Color(0xFFFFFFFF),
      background: Color(0xFFF9F9FF),
      onBackground: Color(0xFF191C20),
      surface: Color(0xFFF9F9FF),
      onSurface: Color(0xFF000000),
      surfaceVariant: Color(0xFFE0E2EC),
      onSurfaceVariant: Color(0xFF21242B),
      outline: Color(0xFF40434A),
      outlineVariant: Color(0xFF40434A),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF2E3036),
      inverseOnSurface: Color(0xFFFFFFFF),
      inversePrimary: Color(0xFFE5ECFF),
      primaryFixed: Color(0xFF234373),
      onPrimaryFixed: Color(0xFFFFFFFF),
      primaryFixedDim: Color(0xFF042C5B),
      onPrimaryFixedVariant: Color(0xFFFFFFFF),
      secondaryFixed: Color(0xFF3A4354),
      onSecondaryFixed: Color(0xFFFFFFFF),
      secondaryFixedDim: Color(0xFF242D3D),
      onSecondaryFixedVariant: Color(0xFFFFFFFF),
      tertiaryFixed: Color(0xFF5F3B00),
      onTertiaryFixed: Color(0xFFFFFFFF),
      tertiaryFixedDim: Color(0xFF412700),
      onTertiaryFixedVariant: Color(0xFFFFFFFF),
      surfaceDim: Color(0xFFD9D9E0),
      surfaceBright: Color(0xFFF9F9FF),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF3F3FA),
      surfaceContainer: Color(0xFFEDEDF4),
      surfaceContainerHigh: Color(0xFFE7E8EE),
      surfaceContainerHighest: Color(0xFFE2E2E9),
    );
  }

  ThemeData lightHighContrast() {
    return theme(lightHighContrastScheme().toColorScheme());
  }

  static MaterialScheme darkScheme() {
    return const MaterialScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFAAC7FF),
      surfaceTint: Color(0xFFAAC7FF),
      onPrimary: Color(0xFF0A305F),
      primaryContainer: Color(0xFF284777),
      onPrimaryContainer: Color(0xFFD6E3FF),
      secondary: Color(0xFFBEC6DC),
      onSecondary: Color(0xFF283141),
      secondaryContainer: Color(0xFF3E4759),
      onSecondaryContainer: Color(0xFFDAE2F9),
      tertiary: Color(0xFFF7BC70),
      onTertiary: Color(0xFF462A00),
      tertiaryContainer: Color(0xFF643F00),
      onTertiaryContainer: Color(0xFFFFDDB6),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      background: Color(0xFF111318),
      onBackground: Color(0xFFE2E2E9),
      surface: Color(0xFF111318),
      onSurface: Color(0xFFE2E2E9),
      surfaceVariant: Color(0xFF44474E),
      onSurfaceVariant: Color(0xFFC4C6D0),
      outline: Color(0xFF8E9099),
      outlineVariant: Color(0xFF44474E),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFE2E2E9),
      inverseOnSurface: Color(0xFF2E3036),
      inversePrimary: Color(0xFF415F91),
      primaryFixed: Color(0xFFD6E3FF),
      onPrimaryFixed: Color(0xFF001B3E),
      primaryFixedDim: Color(0xFFAAC7FF),
      onPrimaryFixedVariant: Color(0xFF284777),
      secondaryFixed: Color(0xFFDAE2F9),
      onSecondaryFixed: Color(0xFF131C2B),
      secondaryFixedDim: Color(0xFFBEC6DC),
      onSecondaryFixedVariant: Color(0xFF3E4759),
      tertiaryFixed: Color(0xFFFFDDB6),
      onTertiaryFixed: Color(0xFF2A1800),
      tertiaryFixedDim: Color(0xFFF7BC70),
      onTertiaryFixedVariant: Color(0xFF643F00),
      surfaceDim: Color(0xFF111318),
      surfaceBright: Color(0xFF37393E),
      surfaceContainerLowest: Color(0xFF0C0E13),
      surfaceContainerLow: Color(0xFF191C20),
      surfaceContainer: Color(0xFF1D2024),
      surfaceContainerHigh: Color(0xFF282A2F),
      surfaceContainerHighest: Color(0xFF33353A),
    );
  }

  ThemeData dark() {
    return theme(darkScheme().toColorScheme());
  }

  static MaterialScheme darkMediumContrastScheme() {
    return const MaterialScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFB1CBFF),
      surfaceTint: Color(0xFFAAC7FF),
      onPrimary: Color(0xFF001634),
      primaryContainer: Color(0xFF7491C7),
      onPrimaryContainer: Color(0xFF000000),
      secondary: Color(0xFFC2CBE0),
      onSecondary: Color(0xFF0D1626),
      secondaryContainer: Color(0xFF8891A5),
      onSecondaryContainer: Color(0xFF000000),
      tertiary: Color(0xFFFBC074),
      onTertiary: Color(0xFF231300),
      tertiaryContainer: Color(0xFFBB8741),
      onTertiaryContainer: Color(0xFF000000),
      error: Color(0xFFFFBAB1),
      onError: Color(0xFF370001),
      errorContainer: Color(0xFFFF5449),
      onErrorContainer: Color(0xFF000000),
      background: Color(0xFF111318),
      onBackground: Color(0xFFE2E2E9),
      surface: Color(0xFF111318),
      onSurface: Color(0xFFFBFAFF),
      surfaceVariant: Color(0xFF44474E),
      onSurfaceVariant: Color(0xFFC8CAD4),
      outline: Color(0xFFA0A3AC),
      outlineVariant: Color(0xFF80838C),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFE2E2E9),
      inverseOnSurface: Color(0xFF282A2F),
      inversePrimary: Color(0xFF294878),
      primaryFixed: Color(0xFFD6E3FF),
      onPrimaryFixed: Color(0xFF00112B),
      primaryFixedDim: Color(0xFFAAC7FF),
      onPrimaryFixedVariant: Color(0xFF133665),
      secondaryFixed: Color(0xFFDAE2F9),
      onSecondaryFixed: Color(0xFF081121),
      secondaryFixedDim: Color(0xFFBEC6DC),
      onSecondaryFixedVariant: Color(0xFF2E3647),
      tertiaryFixed: Color(0xFFFFDDB6),
      onTertiaryFixed: Color(0xFF1C0E00),
      tertiaryFixedDim: Color(0xFFF7BC70),
      onTertiaryFixedVariant: Color(0xFF4E3000),
      surfaceDim: Color(0xFF111318),
      surfaceBright: Color(0xFF37393E),
      surfaceContainerLowest: Color(0xFF0C0E13),
      surfaceContainerLow: Color(0xFF191C20),
      surfaceContainer: Color(0xFF1D2024),
      surfaceContainerHigh: Color(0xFF282A2F),
      surfaceContainerHighest: Color(0xFF33353A),
    );
  }

  ThemeData darkMediumContrast() {
    return theme(darkMediumContrastScheme().toColorScheme());
  }

  static MaterialScheme darkHighContrastScheme() {
    return const MaterialScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFFBFAFF),
      surfaceTint: Color(0xFFAAC7FF),
      onPrimary: Color(0xFF000000),
      primaryContainer: Color(0xFFB1CBFF),
      onPrimaryContainer: Color(0xFF000000),
      secondary: Color(0xFFFBFAFF),
      onSecondary: Color(0xFF000000),
      secondaryContainer: Color(0xFFC2CBE0),
      onSecondaryContainer: Color(0xFF000000),
      tertiary: Color(0xFFFFFAF7),
      onTertiary: Color(0xFF000000),
      tertiaryContainer: Color(0xFFFBC074),
      onTertiaryContainer: Color(0xFF000000),
      error: Color(0xFFFFF9F9),
      onError: Color(0xFF000000),
      errorContainer: Color(0xFFFFBAB1),
      onErrorContainer: Color(0xFF000000),
      background: Color(0xFF111318),
      onBackground: Color(0xFFE2E2E9),
      surface: Color(0xFF111318),
      onSurface: Color(0xFFFFFFFF),
      surfaceVariant: Color(0xFF44474E),
      onSurfaceVariant: Color(0xFFFBFAFF),
      outline: Color(0xFFC8CAD4),
      outlineVariant: Color(0xFFC8CAD4),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFE2E2E9),
      inverseOnSurface: Color(0xFF000000),
      inversePrimary: Color(0xFF002959),
      primaryFixed: Color(0xFFDDE7FF),
      onPrimaryFixed: Color(0xFF000000),
      primaryFixedDim: Color(0xFFB1CBFF),
      onPrimaryFixedVariant: Color(0xFF001634),
      secondaryFixed: Color(0xFFDEE7FD),
      onSecondaryFixed: Color(0xFF000000),
      secondaryFixedDim: Color(0xFFC2CBE0),
      onSecondaryFixedVariant: Color(0xFF0D1626),
      tertiaryFixed: Color(0xFFFFE2C3),
      onTertiaryFixed: Color(0xFF000000),
      tertiaryFixedDim: Color(0xFFFBC074),
      onTertiaryFixedVariant: Color(0xFF231300),
      surfaceDim: Color(0xFF111318),
      surfaceBright: Color(0xFF37393E),
      surfaceContainerLowest: Color(0xFF0C0E13),
      surfaceContainerLow: Color(0xFF191C20),
      surfaceContainer: Color(0xFF1D2024),
      surfaceContainerHigh: Color(0xFF282A2F),
      surfaceContainerHighest: Color(0xFF33353A),
    );
  }

  ThemeData darkHighContrast() {
    return theme(darkHighContrastScheme().toColorScheme());
  }

  ThemeData theme(ColorScheme colorScheme) => ThemeData(
        useMaterial3: true,
        brightness: colorScheme.brightness,
        colorScheme: colorScheme,
        textTheme: textTheme.apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        ),
        scaffoldBackgroundColor: colorScheme.surface,
        canvasColor: colorScheme.surface,
      );

  List<ExtendedColor> get extendedColors => [];
}

class MaterialScheme {
  const MaterialScheme({
    required this.brightness,
    required this.primary,
    required this.surfaceTint,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.background,
    required this.onBackground,
    required this.surface,
    required this.onSurface,
    required this.surfaceVariant,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.shadow,
    required this.scrim,
    required this.inverseSurface,
    required this.inverseOnSurface,
    required this.inversePrimary,
    required this.primaryFixed,
    required this.onPrimaryFixed,
    required this.primaryFixedDim,
    required this.onPrimaryFixedVariant,
    required this.secondaryFixed,
    required this.onSecondaryFixed,
    required this.secondaryFixedDim,
    required this.onSecondaryFixedVariant,
    required this.tertiaryFixed,
    required this.onTertiaryFixed,
    required this.tertiaryFixedDim,
    required this.onTertiaryFixedVariant,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
  });

  final Brightness brightness;
  final Color primary;
  final Color surfaceTint;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color background;
  final Color onBackground;
  final Color surface;
  final Color onSurface;
  final Color surfaceVariant;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color shadow;
  final Color scrim;
  final Color inverseSurface;
  final Color inverseOnSurface;
  final Color inversePrimary;
  final Color primaryFixed;
  final Color onPrimaryFixed;
  final Color primaryFixedDim;
  final Color onPrimaryFixedVariant;
  final Color secondaryFixed;
  final Color onSecondaryFixed;
  final Color secondaryFixedDim;
  final Color onSecondaryFixedVariant;
  final Color tertiaryFixed;
  final Color onTertiaryFixed;
  final Color tertiaryFixedDim;
  final Color onTertiaryFixedVariant;
  final Color surfaceDim;
  final Color surfaceBright;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
}

extension MaterialSchemeUtils on MaterialScheme {
  ColorScheme toColorScheme() {
    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      tertiary: tertiary,
      onTertiary: onTertiary,
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: onTertiaryContainer,
      error: error,
      onError: onError,
      errorContainer: errorContainer,
      onErrorContainer: onErrorContainer,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surfaceVariant,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant,
      shadow: shadow,
      scrim: scrim,
      inverseSurface: inverseSurface,
      onInverseSurface: inverseOnSurface,
      inversePrimary: inversePrimary,
    );
  }
}

class ExtendedColor {
  final Color seed, value;
  final ColorFamily light;
  final ColorFamily lightHighContrast;
  final ColorFamily lightMediumContrast;
  final ColorFamily dark;
  final ColorFamily darkHighContrast;
  final ColorFamily darkMediumContrast;

  const ExtendedColor({
    required this.seed,
    required this.value,
    required this.light,
    required this.lightHighContrast,
    required this.lightMediumContrast,
    required this.dark,
    required this.darkHighContrast,
    required this.darkMediumContrast,
  });
}

class ColorFamily {
  const ColorFamily({
    required this.color,
    required this.onColor,
    required this.colorContainer,
    required this.onColorContainer,
  });

  final Color color;
  final Color onColor;
  final Color colorContainer;
  final Color onColorContainer;
}
