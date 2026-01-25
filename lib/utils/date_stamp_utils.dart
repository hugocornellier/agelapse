import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/custom_font_manager.dart';
import '../services/log_service.dart';
import '../styles/styles.dart';
import 'capture_timezone.dart';

/// Utility class for date stamp formatting, positioning, and styling.
/// Used for both gallery preview overlays and export compositing.
class DateStampUtils {
  // Gallery date format options (compact for thumbnails)
  static const String galleryFormatMMYY = 'MM/yy';
  static const String galleryFormatMMMDD = 'MMM dd';
  static const String galleryFormatMMMDDYY = "MMM dd ''yy";
  static const String galleryFormatDDMMM = 'dd MMM';
  static const String galleryFormatMMMYYYY = 'MMM yyyy';
  static const String galleryFormatCustom = '_custom_gallery';

  // Export date format options (full formats)
  static const String exportFormatISO = 'yyyy-MM-dd';
  static const String exportFormatUS = 'MM/dd/yyyy';
  static const String exportFormatEU = 'dd/MM/yyyy';
  static const String exportFormatLong = 'MMM dd, yyyy';
  static const String exportFormatShort = 'dd MMM yyyy';
  static const String exportFormatCustom = '_custom_export';

  // Character limits for custom formats
  static const int galleryFormatMaxLength = 15;
  static const int exportFormatMaxLength = 40;

  // List of gallery preset formats (for checking if a format is custom)
  static const List<String> galleryPresets = [
    galleryFormatMMYY,
    galleryFormatMMMDD,
    galleryFormatMMMDDYY,
    galleryFormatDDMMM,
    galleryFormatMMMYYYY,
  ];

  // List of export preset formats (for checking if a format is custom)
  static const List<String> exportPresets = [
    exportFormatISO,
    exportFormatUS,
    exportFormatEU,
    exportFormatLong,
    exportFormatShort,
  ];

  // Position options
  static const String positionLowerRight = 'lower right';
  static const String positionLowerLeft = 'lower left';
  static const String positionUpperRight = 'upper right';
  static const String positionUpperLeft = 'upper left';

  // Default values
  static const String defaultGalleryFormat = galleryFormatMMYY;
  static const String defaultExportFormat = exportFormatLong;
  static const String defaultPosition = positionLowerRight;
  static const double defaultOpacity = 1.0;
  static const int defaultSizePercent = 3;

  // Font options (bundled, copyright-free fonts)
  static const String fontInter = 'Inter';
  static const String fontRoboto = 'Roboto';
  static const String fontSourceSans = 'SourceSans3';
  static const String fontNunito = 'Nunito';
  static const String fontJetBrainsMono = 'JetBrainsMono';
  static const String fontSameAsGallery = '_same_as_gallery';

  /// Marker value for "Custom (TTF/OTF)" option in dropdown.
  /// When selected, triggers file picker to import a custom font.
  static const String fontCustomMarker = '_custom_font';

  // Default font
  static const String defaultFont = fontInter;

  // DateFormat cache to avoid creating new instances during builds
  static final Map<String, DateFormat> _formatCache = {};

  // All bundled fonts (for dropdown - doesn't include custom fonts)
  static const List<String> bundledFonts = [
    fontInter,
    fontRoboto,
    fontSourceSans,
    fontNunito,
    fontJetBrainsMono,
  ];

  // Legacy alias for bundledFonts (for backwards compatibility)
  static const List<String> availableFonts = bundledFonts;

  /// Get display name for font option (synchronous version for bundled fonts).
  /// For custom fonts, use getFontDisplayNameAsync.
  static String getFontDisplayName(String font) {
    switch (font) {
      case fontInter:
        return 'Inter';
      case fontRoboto:
        return 'Roboto';
      case fontSourceSans:
        return 'Source Sans';
      case fontNunito:
        return 'Nunito';
      case fontJetBrainsMono:
        return 'JetBrains Mono';
      case fontSameAsGallery:
        return 'Same as thumbnail';
      case fontCustomMarker:
        return 'Custom (TTF/OTF)';
      default:
        // Check if it's a custom font (starts with prefix)
        if (isCustomFont(font)) {
          // For synchronous calls, return a placeholder
          // Use getFontDisplayNameAsync for proper display name
          return 'Custom Font';
        }
        return 'Inter';
    }
  }

  /// Get display name for font option (async version that handles custom fonts).
  static Future<String> getFontDisplayNameAsync(String font) async {
    // First check bundled fonts
    if (!isCustomFont(font)) {
      return getFontDisplayName(font);
    }

    // It's a custom font - get display name from CustomFontManager
    final customFont =
        await CustomFontManager.instance.getCustomFontByFamilyName(font);
    if (customFont != null) {
      return customFont.displayName;
    }

    // Fallback
    return 'Custom Font';
  }

  /// Check if a font family name is a custom font.
  static bool isCustomFont(String fontFamily) {
    return fontFamily.startsWith(CustomFontManager.customFontPrefix);
  }

  /// Check if a font family name is a bundled font.
  static bool isBundledFont(String fontFamily) {
    return bundledFonts.contains(fontFamily);
  }

  /// Get all available fonts (bundled + custom).
  /// Returns a list of font family names.
  static Future<List<String>> getAllAvailableFonts() async {
    final customFonts = await CustomFontManager.instance.getAllCustomFonts();
    final customFamilyNames = customFonts.map((f) => f.familyName).toList();
    return [...bundledFonts, ...customFamilyNames];
  }

  /// Resolve a font family to ensure it's available.
  /// Returns the font family if valid, or the default font.
  static Future<String> resolveFontFamily(String fontFamily) async {
    // Bundled fonts are always available
    if (isBundledFont(fontFamily)) {
      return fontFamily;
    }

    // Check if custom font is available
    if (isCustomFont(fontFamily)) {
      final resolved =
          await CustomFontManager.instance.resolveFontFamily(fontFamily);
      return resolved;
    }

    // Unknown font, return default
    return defaultFont;
  }

  /// Resolve export font - handles "same as gallery" logic.
  static String resolveExportFont(String exportFont, String galleryFont) {
    return exportFont == fontSameAsGallery ? galleryFont : exportFont;
  }

  /// Format a timestamp using the specified format pattern.
  /// [timestampMs] - Unix timestamp in milliseconds (UTC)
  /// [format] - DateFormat pattern string
  /// [captureOffsetMinutes] - Optional timezone offset in minutes for accurate local time
  static String formatTimestamp(
    int timestampMs,
    String format, {
    int? captureOffsetMinutes,
  }) {
    final dateTime = CaptureTimezone.toLocalDateTime(
      timestampMs,
      offsetMinutes: captureOffsetMinutes,
    );

    try {
      // Use cached formatter to avoid allocation during builds
      final formatter =
          _formatCache.putIfAbsent(format, () => DateFormat(format));
      return formatter.format(dateTime);
    } catch (e) {
      // Fallback to ISO format if pattern is invalid
      final fallback = _formatCache.putIfAbsent(
          exportFormatISO, () => DateFormat(exportFormatISO));
      return fallback.format(dateTime);
    }
  }

  /// Calculate the position offset for date stamp based on corner and margins.
  /// Returns (x, y) offset from top-left corner of the image.
  /// [imageWidth] - Width of the image in pixels
  /// [imageHeight] - Height of the image in pixels
  /// [textWidth] - Width of the rendered text in pixels
  /// [textHeight] - Height of the rendered text in pixels
  /// [position] - Corner position (e.g., 'lower right')
  /// [marginPercent] - Margin from edge as percentage (default 2%)
  static Offset calculatePosition({
    required double imageWidth,
    required double imageHeight,
    required double textWidth,
    required double textHeight,
    required String position,
    double marginPercent = 2.0,
  }) {
    final double marginX = imageWidth * (marginPercent / 100);
    final double marginY = imageHeight * (marginPercent / 100);

    double x, y;

    switch (position.toLowerCase()) {
      case positionLowerRight:
        x = imageWidth - textWidth - marginX;
        y = imageHeight - textHeight - marginY;
        break;
      case positionLowerLeft:
        x = marginX;
        y = imageHeight - textHeight - marginY;
        break;
      case positionUpperRight:
        x = imageWidth - textWidth - marginX;
        y = marginY;
        break;
      case positionUpperLeft:
        x = marginX;
        y = marginY;
        break;
      default:
        // Default to lower right
        x = imageWidth - textWidth - marginX;
        y = imageHeight - textHeight - marginY;
    }

    return Offset(x, y);
  }

  /// Calculate font size based on image height and size percentage.
  /// [imageHeight] - Height of the image in pixels
  /// [sizePercent] - Font size as percentage of image height (1-6%)
  static double calculateFontSize(double imageHeight, int sizePercent) {
    final clampedPercent = sizePercent.clamp(1, 6);
    return imageHeight * (clampedPercent / 100);
  }

  /// Get text style for gallery thumbnail date labels.
  /// Uses a semi-transparent background pill for readability.
  static TextStyle getGalleryLabelStyle(double fontSize, {String? fontFamily}) {
    return TextStyle(
      fontFamily: fontFamily ?? defaultFont,
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      color: AppColors.textPrimary,
      shadows: [
        Shadow(
            offset: const Offset(0, 1),
            blurRadius: 2,
            color: AppColors.overlay.withValues(alpha: 0.54)),
      ],
    );
  }

  /// Get text style for export date stamp.
  /// Includes text shadow for readability on any background.
  static TextStyle getExportTextStyle(
    double fontSize,
    double opacity, {
    String? fontFamily,
  }) {
    return TextStyle(
      fontFamily: fontFamily ?? defaultFont,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary.withValues(alpha: opacity),
      shadows: [
        Shadow(
          offset: const Offset(1, 1),
          blurRadius: 2,
          color: AppColors.overlay.withValues(alpha: opacity * 0.8),
        ),
        Shadow(
          offset: const Offset(-1, -1),
          blurRadius: 2,
          color: AppColors.overlay.withValues(alpha: opacity * 0.5),
        ),
      ],
    );
  }

  /// Build a gallery date label widget with background pill.
  /// [date] - Formatted date string
  /// [thumbnailHeight] - Height of the thumbnail for scaling
  /// [fontFamily] - Optional font family (defaults to Inter)
  static Widget buildGalleryDateLabel(
    String date,
    double thumbnailHeight, {
    String? fontFamily,
  }) {
    // Scale font size based on thumbnail height, minimum 8px
    final fontSize = (thumbnailHeight * 0.12).clamp(8.0, 14.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.overlay.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        date,
        style: TextStyle(
          fontFamily: fontFamily ?? defaultFont,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          height: 1.0,
        ),
      ),
    );
  }

  /// Get display name for gallery format option.
  static String getGalleryFormatDisplayName(String format) {
    switch (format) {
      case galleryFormatMMYY:
        return 'MM/YY';
      case galleryFormatMMMDD:
        return 'MMM DD';
      case galleryFormatMMMDDYY:
        return "MMM DD 'YY";
      case galleryFormatDDMMM:
        return 'DD MMM';
      case galleryFormatMMMYYYY:
        return 'MMM YYYY';
      default:
        return 'MM/YY';
    }
  }

  /// Get example text for gallery format option.
  static String getGalleryFormatExample(String format) {
    final now = DateTime.now();
    try {
      return DateFormat(format).format(now);
    } catch (e) {
      return '01/24';
    }
  }

  /// Get display name for export format option.
  static String getExportFormatDisplayName(String format) {
    switch (format) {
      case exportFormatISO:
        return 'YYYY-MM-DD';
      case exportFormatUS:
        return 'MM/DD/YYYY';
      case exportFormatEU:
        return 'DD/MM/YYYY';
      case exportFormatLong:
        return 'MMM DD, YYYY';
      case exportFormatShort:
        return 'DD MMM YYYY';
      default:
        return 'MMM DD, YYYY';
    }
  }

  /// Get example text for export format option.
  static String getExportFormatExample(String format) {
    final now = DateTime.now();
    try {
      return DateFormat(format).format(now);
    } catch (e) {
      return 'Jan 15, 2024';
    }
  }

  /// Get display name for position option.
  static String getPositionDisplayName(String position) {
    switch (position.toLowerCase()) {
      case positionLowerRight:
        return 'Lower right';
      case positionLowerLeft:
        return 'Lower left';
      case positionUpperRight:
        return 'Upper right';
      case positionUpperLeft:
        return 'Upper left';
      default:
        return 'Lower right';
    }
  }

  // ==================== Custom Format Validation ====================

  /// Validate a custom date format pattern for gallery (compact, date only).
  /// Returns null if valid, or an error message if invalid.
  static String? validateGalleryFormat(String pattern) {
    if (pattern.isEmpty) {
      return 'Format cannot be empty';
    }
    if (pattern.length > galleryFormatMaxLength) {
      return 'Maximum $galleryFormatMaxLength characters';
    }

    // Must contain at least one date token
    if (!_containsDateToken(pattern)) {
      return 'Must include at least one date token';
    }

    // Gallery formats should not include time tokens
    if (_containsTimeToken(pattern)) {
      return 'Time tokens not available for thumbnails';
    }

    // Try parsing to validate
    try {
      DateFormat(pattern).format(DateTime.now());
      return null; // Valid
    } catch (e) {
      return 'Invalid format pattern';
    }
  }

  /// Validate a custom date format pattern for export (full, date + time allowed).
  /// Returns null if valid, or an error message if invalid.
  static String? validateExportFormat(String pattern) {
    if (pattern.isEmpty) {
      return 'Format cannot be empty';
    }
    if (pattern.length > exportFormatMaxLength) {
      return 'Maximum $exportFormatMaxLength characters';
    }

    // Must contain at least one date token
    if (!_containsDateToken(pattern)) {
      return 'Must include at least one date token';
    }

    // Try parsing to validate
    try {
      DateFormat(pattern).format(DateTime.now());
      return null; // Valid
    } catch (e) {
      return 'Invalid format pattern';
    }
  }

  /// Check if pattern contains at least one date token.
  static bool _containsDateToken(String pattern) {
    // Date tokens: y (year), M (month), d (day), E (weekday)
    // Remove quoted literals before checking
    final withoutLiterals = pattern.replaceAll(RegExp(r"'[^']*'"), '');
    return RegExp(r'[yMdE]').hasMatch(withoutLiterals);
  }

  /// Check if pattern contains time tokens.
  static bool _containsTimeToken(String pattern) {
    // Time tokens: H, h (hour), m (minute), s (second), a (AM/PM)
    // Remove quoted literals before checking
    final withoutLiterals = pattern.replaceAll(RegExp(r"'[^']*'"), '');
    return RegExp(r'[Hhms]').hasMatch(withoutLiterals);
  }

  /// Check if a format is a gallery preset (not custom).
  static bool isGalleryPreset(String format) {
    return galleryPresets.contains(format);
  }

  /// Check if a format is an export preset (not custom).
  static bool isExportPreset(String format) {
    return exportPresets.contains(format);
  }

  /// Get a preview of what the format will look like.
  /// Returns the formatted date or an error indicator.
  static String getFormatPreview(String format) {
    try {
      return DateFormat(format).format(DateTime.now());
    } catch (e) {
      return '—';
    }
  }

  /// Help text content for gallery format tokens (compact reference).
  static const String galleryFormatHelpText = '''FORMAT TOKENS

Year
yyyy → 2024    yy → 24

Month
MMMM → January    MMM → Jan
MM → 01    M → 1

Day
dd → 05    d → 5
EEEE → Monday    E → Mon

Separators
- / . , space

Examples
"MMM d" → Jan 5
"MM/dd/yy" → 01/05/24
"d MMM" → 5 Jan

Keep it short (max 15 chars)''';

  /// Help text content for export format tokens (full reference).
  static const String exportFormatHelpText = '''FORMAT TOKENS

Year
yyyy → 2024    yy → 24

Month
MMMM → January    MMM → Jan
MM → 01    M → 1

Day
dd → 05    d → 5
EEEE → Monday    E → Mon

Time
HH → 14 (24hr)    hh → 02 (12hr)
h → 2    mm → 45    ss → 30
a → PM

Literal Text
Use single quotes: 'at' → at

Examples
"MMM d, yyyy" → Jan 5, 2024
"EEEE, MMMM d" → Monday, January 5
"yyyy-MM-dd HH:mm" → 2024-01-05 14:45
"h:mm a 'on' MMM d" → 2:45 PM on Jan 5''';

  /// Calculate vertical offset when both watermark and date stamp are in the same corner.
  /// Returns additional Y offset to stack date stamp below/above watermark.
  static double calculateWatermarkOffset({
    required String dateStampPosition,
    required String watermarkPosition,
    required double textHeight,
    required double imageHeight,
    double gap = 10.0,
  }) {
    if (dateStampPosition.toLowerCase() != watermarkPosition.toLowerCase()) {
      return 0.0;
    }

    // If in same corner, offset based on whether it's upper or lower
    final isLower = dateStampPosition.toLowerCase().contains('lower');
    if (isLower) {
      // Move date stamp up (negative offset since we measure from top)
      return -(textHeight + gap);
    } else {
      // Move date stamp down (positive offset)
      return textHeight + gap;
    }
  }

  /// Parse timestamp from filename (format: {timestamp}.{ext})
  static int? parseTimestampFromFilename(String filename) {
    final basename = filename.split('/').last.split('.').first;
    return int.tryParse(basename);
  }

  /// Composite a date stamp onto an image and save to output path.
  /// Returns true if successful, false otherwise.
  /// This function must be called from the main isolate (requires Flutter engine).
  /// [watermarkVerticalOffset] - Additional Y offset to avoid overlapping with watermark
  /// [fontFamily] - Font family for date stamp text (defaults to Inter)
  static Future<bool> compositeDate({
    required String inputPath,
    required String outputPath,
    required String dateText,
    required String position,
    required int sizePercent,
    required double opacity,
    double watermarkVerticalOffset = 0.0,
    String? fontFamily,
  }) async {
    try {
      LogService.instance.log(
        "[DATE_STAMP] compositeDate called: input=$inputPath, output=$outputPath, text=$dateText",
      );
      // Load image
      final file = File(inputPath);
      if (!await file.exists()) {
        LogService.instance.log(
          "[DATE_STAMP] Input file does not exist: $inputPath",
        );
        return false;
      }

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final width = image.width.toDouble();
      final height = image.height.toDouble();

      // Create a picture recorder to draw on
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Draw the original image
      canvas.drawImage(image, Offset.zero, Paint());

      // Calculate font size and position
      final fontSize = calculateFontSize(height, sizePercent);

      // Create text painter
      final textPainter = TextPainter(
        text: TextSpan(
          text: dateText,
          style: TextStyle(
            fontFamily: fontFamily ?? defaultFont,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary.withValues(alpha: opacity),
            shadows: [
              Shadow(
                offset: const Offset(2, 2),
                blurRadius: 3,
                color: AppColors.overlay.withValues(alpha: opacity * 0.8),
              ),
              Shadow(
                offset: const Offset(-1, -1),
                blurRadius: 2,
                color: AppColors.overlay.withValues(alpha: opacity * 0.5),
              ),
            ],
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();

      // Calculate position
      final textOffset = calculatePosition(
        imageWidth: width,
        imageHeight: height,
        textWidth: textPainter.width,
        textHeight: textPainter.height,
        position: position,
        marginPercent: 2.0,
      );

      // Apply watermark offset to avoid overlap
      final adjustedOffset = Offset(
        textOffset.dx,
        textOffset.dy + watermarkVerticalOffset,
      );

      // Draw text
      textPainter.paint(canvas, adjustedOffset);

      // Convert to image
      final picture = recorder.endRecording();
      final outputImage = await picture.toImage(image.width, image.height);

      // Encode to PNG
      final byteData = await outputImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return false;

      // Save to file
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(byteData.buffer.asUint8List());

      // Dispose
      image.dispose();
      outputImage.dispose();

      LogService.instance.log(
        "[DATE_STAMP] compositeDate SUCCESS: $outputPath",
      );
      return true;
    } catch (e) {
      LogService.instance.log("[DATE_STAMP] compositeDate ERROR: $e");
      return false;
    }
  }

  /// Process a batch of images with date stamps.
  /// Returns a map of original path -> temp path for files that were processed.
  /// Files that fail processing will not be included in the map.
  /// [captureOffsetMap] - Map of timestamp -> captureOffsetMinutes for accurate timezone handling
  /// [watermarkPosition] - If provided, date stamp will be offset to avoid overlap with watermark
  /// [fontFamily] - Font family for date stamp text (defaults to Inter)
  static Future<Map<String, String>> processBatchWithDateStamps({
    required List<String> inputPaths,
    required String tempDir,
    required String format,
    required String position,
    required int sizePercent,
    required double opacity,
    Map<String, int?>? captureOffsetMap,
    String? watermarkPosition,
    void Function(int current, int total)? onProgress,
    String? fontFamily,
  }) async {
    LogService.instance.log(
      "[DATE_STAMP] processBatchWithDateStamps called: ${inputPaths.length} files, format=$format, position=$position",
    );
    final result = <String, String>{};

    // Create temp directory if needed
    final dir = Directory(tempDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      LogService.instance.log("[DATE_STAMP] Created temp dir: $tempDir");
    }

    for (int i = 0; i < inputPaths.length; i++) {
      final inputPath = inputPaths[i];

      // Parse timestamp from filename
      final filename = inputPath.split('/').last;
      final basename = filename.split('.').first;
      final timestampMs = int.tryParse(basename);

      if (timestampMs == null) {
        // Skip files without valid timestamp
        LogService.instance.log(
          "[DATE_STAMP] Skipping file (no valid timestamp): $filename",
        );
        continue;
      }

      // Format date with timezone offset if available
      final int? offsetMinutes = captureOffsetMap?[basename];
      final dateText = formatTimestamp(
        timestampMs,
        format,
        captureOffsetMinutes: offsetMinutes,
      );

      // Create temp output path (preserve original filename)
      final outputPath = '$tempDir/$filename';

      // Calculate watermark offset if both are in same position
      double watermarkOffset = 0.0;
      if (watermarkPosition != null &&
          position.toLowerCase() == watermarkPosition.toLowerCase()) {
        // Estimate based on typical text height (will be proportional to image)
        // Negative for lower corners (move up), positive for upper (move down)
        final isLowerCorner = position.toLowerCase().contains('lower');
        // Use a proportional offset - roughly 4% of typical image height + gap
        watermarkOffset = isLowerCorner ? -60.0 : 60.0;
      }

      // Composite date
      final success = await compositeDate(
        inputPath: inputPath,
        outputPath: outputPath,
        dateText: dateText,
        position: position,
        sizePercent: sizePercent,
        opacity: opacity,
        watermarkVerticalOffset: watermarkOffset,
        fontFamily: fontFamily,
      );

      if (success) {
        result[inputPath] = outputPath;
      }

      onProgress?.call(i + 1, inputPaths.length);
    }

    LogService.instance.log(
      "[DATE_STAMP] processBatchWithDateStamps complete: ${result.length}/${inputPaths.length} files processed",
    );
    return result;
  }

  /// Render a date stamp as a transparent PNG matching the image preview style exactly.
  /// Returns the PNG bytes, or null on failure.
  /// [dateText] - The formatted date string to render
  /// [videoHeight] - Height of the video for scaling the font size
  /// [sizePercent] - Font size as percentage of video height (1-6)
  /// [fontFamily] - Font family for date stamp text (defaults to Inter)
  static Future<ui.Image?> renderDateStampImage({
    required String dateText,
    required int videoHeight,
    required int sizePercent,
    String? fontFamily,
  }) async {
    try {
      // Calculate font size (percentage of video height, matching preview)
      final fontSize = (videoHeight * sizePercent / 100).clamp(12.0, 200.0);

      // Fixed padding and border radius to match image preview exactly
      const double paddingH = 8.0;
      const double paddingV = 4.0;
      const double borderRadius = 4.0;

      // Measure text to determine image dimensions
      final textPainter = TextPainter(
        text: TextSpan(
          text: dateText,
          style: TextStyle(
            fontFamily: fontFamily ?? defaultFont,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
            height: 1.0,
            shadows: [
              Shadow(
                offset: const Offset(1, 1),
                blurRadius: 2,
                color: AppColors.overlay.withValues(alpha: 0.54),
              ),
            ],
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();

      // Calculate image dimensions (text + padding)
      final imageWidth = (textPainter.width + paddingH * 2).ceil();
      final imageHeight = (textPainter.height + paddingV * 2).ceil();

      // Create a picture recorder to draw on
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Draw rounded rectangle background (50% opacity black, matching preview)
      final backgroundPaint = Paint()
        ..color = AppColors.overlay.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, imageWidth.toDouble(), imageHeight.toDouble()),
        Radius.circular(borderRadius),
      );
      canvas.drawRRect(rrect, backgroundPaint);

      // Draw text centered in the box
      textPainter.paint(canvas, Offset(paddingH, paddingV));

      // Convert to image
      final picture = recorder.endRecording();
      final image = await picture.toImage(imageWidth, imageHeight);

      return image;
    } catch (e) {
      LogService.instance.log("[DATE_STAMP] renderDateStampImage failed: $e");
      return null;
    }
  }

  /// Render a date stamp PNG and save to file.
  /// Returns true if successful.
  /// [fontFamily] - Font family for date stamp text (defaults to Inter)
  static Future<bool> renderDateStampPng({
    required String dateText,
    required String outputPath,
    required int videoHeight,
    required int sizePercent,
    String? fontFamily,
  }) async {
    try {
      final image = await renderDateStampImage(
        dateText: dateText,
        videoHeight: videoHeight,
        sizePercent: sizePercent,
        fontFamily: fontFamily,
      );
      if (image == null) return false;

      // Encode to PNG
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return false;

      // Write to file
      final file = File(outputPath);
      await file.writeAsBytes(byteData.buffer.asUint8List());

      return true;
    } catch (e) {
      LogService.instance.log("[DATE_STAMP] renderDateStampPng failed: $e");
      return false;
    }
  }

  /// Generate date stamp PNG assets for video overlay.
  /// Returns a map of date text -> PNG file path, or null on failure.
  /// Also returns the temp directory path for cleanup.
  /// [fontFamily] - Font family for date stamp text (defaults to Inter)
  static Future<({Map<String, String> dateToPath, String tempDir})?>
      generateDateStampAssets({
    required List<String> uniqueDates,
    required int videoHeight,
    required int sizePercent,
    required String baseTempDir,
    String? fontFamily,
  }) async {
    try {
      // Create temp directory for date stamp PNGs
      final tempDir = Directory(
          '$baseTempDir/date_stamps_${DateTime.now().millisecondsSinceEpoch}');
      await tempDir.create(recursive: true);

      final Map<String, String> dateToPath = {};

      for (int i = 0; i < uniqueDates.length; i++) {
        final dateText = uniqueDates[i];
        if (dateText.isEmpty) continue;

        // Create safe filename from date text
        final safeFilename = dateText
            .replaceAll(RegExp(r'[^\w\s-]'), '_')
            .replaceAll(RegExp(r'\s+'), '_');
        final outputPath = '${tempDir.path}/date_${i}_$safeFilename.png';

        final success = await renderDateStampPng(
          dateText: dateText,
          outputPath: outputPath,
          videoHeight: videoHeight,
          sizePercent: sizePercent,
          fontFamily: fontFamily,
        );

        if (success) {
          dateToPath[dateText] = outputPath;
        } else {
          LogService.instance.log("[DATE_STAMP] Failed to render: $dateText");
        }
      }

      LogService.instance.log(
        "[DATE_STAMP] Generated ${dateToPath.length}/${uniqueDates.length} date stamp PNGs",
      );

      return (dateToPath: dateToPath, tempDir: tempDir.path);
    } catch (e) {
      LogService.instance
          .log("[DATE_STAMP] generateDateStampAssets failed: $e");
      return null;
    }
  }
}
