import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'dart:ui' as ui;

import '../services/database_helper.dart';
import 'dir_utils.dart';

class ProjectUtils {
  static Future<int?> calculateStreak(int projectId) async {
    final photos = await DB.instance.getPhotosByProjectIDNewestFirst(projectId);
    if (photos.isEmpty) return 0;
    return _calculatePhotoStreak(photos);
  }

  static String convertExtensionToPng(String path) => path.replaceAll(RegExp(r'\.jpg$'), '.png');

  static int getTimeDiff(DateTime startTime, DateTime endTime) => endTime.difference(startTime).inDays;

  static int parseTimestampFromFilename(String filepath) => int.tryParse(path.basenameWithoutExtension(filepath)) ?? 0;

  static Future<bool> isDefaultProject(int projectId) async {
    final data = await DB.instance.getSettingByTitle('default_project');
    final defaultProject = data?['value'];

    if (defaultProject == null || defaultProject == "none") {
      return false;
    } else {
      return int.tryParse(defaultProject) == projectId;
    }
  }

  static Future<void> deleteFile(File file) async => await file.delete();

  static Future<bool> deleteImage(File image, int projectId) async {
    try {
      await deletePngFileIfExists(image);
      await deleteStabilizedFileIfExists(image, projectId);
      await deleteFile(image);
      await deletePhotoFromDatabase(image.path);
      return true;
    } catch (e) {
      print("Failed to delete image: ${image.path}, Error: $e");
      return false;
    }
  }

  static Future<void> deletePngFileIfExists(File image) async {
    if (image.path.endsWith('.jpg')) {
      String newPath = convertExtensionToPng(image.path);

      File newImage = File(newPath);
      if (await newImage.exists()) {
        await deleteFile(newImage);
      }
    }
  }

  static Future<ui.Image> loadImage(String assetPath) async {
    final ByteData data = await rootBundle.load(assetPath);
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(data.buffer.asUint8List(), (ui.Image img) {
      completer.complete(img);
    });
    return completer.future;
  }

  static Duration calculateDateDifference(int startDate, int endDate) {
    final start = DateTime.fromMillisecondsSinceEpoch(startDate, isUtc: true);
    final end = DateTime.fromMillisecondsSinceEpoch(endDate, isUtc: true);
    return end.difference(start);
  }

  static Future<void> deleteStabilizedFileIfExists(File image, int projectId) async {
    final String stabilizedDirPath = await DirUtils.getStabilizedDirPath(projectId);
    final String stabilizedPngPath = "${path.basenameWithoutExtension(image.path)}.png";

    final String stabilizedImagePathPngPortrait = path.join(
      stabilizedDirPath,
      'portrait',
      stabilizedPngPath
    );
    final String stabilizedImagePathPngLandscape = path.join(
      stabilizedDirPath,
      'landscape',
      stabilizedPngPath
    );

    final File stabilizedImagePngPortrait = File(stabilizedImagePathPngPortrait);
    final File stabilizedImagePngLandscape = File(stabilizedImagePathPngLandscape);

    if (await stabilizedImagePngPortrait.exists()) await deleteFile(stabilizedImagePngPortrait);
    if (await stabilizedImagePngLandscape.exists()) await deleteFile(stabilizedImagePngLandscape);
  }

  static Future<void> deletePhotoFromDatabase(String path) async {
    final timestamp = parseTimestampFromFilename(path);
    await DB.instance.deletePhoto(timestamp);
  }

  static List<String> getUniquePhotoDates(List<Map<String, dynamic>> photos) {
    final Set<DateTime> uniqueDays = {};

    for (var photo in photos) {
      final int ts = int.tryParse(photo['timestamp'] ?? '0') ?? 0;
      final DateTime utc = DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
      final int? offsetMin = photo['captureOffsetMinutes'] is int ? photo['captureOffsetMinutes'] as int : null;
      final DateTime localLike = offsetMin != null ? utc.add(Duration(minutes: offsetMin)) : utc.toLocal();
      final DateTime dayOnly = DateTime(localLike.year, localLike.month, localLike.day);
      uniqueDays.add(dayOnly);
    }

    final List<DateTime> days = uniqueDays.toList()..sort((a, b) => b.compareTo(a));
    return days.map((d) => d.toString()).toList();
  }

  static int _calculatePhotoStreak(List<Map<String, dynamic>> photos) {
    final List<String> uniqueDates = getUniquePhotoDates(photos);
    if (uniqueDates.isEmpty) return 0;

    int streak = 1;

    final DateTime latestPhotoDate = DateTime.parse(uniqueDates[0]);

    int? latestOffset;
    for (final p in photos) {
      final int ts = int.tryParse(p['timestamp'] ?? '0') ?? 0;
      final DateTime utc = DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
      final int? off = p['captureOffsetMinutes'] is int ? p['captureOffsetMinutes'] as int : null;
      final DateTime captureLocal = off != null ? utc.add(Duration(minutes: off)) : utc.toLocal();
      final DateTime capDay = DateTime(captureLocal.year, captureLocal.month, captureLocal.day);
      if (capDay.year == latestPhotoDate.year && capDay.month == latestPhotoDate.month && capDay.day == latestPhotoDate.day) {
        latestOffset = off;
        break;
      }
    }

    DateTime nowRef;
    if (latestOffset != null) {
      final DateTime nowUtc = DateTime.now().toUtc();
      nowRef = nowUtc.add(Duration(minutes: latestOffset));
    } else {
      nowRef = DateTime.now();
    }
    final DateTime todayLocalLike = DateTime(nowRef.year, nowRef.month, nowRef.day);

    final int headDiff = getTimeDiff(latestPhotoDate, todayLocalLike);
    if (headDiff > 1) return 0;

    for (int i = 1; i < uniqueDates.length; i++) {
      final DateTime currentDate = DateTime.parse(uniqueDates[i]);
      final DateTime previousDate = DateTime.parse(uniqueDates[i - 1]);

      final int diff = getTimeDiff(currentDate, previousDate);
      if (diff != 1) {
        return streak;
      }
      streak++;
    }

    return streak;
  }

  static DateTime _getDateTimeFromTimestamp(String? timestamp) =>
      DateTime.fromMillisecondsSinceEpoch(int.tryParse(timestamp ?? '0') ?? 0, isUtc: true);

  static Future<ui.Image> loadImageData(String imagePath) async {
    final data = await rootBundle.load(imagePath);
    final bytes = data.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }
}