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
    final start = DateTime.fromMillisecondsSinceEpoch(startDate);
    final end = DateTime.fromMillisecondsSinceEpoch(endDate);
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
    Set<String> uniqueDates = {};

    for (var photo in photos) {
      DateTime dateFromTimestamp = _getDateTimeFromTimestamp(photo['timestamp']).toLocal();
      DateTime yearMonthDayOnly = DateTime(dateFromTimestamp.year, dateFromTimestamp.month, dateFromTimestamp.day);
      uniqueDates.add(yearMonthDayOnly.toString());
    }

    return uniqueDates.toList();
  }

  static int _calculatePhotoStreak(List<Map<String, dynamic>> photos) {
    List<String> uniqueDates = getUniquePhotoDates(photos);
    int streak = 1;

    final DateTime latestPhotoDateTime = DateTime.parse(uniqueDates[0]);
    final DateTime currentDateTime = DateTime.now();
    final int timeDiff = getTimeDiff(latestPhotoDateTime, currentDateTime);

    if (timeDiff > 1) return 0;

    for (int i = 1; i < uniqueDates.length; i++) {
      final DateTime currentIterationDate = DateTime.parse(uniqueDates[i]);
      final DateTime previousIterationDate = DateTime.parse(uniqueDates[i - 1]);

      final int timeDiff = getTimeDiff(currentIterationDate, previousIterationDate);

      if (timeDiff != 1) {
        return streak;
      }

      streak++;
    }

    return streak;
  }

  static DateTime _getDateTimeFromTimestamp(String? timestamp) =>
      DateTime.fromMillisecondsSinceEpoch(int.tryParse(timestamp ?? '0') ?? 0);

  static Future<ui.Image> loadImageData(String imagePath) async {
    final data = await rootBundle.load(imagePath);
    final bytes = data.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }
}