import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;

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

  static String formatUnixTimestamp2(int timestamp) {
    DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    DateTime now = DateTime.now();

    String formattedTime = DateFormat('h:mm a').format(date);
    String formattedDate;

    if (date.year == now.year) {
      formattedDate = DateFormat('MMMM d').format(date);
    } else {
      formattedDate = DateFormat('MMMM d y').format(date);
    }

    return '$formattedDate, $formattedTime';
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
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => screen));

  static void navigateToScreenReplaceNoAnim(BuildContext context, Widget screen) {
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

    var validExtensions = {".heic", ".heif", ".jpg", ".jpeg", ".jfif", ".pjpeg",
      ".pjp", ".png", ".apng", ".tiff", ".bmp", ".webp", ".avif"};
    if (validExtensions.contains(extension)) return true;

    final String? mimeType = lookupMimeType(filepath);
    if (mimeType != null) {
      return mimeType.startsWith('image/');
    }

    return false;
  }

  static Future<bool> showConfirmChangeDialog(BuildContext context, String toChange) async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Change'),
          content: Text(
            'Are you sure you want to change the $toChange? '
            'This will require re-stabilizing all photos.'
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(false); // User chose to cancel
              },
            ),
            TextButton(
              child: const Text('Proceed'),
              onPressed: () {
                Navigator.of(context).pop(true); // User chose to proceed
              },
            ),
          ],
        );
      },
    ) ?? false;
  }
}
