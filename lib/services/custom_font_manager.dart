import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../utils/dir_utils.dart';
import 'database_helper.dart';
import 'log_service.dart';

// Re-export CustomFont from database_helper for convenience
export 'database_helper.dart' show CustomFont;

/// Result of font validation.
class FontValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String? suggestedName;

  const FontValidationResult({
    required this.isValid,
    this.errorMessage,
    this.suggestedName,
  });

  factory FontValidationResult.valid(String suggestedName) =>
      FontValidationResult(isValid: true, suggestedName: suggestedName);

  factory FontValidationResult.invalid(String error) =>
      FontValidationResult(isValid: false, errorMessage: error);
}

/// Manages custom font installation, loading, and lifecycle.
/// Handles cross-platform font loading using Flutter's FontLoader API.
class CustomFontManager {
  static final CustomFontManager _instance = CustomFontManager._internal();
  static CustomFontManager get instance => _instance;

  CustomFontManager._internal();

  /// Set of font family names that have been loaded into the engine.
  /// Used to prevent duplicate loading attempts.
  final Set<String> _loadedFonts = {};

  /// Cache of installed custom fonts.
  List<CustomFont>? _cachedFonts;

  /// Whether initialization has been completed.
  bool _initialized = false;

  /// Supported font file extensions.
  static const List<String> supportedExtensions = ['.ttf', '.otf'];

  /// Maximum allowed font file size (10 MB).
  static const int maxFileSizeBytes = 10 * 1024 * 1024;

  /// Prefix for custom font family names to avoid collisions.
  static const String customFontPrefix = 'CustomFont_';

  /// Marker value for "Custom" in settings (triggers file picker).
  static const String customFontMarker = '_custom_font';

  /// Directory name for storing custom fonts.
  static const String fontsDirName = 'custom_fonts';

  /// Initialize the custom font manager.
  /// Should be called early in app startup, after database initialization.
  /// Loads all previously installed custom fonts into the Flutter engine.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      LogService.instance.log('[CUSTOM_FONT] Initializing CustomFontManager');

      // Ensure the custom fonts directory exists
      await _ensureFontsDirectory();

      // Verify all fonts are still valid and clean up orphaned entries
      await verifyInstalledFonts();

      // Load all installed custom fonts from database
      final fonts = await getAllCustomFonts();

      // Load each font into the Flutter engine
      int successCount = 0;
      for (final font in fonts) {
        final success = await _loadFontIntoEngine(font);
        if (success) successCount++;
      }

      _initialized = true;
      LogService.instance.log(
        '[CUSTOM_FONT] Initialized: $successCount/${fonts.length} custom fonts loaded',
      );
    } catch (e) {
      LogService.instance.log('[CUSTOM_FONT] Initialization error: $e');
      _initialized = true; // Mark as initialized even on error to prevent loops
    }
  }

  /// Get the directory path for storing custom fonts.
  Future<String> _getFontsDirectoryPath() async {
    final appDir = await DirUtils.getAppDocumentsDirPath();
    return path.join(appDir, fontsDirName);
  }

  /// Ensure the custom fonts directory exists.
  Future<Directory> _ensureFontsDirectory() async {
    final dirPath = await _getFontsDirectoryPath();
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Validate a font file before installation.
  /// Returns validation result with error message or suggested name.
  Future<FontValidationResult> validateFontFile(String filePath) async {
    try {
      final file = File(filePath);

      // Check if file exists
      if (!await file.exists()) {
        return FontValidationResult.invalid('Font file not found');
      }

      // Check file extension
      final extension = path.extension(filePath).toLowerCase();
      if (!supportedExtensions.contains(extension)) {
        return FontValidationResult.invalid(
          'Unsupported format. Use TTF or OTF files.',
        );
      }

      // Check file size
      final fileSize = await file.length();
      if (fileSize > maxFileSizeBytes) {
        final sizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(1);
        return FontValidationResult.invalid(
          'File too large ($sizeMB MB). Maximum is 10 MB.',
        );
      }

      if (fileSize < 100) {
        return FontValidationResult.invalid(
            'File appears to be empty or corrupt');
      }

      // Try to load the font to validate it's a real font file
      final bytes = await file.readAsBytes();
      final validationResult = await _validateFontBytes(bytes);
      if (!validationResult.isValid) {
        return validationResult;
      }

      // Generate suggested name from filename
      final filename = path.basenameWithoutExtension(filePath);
      final suggestedName = _sanitizeDisplayName(filename);

      return FontValidationResult.valid(suggestedName);
    } catch (e) {
      LogService.instance.log('[CUSTOM_FONT] Validation error: $e');
      return FontValidationResult.invalid('Failed to validate font: $e');
    }
  }

  /// Validate font bytes by attempting to load them.
  Future<FontValidationResult> _validateFontBytes(Uint8List bytes) async {
    try {
      // Check for TTF/OTF magic bytes
      if (bytes.length < 4) {
        return FontValidationResult.invalid(
            'File too small to be a valid font');
      }

      // TTF starts with: 00 01 00 00 or 'true' (74 72 75 65)
      // OTF starts with: 'OTTO' (4F 54 54 4F)
      // TTC starts with: 'ttcf' (74 74 63 66)
      final isTTF = (bytes[0] == 0x00 &&
              bytes[1] == 0x01 &&
              bytes[2] == 0x00 &&
              bytes[3] == 0x00) ||
          (bytes[0] == 0x74 &&
              bytes[1] == 0x72 &&
              bytes[2] == 0x75 &&
              bytes[3] == 0x65);
      final isOTF = bytes[0] == 0x4F &&
          bytes[1] == 0x54 &&
          bytes[2] == 0x54 &&
          bytes[3] == 0x4F;
      final isTTC = bytes[0] == 0x74 &&
          bytes[1] == 0x74 &&
          bytes[2] == 0x63 &&
          bytes[3] == 0x66;

      if (!isTTF && !isOTF && !isTTC) {
        return FontValidationResult.invalid(
          'Invalid font file. Must be a valid TTF or OTF font.',
        );
      }

      // Try to actually load the font using FontLoader to verify it's usable
      // We use a temporary name for validation
      final testFamilyName =
          '_validation_test_${DateTime.now().millisecondsSinceEpoch}';
      final fontLoader = FontLoader(testFamilyName);
      fontLoader.addFont(Future.value(ByteData.view(bytes.buffer)));

      try {
        await fontLoader.load();
      } catch (e) {
        return FontValidationResult.invalid(
          'Font file is corrupt or unsupported',
        );
      }

      return FontValidationResult.valid('');
    } catch (e) {
      return FontValidationResult.invalid('Failed to validate font data');
    }
  }

  /// Sanitize a display name for the font.
  String _sanitizeDisplayName(String name) {
    // Remove common suffixes
    var cleaned = name
        .replaceAll(
            RegExp(
                r'[-_]?(Regular|Bold|Italic|Medium|Light|Thin|Black|SemiBold|ExtraBold|ExtraLight)$',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'[-_]+'), ' ')
        .trim();

    // Capitalize first letter of each word
    cleaned = cleaned.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');

    // Limit length
    if (cleaned.length > 30) {
      cleaned = cleaned.substring(0, 30).trim();
    }

    return cleaned.isEmpty ? 'Custom Font' : cleaned;
  }

  /// Install a custom font from a file path.
  /// Returns the installed CustomFont or throws an exception.
  Future<CustomFont> installFont(String sourcePath, String displayName) async {
    LogService.instance
        .log('[CUSTOM_FONT] Installing font: $displayName from $sourcePath');

    // Validate the font file
    final validation = await validateFontFile(sourcePath);
    if (!validation.isValid) {
      throw Exception(validation.errorMessage);
    }

    // Check if a font with this name already exists
    final existing = await getCustomFontByDisplayName(displayName);
    if (existing != null) {
      throw Exception('A font named "$displayName" already exists');
    }

    // Generate unique family name for Flutter engine
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final familyName = '$customFontPrefix$timestamp';

    // Copy font file to app storage
    final fontsDir = await _ensureFontsDirectory();
    final extension = path.extension(sourcePath).toLowerCase();
    final destFileName = '$familyName$extension';
    final destPath = path.join(fontsDir.path, destFileName);

    final sourceFile = File(sourcePath);
    await sourceFile.copy(destPath);

    // Get file size
    final destFile = File(destPath);
    final fileSize = await destFile.length();

    // Add to database
    final fontId = await DB.instance.addCustomFont(
      displayName: displayName,
      familyName: familyName,
      filePath: destPath,
      fileSize: fileSize,
    );

    final font = CustomFont(
      id: fontId,
      displayName: displayName,
      familyName: familyName,
      filePath: destPath,
      fileSize: fileSize,
      installedAt: timestamp,
    );

    // Load into Flutter engine
    await _loadFontIntoEngine(font);

    // Invalidate cache
    _cachedFonts = null;

    LogService.instance.log('[CUSTOM_FONT] Installed font: $font');
    return font;
  }

  /// Load a custom font into the Flutter engine.
  Future<bool> _loadFontIntoEngine(CustomFont font) async {
    if (_loadedFonts.contains(font.familyName)) {
      return true; // Already loaded
    }

    try {
      final file = File(font.filePath);
      if (!await file.exists()) {
        LogService.instance.log(
          '[CUSTOM_FONT] Font file missing: ${font.filePath}',
        );
        return false;
      }

      final bytes = await file.readAsBytes();
      final fontLoader = FontLoader(font.familyName);
      fontLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await fontLoader.load();

      _loadedFonts.add(font.familyName);
      LogService.instance.log(
        '[CUSTOM_FONT] Loaded font into engine: ${font.familyName}',
      );
      return true;
    } catch (e) {
      LogService.instance.log(
        '[CUSTOM_FONT] Failed to load font ${font.familyName}: $e',
      );
      return false;
    }
  }

  /// Get all installed custom fonts.
  Future<List<CustomFont>> getAllCustomFonts() async {
    if (_cachedFonts != null) {
      return _cachedFonts!;
    }

    final fonts = await DB.instance.getAllCustomFonts();
    _cachedFonts = fonts;
    return fonts;
  }

  /// Get a custom font by its display name.
  Future<CustomFont?> getCustomFontByDisplayName(String displayName) async {
    final fonts = await getAllCustomFonts();
    try {
      return fonts.firstWhere((f) => f.displayName == displayName);
    } catch (_) {
      return null;
    }
  }

  /// Get a custom font by its family name.
  Future<CustomFont?> getCustomFontByFamilyName(String familyName) async {
    final fonts = await getAllCustomFonts();
    try {
      return fonts.firstWhere((f) => f.familyName == familyName);
    } catch (_) {
      return null;
    }
  }

  /// Check if a family name is a custom font.
  bool isCustomFont(String familyName) {
    return familyName.startsWith(customFontPrefix);
  }

  /// Get the display name for a font family name.
  /// Returns the display name for custom fonts, or the family name itself for bundled fonts.
  Future<String> getDisplayNameForFamily(String familyName) async {
    if (!isCustomFont(familyName)) {
      return familyName;
    }

    final font = await getCustomFontByFamilyName(familyName);
    return font?.displayName ?? familyName;
  }

  /// Uninstall a custom font.
  Future<void> uninstallFont(CustomFont font) async {
    LogService.instance
        .log('[CUSTOM_FONT] Uninstalling font: ${font.displayName}');

    // Delete from database
    await DB.instance.deleteCustomFont(font.id);

    // Delete font file
    try {
      final file = File(font.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      LogService.instance.log('[CUSTOM_FONT] Failed to delete font file: $e');
    }

    // Remove from loaded set (font will remain in engine until app restart)
    _loadedFonts.remove(font.familyName);

    // Invalidate cache
    _cachedFonts = null;

    LogService.instance
        .log('[CUSTOM_FONT] Uninstalled font: ${font.displayName}');
  }

  /// Check if a font is available (loaded into the engine).
  Future<bool> isFontAvailable(String familyName) async {
    if (!isCustomFont(familyName)) {
      return true; // Bundled fonts are always available
    }

    // Check if already loaded
    if (_loadedFonts.contains(familyName)) {
      return true;
    }

    // Try to load it
    final font = await getCustomFontByFamilyName(familyName);
    if (font == null) {
      return false;
    }

    return await _loadFontIntoEngine(font);
  }

  /// Get the fallback font family to use if a custom font is unavailable.
  String getFallbackFont() {
    return 'Inter'; // Default bundled font
  }

  /// Resolve a font family name, ensuring it's available.
  /// Returns the font family if available, or the fallback font.
  Future<String> resolveFontFamily(String familyName) async {
    if (await isFontAvailable(familyName)) {
      return familyName;
    }
    LogService.instance.log(
      '[CUSTOM_FONT] Font unavailable, using fallback: $familyName',
    );
    return getFallbackFont();
  }

  /// Verify all installed fonts are still valid.
  /// Removes entries for fonts whose files are missing.
  Future<void> verifyInstalledFonts() async {
    final fonts = await getAllCustomFonts();
    for (final font in fonts) {
      final file = File(font.filePath);
      if (!await file.exists()) {
        LogService.instance.log(
          '[CUSTOM_FONT] Removing orphaned font entry: ${font.displayName}',
        );
        await DB.instance.deleteCustomFont(font.id);
      }
    }
    _cachedFonts = null;
  }

  /// Get the total storage used by custom fonts.
  Future<int> getTotalStorageUsed() async {
    final fonts = await getAllCustomFonts();
    return fonts.fold<int>(0, (sum, font) => sum + font.fileSize);
  }

  /// Clear all custom fonts.
  Future<void> clearAllFonts() async {
    final fonts = await getAllCustomFonts();
    for (final font in fonts) {
      await uninstallFont(font);
    }
  }
}
