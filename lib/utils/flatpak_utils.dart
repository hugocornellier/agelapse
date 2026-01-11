import 'dart:io';

/// Utilities for detecting and handling Flatpak sandbox environment.
/// Provides runtime detection without requiring compile-time flags.
///
/// This utility enables the app to work seamlessly in both traditional
/// .deb installations and Flatpak sandboxed environments.
class FlatpakUtils {
  static bool? _isFlatpak;
  static String? _realUserHome;

  /// Returns true if running inside a Flatpak sandbox.
  /// Detection is cached after first call for performance.
  ///
  /// Detection methods (in order of reliability):
  /// 1. FLATPAK_ID environment variable (most reliable, set by Flatpak runtime)
  /// 2. /.flatpak-info file existence (fallback for edge cases)
  static bool get isFlatpak {
    if (_isFlatpak != null) return _isFlatpak!;

    // Only relevant on Linux
    if (!Platform.isLinux) {
      _isFlatpak = false;
      return false;
    }

    // Method 1: Check FLATPAK_ID env var (set by Flatpak runtime)
    final flatpakId = Platform.environment['FLATPAK_ID'];
    if (flatpakId != null && flatpakId.isNotEmpty) {
      _isFlatpak = true;
      return true;
    }

    // Method 2: Check for /.flatpak-info file (created by Flatpak)
    try {
      if (File('/.flatpak-info').existsSync()) {
        _isFlatpak = true;
        return true;
      }
    } catch (_) {
      // Ignore permission errors - if we can't read it, we're probably not in Flatpak
    }

    _isFlatpak = false;
    return false;
  }

  /// Returns the Flatpak app ID if running in Flatpak, null otherwise.
  /// Example: `com.hugocornellier.agelapse`
  static String? get flatpakAppId {
    if (!isFlatpak) return null;
    return Platform.environment['FLATPAK_ID'];
  }

  /// Returns the real user home directory, even inside Flatpak sandbox.
  ///
  /// In Flatpak, `$HOME` points to `~/.var/app/{app-id}`, but for some operations
  /// we need to know the real home directory (e.g., ~/Downloads access via portal).
  ///
  /// Returns null if unable to determine the real home.
  static String? get realUserHome {
    if (_realUserHome != null) return _realUserHome;

    if (!isFlatpak) {
      _realUserHome = Platform.environment['HOME'];
      return _realUserHome;
    }

    // In Flatpak, try to derive real home from XDG paths
    // XDG_CONFIG_HOME is typically ~/.var/app/<app-id>/config
    // Real home is the path before .var/app/
    final xdgConfig = Platform.environment['XDG_CONFIG_HOME'];
    if (xdgConfig != null && xdgConfig.contains('.var/app/')) {
      final parts = xdgConfig.split('.var/app/');
      if (parts.isNotEmpty && parts[0].isNotEmpty) {
        _realUserHome = parts[0].endsWith('/')
            ? parts[0].substring(0, parts[0].length - 1)
            : parts[0];
        return _realUserHome;
      }
    }

    // Fallback: try HOST_XDG_DATA_HOME (sometimes available)
    final hostData = Platform.environment['HOST_XDG_DATA_HOME'];
    if (hostData != null) {
      // Usually /home/user/.local/share -> extract /home/user
      final idx = hostData.indexOf('/.local/share');
      if (idx > 0) {
        _realUserHome = hostData.substring(0, idx);
        return _realUserHome;
      }
    }

    // Last resort: parse sandboxed HOME to extract username pattern
    final sandboxedHome = Platform.environment['HOME'];
    if (sandboxedHome != null && sandboxedHome.contains('.var/app/')) {
      final parts = sandboxedHome.split('.var/app/');
      if (parts.isNotEmpty && parts[0].isNotEmpty) {
        _realUserHome = parts[0].endsWith('/')
            ? parts[0].substring(0, parts[0].length - 1)
            : parts[0];
        return _realUserHome;
      }
    }

    return null;
  }

  /// Checks if a specific Flatpak permission is likely available.
  /// This is a heuristic based on common permission patterns.
  ///
  /// Note: This cannot definitively check permissions - it's for logging/debugging.
  static bool hasLikelyPermission(String permission) {
    if (!isFlatpak) return true; // Non-Flatpak has all permissions

    // Check environment hints that suggest permissions
    switch (permission) {
      case 'filesystem':
        // If we can see real home, we likely have filesystem access
        return realUserHome != null;
      case 'network':
        // Network is usually granted; check for network namespace
        return true;
      case 'device':
        // Can't easily check without trying to access devices
        return true;
      default:
        return true;
    }
  }

  /// Returns the appropriate Downloads directory path.
  /// Handles both Flatpak (with xdg-download portal) and traditional installs.
  ///
  /// In Flatpak with --filesystem=xdg-download:rw, the portal transparently
  /// maps ~/Downloads to the real user's Downloads folder.
  static String? getDownloadsPath() {
    // Check XDG_DOWNLOAD_DIR first (respects user config and portals)
    final xdgDownload = Platform.environment['XDG_DOWNLOAD_DIR'];
    if (xdgDownload != null && xdgDownload.isNotEmpty) {
      return xdgDownload;
    }

    // Construct from HOME - works for both Flatpak (via portal) and native
    final home = Platform.environment['HOME'];
    if (home != null) {
      return '$home/Downloads';
    }

    return null;
  }
}
