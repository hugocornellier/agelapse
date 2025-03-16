import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' show join;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../utils/settings_utils.dart';
import '../utils/utils.dart';

import '../services/database_helper.dart';

class DirUtils {
  static const String photosRawDirname = 'photos_raw';
  static const String stabilizedDirname = 'stabilized';
  static const String stabilizedWIPDirname = 'stabilized_wip';
  static const String watermarkDirname = 'watermark';
  static const String thumbnailDirname = 'thumbnails';
  static const String failureDirname = 'failure';
  static const String testDirname = 'test';
  
  static Future<String> getProjectDirPath(int projectId) async =>
      join(await getAppDocumentsDirPath(), projectId.toString());

  static Future<String> getStabilizedDirPath(int projectId) async =>
      join(await getProjectDirPath(projectId), stabilizedDirname);

  static Future<String> getRawPhotoDirPath(int projectId) async =>
      join(await getProjectDirPath(projectId), photosRawDirname);

  static Future<String> getFailureDirPath(int projectId) async =>
      join(await getProjectDirPath(projectId), failureDirname);

  static Future<String> getWatermarkDirPath(int projectId) async =>
      join(await getProjectDirPath(projectId), watermarkDirname);

  static Future<String> getThumbnailDirPath(int projectId) async =>
      join(await getProjectDirPath(projectId), thumbnailDirname);

  static Future<String> getTestDirPath(int projectId) async =>
      join(await getProjectDirPath(projectId), testDirname);

  static Future<String> getExportsDirPath(int projectId) async =>
      join(await getProjectDirPath(projectId), 'exports');

  static Future<String> getRawPhotoPngDirPath() async =>
      join(await getTemporaryDirPath(), 'photos_raw_png');

  static Future<String> getStabilizedWIPDirPath() async =>
      join(await getTemporaryDirPath(), stabilizedWIPDirname);

  static Future<String> getPngPathFromRawPhotoPath(String rawPhotoPath) async =>
      join(await getRawPhotoPngDirPath(), '${path.basenameWithoutExtension(rawPhotoPath)}.png');

  static Future<String> getStabilizedWIPPathFromRawPhotoPath(String rawPhotoPath) async =>
      join(await getStabilizedWIPDirPath(), '${path.basenameWithoutExtension(rawPhotoPath)}.jpg');

  static Future<String> getVideoOutputPath(int projectId, String projectOrientation) async =>
      join(await getProjectDirPath(projectId), 'videos', projectOrientation, 'agelapse.mp4');

  static Future<String> getWatermarkFilePath(int projectId) async =>
      join(await getWatermarkDirPath(projectId), 'watermark.png');

  static Future<String> getZipFileExportPath(int projectId, String projectName) async =>
      path.join(await getExportsDirPath(projectId), "$projectName AgeLapse Export.zip");

  static Future<String> getRawPhotoPathFromTimestampAndProjectId(String timestamp, int projectId, {String? fileExtension}) async {
    fileExtension ??= await DB.instance.getPhotoExtensionByTimestampAndProjectId(timestamp, projectId);

    return join(
      await getRawPhotoDirPath(projectId),
      '$timestamp$fileExtension'
    );
  }

  static Future<String> getStabilizedImagePath(String rawImagePath, int projectId) async {
    return getStabilizedImagePathFromRawPathAndProjectOrientation(
      projectId,
      rawImagePath,
      await SettingsUtil.loadProjectOrientation(projectId.toString())
    );
  }

  static Future<String> getStabilizedDirPathFromProjectIdAndOrientation(
    int projectId,
    String projectOrientation
  ) async {
    return path.join(
      await getStabilizedDirPath(projectId),
      projectOrientation.toLowerCase()
    );
  }

  static Future<String> getStabilizedImagePathFromRawPathAndProjectOrientation(
    int projectId,
    String rawImagePath,
    String projectOrientation
  ) async {
    if (projectOrientation == 'portrait') {
      return getStabilizedPortraitImagePathFromRawPath(rawImagePath, projectId);
    } else {
      return getStabilizedLandscapeImagePathFromRawPath(rawImagePath, projectId);
    }
  }

  static Future<String> getStabilizedPortraitImagePathFromRawPath(String rawImagePath, int projectId) async {
    return path.join(
      await getStabilizedDirPath(projectId),
      'portrait',
      "${path.basenameWithoutExtension(rawImagePath)}.png"
    );
  }

  static Future<String> getStabilizedLandscapeImagePathFromRawPath(String rawImagePath, int projectId) async {
    return path.join(
      await getStabilizedDirPath(projectId),
      'landscape',
      "${path.basenameWithoutExtension(rawImagePath)}.png"
    );
  }
  
  // Cross-platform temp & permanent data directory path fetchers 
  static Future<String> getTemporaryDirPath() async => (await getTemporaryDirectory()).path;
  static Future<String> getAppDocumentsDirPath() async => (await getApplicationDocumentsDirectory()).path;

  static Future<List<File>> getAllFilesInRawPhotoDirByExtension(int projectId, String extension) async {
    try {
      final String rawPhotoDirectoryPath = await getRawPhotoDirPath(projectId);
      final Directory directory = Directory(rawPhotoDirectoryPath);
      final List<File> files = await directory.list()
          .where((entity) => entity is File && Utils.isImage(entity.path))
          .cast<File>()
          .toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      return files;
    } catch (e) {
      return [];
    }
  }

  static Future<List<File>> getAllJpgFilesInRawPhotoDir(int projectId) async =>
      await getAllFilesInRawPhotoDirByExtension(projectId, '.jpg');

  static Future<List<File>> getAllPngFilesInRawPhotoDir(int projectId) async =>
      await getAllFilesInRawPhotoDirByExtension(projectId, '.png');

  static Future<void> createDirectoryIfNotExists(String imagePath) async {
    final directory = Directory(path.dirname(imagePath));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  static Future<File?> getFileObjectFromFilepath(String filepath) async {
    try {
      final file = File(filepath);
      final bool fileExists = await file.exists();
      return fileExists ? file : null;
    } catch (e) {
      debugPrint("Failed to load image: $e");
    }
    return null;
  }

  static Future<void> tryDeleteFiles(List<String> filepathList) async {
    for (String filepath in filepathList) {
      await deleteFileIfExists(filepath);
    }
  }

  static Future<void> deleteFileIfExists(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // print('An error occurred while deleting the file: $e');
    }
  }

  static Future<void> deleteDirectoryContents(Directory directory) async {
    if (await directory.exists()) {
      await for (var entity in directory.list(recursive: false)) {
        if (entity is File) {
          await entity.delete();
        } else if (entity is Directory) {
          await deleteDirectoryContents(entity);
          await entity.delete(recursive: true);
        }
      }
    }
  }

  static deleteAllThumbnails(int projectId, String projectOrientation) async {
    final String stabilizedDirPath = await DirUtils.getStabilizedDirPath(projectId);
    final String thumbnailDir = join(
        stabilizedDirPath,
        projectOrientation,
        DirUtils.thumbnailDirname,
        "thumbnail.jpg"
    );

    final bool isValidDirectory = await _isValidDirectory(thumbnailDir);
    if (isValidDirectory) {
      await deleteDirectory(thumbnailDir);
    } else {
      print('Directory does not exist or is not a valid directory.');
    }
  }

  static Future<bool> _isValidDirectory(String path) async {
    final dir = Directory(path);
    return await dir.exists();
  }

  static Future<void> deleteDirectory(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  static Future<String> getGuideImagePath(int projectId, Map<String, Object?>? guidePhoto) async {
    if (guidePhoto == null) {
      return "";
    }

    final List<Future<String>> futures = [
      DirUtils.getStabilizedDirPath(projectId),
      SettingsUtil.loadProjectOrientation(projectId.toString())
    ];

    final List<String> results = await Future.wait(futures);

    final String directoryPath = results[0];
    final String projectOrientation = results[1];
    final String stabDirPath = path.join(directoryPath, projectOrientation);
    final String guideImagePath = path.join(stabDirPath, "${guidePhoto['timestamp']}.png");

    return guideImagePath;
  }

  static Future<Map<String, Object?>?> getGuidePhoto(double offsetX, int projectId) async {
    List<Map<String, Object?>> validGuidePhotos = await DB.instance.getSetEyePhoto(
      offsetX,
      projectId
    );

    if (validGuidePhotos.isEmpty) {
      return null;
    }

    return validGuidePhotos.first;
  }
}
