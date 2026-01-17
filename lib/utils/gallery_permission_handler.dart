import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/log_service.dart';

/// Handles permission requests for gallery operations.
/// Consolidates duplicate permission code from gallery_page.dart and image_preview_navigator.dart.
class GalleryPermissionHandler {
  /// Requests permissions for accessing photos/media based on platform and SDK version.
  ///
  /// For Android SDK >= 33: Requests photos, videos, and audio permissions
  /// For Android SDK < 33: Requests storage permission
  /// For iOS: Requests photos permission with storage fallback
  ///
  /// Returns true if all required permissions are granted, false otherwise.
  /// If permission is permanently denied, opens app settings.
  static Future<bool> requestGalleryPermissions() async {
    if (Platform.isAndroid) {
      return _requestAndroidPermissions();
    } else if (Platform.isIOS) {
      return _requestiOSPermissions();
    }
    // Desktop platforms don't need special permissions
    return true;
  }

  /// Android-specific permission handling.
  /// Handles different SDK versions (33+ uses granular media permissions).
  static Future<bool> _requestAndroidPermissions() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      final int sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 33) {
        // Android 13+ uses granular media permissions
        PermissionStatus imagesStatus = await Permission.photos.request();
        PermissionStatus videosStatus = await Permission.videos.request();
        PermissionStatus audioStatus = await Permission.audio.request();

        if (imagesStatus.isGranted &&
            videosStatus.isGranted &&
            audioStatus.isGranted) {
          return true;
        }

        if (imagesStatus.isPermanentlyDenied ||
            videosStatus.isPermanentlyDenied ||
            audioStatus.isPermanentlyDenied) {
          await openAppSettings();
        }
        return false;
      } else {
        // Older Android versions use storage permission
        PermissionStatus storageStatus = await Permission.storage.request();
        if (storageStatus.isGranted) return true;
        if (storageStatus.isPermanentlyDenied) {
          await openAppSettings();
        }
        return false;
      }
    } catch (e) {
      LogService.instance.log('Error checking Android permissions: $e');
      return false;
    }
  }

  /// iOS-specific permission handling.
  /// Requests photos permission with storage fallback.
  static Future<bool> _requestiOSPermissions() async {
    try {
      PermissionStatus status = await Permission.photos.request();
      if (status.isGranted) {
        return true;
      } else if (status.isDenied) {
        // Try storage as fallback
        status = await Permission.storage.request();
        return status.isGranted;
      } else if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      return false;
    } catch (e) {
      LogService.instance.log('Error checking iOS permissions: $e');
      return false;
    }
  }

  /// Simple permission check without opening settings.
  /// Useful for checking permission status before attempting operations.
  static Future<bool> hasGalleryPermissions() async {
    if (Platform.isAndroid) {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      final int sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 33) {
        return await Permission.photos.isGranted &&
            await Permission.videos.isGranted;
      } else {
        return await Permission.storage.isGranted;
      }
    } else if (Platform.isIOS) {
      return await Permission.photos.isGranted;
    }
    return true;
  }
}
