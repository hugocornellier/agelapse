import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'capture_timezone.dart';
import '../widgets/confirm_action_dialog.dart';

class Utils {
  static bool? parseBoolean(String? input) {
    if (input == null) return null;
    String lowerCaseInput = input.toLowerCase();
    if (lowerCaseInput == "true") return true;
    if (lowerCaseInput == "false") return false;
    return null;
  }

  static String formatUnixTimestamp(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final daySuffix = (int day) {
      if (day >= 11 && day <= 13) {
        return 'th';
      }
      switch (day % 10) {
        case 1:
          return 'st';
        case 2:
          return 'nd';
        case 3:
          return 'rd';
        default:
          return 'th';
      }
    }(dateTime.day);

    final formattedDate = DateFormat("MMM d'$daySuffix' y").format(dateTime);
    return formattedDate;
  }

  static String formatUnixTimestampPlatformAware(
    int timestamp, {
    int? captureOffsetMinutes,
  }) {
    final wall = CaptureTimezone.toLocalDateTime(
      timestamp,
      offsetMinutes: captureOffsetMinutes,
    );
    final pattern = (Platform.isAndroid || Platform.isIOS)
        ? 'MMM d yyyy h:mm a'
        : 'MMMM d yyyy h:mm a';
    final fmt = DateFormat(pattern);
    final tzLabel = CaptureTimezone.formatOffsetLabel(
      captureOffsetMinutes,
      fallbackDateTime: wall,
    );
    return '${fmt.format(wall)} $tzLabel';
  }

  static String formatUnixTimestamp2(
    int timestamp, {
    int? captureOffsetMinutes,
  }) {
    final DateTime localLike = CaptureTimezone.toLocalDateTime(
      timestamp,
      offsetMinutes: captureOffsetMinutes,
    );
    final DateTime nowRef = DateTime.now();
    final String formattedTime = DateFormat('h:mm a').format(localLike);
    final String formattedDate = localLike.year == nowRef.year
        ? DateFormat('MMMM d').format(localLike)
        : DateFormat('MMMM d y').format(localLike);
    final String tzLabel = CaptureTimezone.formatOffsetLabel(
      captureOffsetMinutes,
      fallbackDateTime: localLike,
    );
    return '$formattedDate, $formattedTime ($tzLabel)';
  }

  static void navigateToScreen(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  static void navigateToScreenNoAnim(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation1, animation2) => screen,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  static void navigateToScreenReplace(BuildContext context, Widget screen) =>
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => screen),
      );

  static void navigateToScreenReplaceNoAnim(
    BuildContext context,
    Widget screen,
  ) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation1, animation2) => screen,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  static void navigateBack(BuildContext context) => Navigator.pop(context);

  static String capitalizeFirstLetter(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1);
  }

  static bool isImage(String filepath) {
    final String extension = path.extension(filepath).toLowerCase();
    if (extension == ".pdf") return false;

    var validExtensions = {
      ".heic",
      ".heif",
      ".jpg",
      ".jpeg",
      ".jfif",
      ".pjpeg",
      ".pjp",
      ".png",
      ".apng",
      ".tiff",
      ".bmp",
      ".webp",
      ".avif",
    };
    if (validExtensions.contains(extension)) return true;

    final String? mimeType = lookupMimeType(filepath);
    if (mimeType != null) {
      return mimeType.startsWith('image/');
    }

    return false;
  }

  /// Shows a confirmation dialog for settings that require re-stabilization.
  ///
  /// This is a backwards-compatible wrapper around [ConfirmActionDialog.showReStabilization].
  static Future<bool> showConfirmChangeDialog(
    BuildContext context,
    String toChange,
  ) async {
    return ConfirmActionDialog.showReStabilization(context, toChange);
  }
}
