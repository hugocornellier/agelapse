import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'capture_timezone.dart';

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

  static Future<bool> showConfirmChangeDialog(
    BuildContext context,
    String toChange,
  ) async {
    const dangerColor = Color(0xFFDC2626);
    const dangerColorLight = Color(0x26DC2626);
    const dangerColorBorder = Color(0x4DDC2626);
    const cardBackground = Color(0xFF1C1C1E);
    const textPrimary = Color(0xFFF5F5F7);
    const textSecondary = Color(0xFF8E8E93);

    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: cardBackground,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: dangerColorLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: dangerColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Are you sure?',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You are about to change the $toChange.',
                    style: const TextStyle(
                      color: textSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: dangerColorLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: dangerColorBorder, width: 1),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          color: dangerColor,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This will re-stabilize all photos.\nThis action cannot be undone.',
                            style: TextStyle(
                              color: dangerColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: dangerColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Proceed Anyway',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }
}
