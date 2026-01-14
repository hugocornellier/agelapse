import 'package:flutter/material.dart';

/// Immutable configuration for gallery date stamp display.
///
/// Used by [GalleryDateStampProvider] to efficiently propagate
/// date label settings to gallery thumbnails without forcing
/// full grid rebuilds.
@immutable
class GalleryDateStampConfig {
  /// Whether date labels are shown on stabilized photo thumbnails.
  final bool stabilizedLabelsEnabled;

  /// Whether date labels are shown on raw photo thumbnails.
  final bool rawLabelsEnabled;

  /// Date format pattern (e.g., 'MM/yy', 'MMM dd').
  final String dateFormat;

  /// Map of timestamp -> timezone offset in minutes.
  /// Used for accurate local time display.
  /// Reference equality is used for comparison (not deep equality).
  final Map<String, int?> captureOffsetMap;

  const GalleryDateStampConfig({
    required this.stabilizedLabelsEnabled,
    required this.rawLabelsEnabled,
    required this.dateFormat,
    required this.captureOffsetMap,
  });

  /// Disabled/default configuration used during initialization.
  static const GalleryDateStampConfig disabled = GalleryDateStampConfig(
    stabilizedLabelsEnabled: false,
    rawLabelsEnabled: false,
    dateFormat: 'MM/yy',
    captureOffsetMap: {},
  );

  /// Efficient equality check.
  /// Uses reference equality for captureOffsetMap (O(1) vs O(n)).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GalleryDateStampConfig &&
          stabilizedLabelsEnabled == other.stabilizedLabelsEnabled &&
          rawLabelsEnabled == other.rawLabelsEnabled &&
          dateFormat == other.dateFormat &&
          identical(captureOffsetMap, other.captureOffsetMap);

  @override
  int get hashCode => Object.hash(
        stabilizedLabelsEnabled,
        rawLabelsEnabled,
        dateFormat,
        identityHashCode(captureOffsetMap),
      );

  /// Create a copy with optional overrides.
  GalleryDateStampConfig copyWith({
    bool? stabilizedLabelsEnabled,
    bool? rawLabelsEnabled,
    String? dateFormat,
    Map<String, int?>? captureOffsetMap,
  }) {
    return GalleryDateStampConfig(
      stabilizedLabelsEnabled:
          stabilizedLabelsEnabled ?? this.stabilizedLabelsEnabled,
      rawLabelsEnabled: rawLabelsEnabled ?? this.rawLabelsEnabled,
      dateFormat: dateFormat ?? this.dateFormat,
      captureOffsetMap: captureOffsetMap ?? this.captureOffsetMap,
    );
  }
}

/// Provides [GalleryDateStampConfig] to descendant widgets.
///
/// Thumbnails access this via [GalleryDateStampProvider.of] and
/// automatically rebuild when the configuration changes.
///
/// Example usage in thumbnail builder:
/// ```dart
/// builder: (context, constraints) {
///   final config = GalleryDateStampProvider.of(context);
///   if (!config.rawLabelsEnabled) return thumbnail;
///   // ... render with date label
/// }
/// ```
class GalleryDateStampProvider extends InheritedWidget {
  final GalleryDateStampConfig config;

  const GalleryDateStampProvider({
    super.key,
    required this.config,
    required super.child,
  });

  /// Access config, returning [GalleryDateStampConfig.disabled] if
  /// no provider exists in the tree.
  ///
  /// Safe to call during widget initialization or in contexts
  /// where the provider may not be present.
  static GalleryDateStampConfig of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<GalleryDateStampProvider>();
    return provider?.config ?? GalleryDateStampConfig.disabled;
  }

  /// Access config without creating a dependency.
  ///
  /// Use when you need to read the config once without subscribing
  /// to changes (e.g., in callbacks or event handlers).
  static GalleryDateStampConfig read(BuildContext context) {
    final provider =
        context.getInheritedWidgetOfExactType<GalleryDateStampProvider>();
    return provider?.config ?? GalleryDateStampConfig.disabled;
  }

  @override
  bool updateShouldNotify(GalleryDateStampProvider oldWidget) {
    return config != oldWidget.config;
  }
}
