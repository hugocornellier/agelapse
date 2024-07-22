import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:agelapse/utils/settings_utils.dart';
import 'package:agelapse/utils/utils.dart';
import 'package:archive/archive_io.dart';
import 'package:async_zip/async_zip.dart';
import 'package:camera/camera.dart';
import 'package:exif/exif.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';

import '../services/database_helper.dart';
import '../services/image_processor.dart';
import 'camera_utils.dart';
import 'dir_utils.dart';

class GalleryUtils {
  static var fileList = [];

  static Future<void> convertAvifToPng(String avifFilePath, String pngFilePath) async {
    try {
      final avifBytes = await File(avifFilePath).readAsBytes();
      final codec = await instantiateImageCodec(avifBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final pngBytes = await image.toByteData(format: ImageByteFormat.png);

      if (pngBytes != null) {
        final pngFile = File(pngFilePath);
        await pngFile.writeAsBytes(pngBytes.buffer.asUint8List());
      } else {
        throw Exception('Failed to convert AVIF to PNG');
      }
    } catch (e) {
      //print('Error converting AVIF to PNG: $e');
    }
  }

  static Duration? parseOffset(String offsetStr) {
    try {
      final bool isNegative = offsetStr.startsWith('-');
      final List<String> parts = offsetStr.substring(1).split(':');
      if (parts.length != 2) return null;
      int hours = int.parse(parts[0]);
      int minutes = int.parse(parts[1]);
      Duration offset = Duration(hours: hours, minutes: minutes);
      if (isNegative) {
        offset = -offset;
      }
      return offset;
    } catch (e) {
      print('Failed to parse offset: $e');
      return null;
    }
  }

  static Future<(bool, int?)> parseExifDate(Map<String, IfdTag> exifData) async {
    try {
      final String? dateTimeOriginalStr = exifData['EXIF DateTimeOriginal']?.toString();
      if (dateTimeOriginalStr == null) return (true, null);

      final String? offsetTimeStr = exifData['EXIF OffsetTime']?.toString();
      DateTime dateTime = DateFormat("yyyy:MM:dd HH:mm:ss").parse(dateTimeOriginalStr, true);

      if (offsetTimeStr != null) {
        final offset = GalleryUtils.parseOffset(offsetTimeStr);
        if (offset != null) {
          return (false, dateTime.add(offset).millisecondsSinceEpoch);
        }
      } else {
        return (false, dateTime.toLocal().millisecondsSinceEpoch);
      }
    } catch (e) {
      print('Failed to parse EXIF date: $e');
      return (true, null);
    }

    return (true, null);
  }

  static String formatDate(File image) {
    final String filename = path.basenameWithoutExtension(image.path);
    final int timestamp = int.tryParse(filename) ?? 0;
    final DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final int currentYear = DateTime.now().year;

    const List<String> monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final String month = monthNames[dateTime.month - 1];
    final int day = dateTime.day;

    if (dateTime.year == currentYear) {
      return '$month $day';
    } else {
      return '$month $day ${dateTime.year}';
    }
  }

  static Future<List<String>> getAllStabAndFailedImagePaths(int projectId) async {
    final String projectOrientation = await SettingsUtil.loadProjectOrientation(projectId.toString());
    final List<Map<String, dynamic>> stabPhotos = await DB.instance.getStabilizedAndFailedPhotosByProjectID(projectId, projectOrientation);

    List<Future<String>> futurePaths = stabPhotos.map((stabilizedPhoto) async {
      final String timestamp = stabilizedPhoto['timestamp'];
      final rawPhotoPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        timestamp,
        projectId,
      );
      return await DirUtils.getStabilizedImagePath(rawPhotoPath, projectId);
    }).toList();

    return await Future.wait(futurePaths);
  }

  static Future<List<String>> getAllRawImagePaths(int projectId) async {
    return await DB.instance.getAllPhotoPathsByProjectID(projectId);
  }

  static Future<void> loadImages({
    required int projectId,
    required String projectIdStr,
    required Function(List<String>, List<String>) onImagesLoaded,
    required VoidCallback onShowInfoDialog,
    required ScrollController stabilizedScrollController,
  }) async {
    final List<Object> results = await Future.wait([
      getAllRawImagePaths(projectId),
      SettingsUtil.hasOpenedNonEmptyGallery(projectIdStr),
      getAllStabAndFailedImagePaths(projectId)
    ]);

    final List<String> rawImagePaths = results[0] as List<String>;
    final bool hasOpenedNonEmptyGallery = results[1] as bool;
    final List<String> stabImagePaths = results[2] as List<String>;

    if (!hasOpenedNonEmptyGallery && rawImagePaths.isNotEmpty) {
      await SettingsUtil.setHasOpenedNonEmptyGalleryToTrue(projectIdStr);
      onShowInfoDialog();
    }

    rawImagePaths.sort((b, a) => b.split('/').last.compareTo(a.split('/').last));
    stabImagePaths.sort((b, a) => b.split('/').last.compareTo(a.split('/').last));

    await onImagesLoaded(rawImagePaths, stabImagePaths);

    // Scroll to bottom after images are loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToBottomInstantly(stabilizedScrollController);
    });
  }


  static Future<void> scrollToBottomInstantly(ScrollController scrollController) async {
    if (scrollController.hasClients) {
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (scrollController.hasClients) {
            scrollController.jumpTo(scrollController.position.maxScrollExtent);
          }
        });
      });
    }
  }

  static Future<String> processZipInIsolate(String zipFileExportPath, List<File> imageFiles) async {
    Future<void> galleryIsolateOperation(Map<String, dynamic> params) async {
      String zipFileExportPath = params['zipFileExportPath'];
      List<String> filePaths = params['filePaths'];
      var sendPort = params['sendPort'];

      ZipFileEncoder encoder = ZipFileEncoder();
      encoder.create(zipFileExportPath);

      for (String path in filePaths) {
        await encoder.addFile(File(path));
      }

      encoder.close();
      sendPort.send("success");
    }

    List<String> filePaths = imageFiles.map((file) => file.path).toList();

    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'zipFileExportPath': zipFileExportPath,
      'filePaths': filePaths,
    };

    Isolate isolate = await Isolate.spawn(galleryIsolateOperation, params);
    final res = await receivePort.first;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
    return res;
  }

  static Future<void> processPickedImage(
      String imagePath,
      int projectId,
      ValueNotifier<String> activeProcessingDateNotifier,
      {
        required Function onImagesLoaded,
        int? timestamp,
        VoidCallback? increaseSuccessfulImportCount
      }
      ) async {
    final imageProcessor = ImageProcessor(
        imagePath: imagePath,
        projectId: projectId,
        activeProcessingDateNotifier: activeProcessingDateNotifier,
        onImagesLoaded: onImagesLoaded,
        timestamp: timestamp,
        increaseSuccessfulImportCount: increaseSuccessfulImportCount
    );

    await imageProcessor.process();
    imageProcessor.dispose();
  }

  static Future<void> processPickedFile(
      File file,
      int projectId,
      ValueNotifier<String> activeProcessingDateNotifier, {
        required Function onImagesLoaded,
        required Function(int p1) setProgressInMain,
        required void Function() increaseSuccessfulImportCount,
        required void Function(int value) increasePhotosImported,
      }
      ) async {
    if (path.extension(file.path) == ".zip") {
      await processPickedZipFile(
          file,
          projectId,
          activeProcessingDateNotifier,
          onImagesLoaded,
          setProgressInMain,
          increaseSuccessfulImportCount,
          increasePhotosImported
      );
    } else if (Utils.isImage(file.path)) {
      await processPickedImage(
        file.path,
        projectId,
        activeProcessingDateNotifier,
        onImagesLoaded: onImagesLoaded,
      );
    }
  }

  static Future<void> processPickedZipFile(
      File file,
      int projectId,
      ValueNotifier<String> activeProcessingDateNotifier,
      Function onImagesLoaded,
      Function(int p1) setProgressInMain,
      void Function() increaseSuccessfulImportCount,
      void Function(int value) increasePhotosImported,
      ) async {
    final reader = ZipFileReader();
    try {
      reader.open(File(file.path));
      List<ZipEntry> entries = (await reader.entries())
          .where((entry) {
        final String basename = path.basename(entry.name);
        return entry.size >= 10000 && Utils.isImage(basename) && !entry.isDir;
      })
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      increasePhotosImported(entries.length);

      for (int i = 0; i < entries.length; i += 2) {
        // Take the next two entries to process concurrently
        final entriesToProcess = entries.sublist(i, (i + 2) > entries.length ? entries.length : (i + 2));

        // Process the entries concurrently
        await Future.wait(entriesToProcess.map((entry) async {
          final int currentIndex = entries.indexOf(entry);
          setProgressInMain(((currentIndex / entries.length) * 100).toInt());

          final String tempFilePath = path.join(
            await DirUtils.getTemporaryDirPath(),
            path.basename(entry.name).toLowerCase(),
          );
          final File tempFile = File(tempFilePath);

          try {
            await reader.readToFile(entry.name, tempFile);
            await processPickedImage(
              tempFilePath,
              projectId,
              activeProcessingDateNotifier,
              onImagesLoaded: onImagesLoaded,
              increaseSuccessfulImportCount: increaseSuccessfulImportCount,
            );
          } catch (_) {
            // Handle the error if needed
          } finally {
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          }
        }).toList());
      }
    } finally {
      reader.close();
    }
  }



  static Future<void> fetchFilesRecursively(Directory dir) async {
    await for (FileSystemEntity entity in dir.list(recursive: false)) {
      if (entity is File) {
        fileList.add(entity.path);
      } else if (entity is Directory) {
        await fetchFilesRecursively(entity);
      }
    }
  }


  static Future<Map<String, IfdTag>> tryReadExifFromBytes(Uint8List bytes) async {
    try {
      final Map<String, IfdTag> data = await readExifFromBytes(bytes);
      return data;
    } catch (e) {
      return {};
    }
  }

  static Future<bool> importXFile(
      XFile file,
      int projectId,
      ValueNotifier<String> activeProcessingDateNotifier,
      {
        int? timestamp,
        VoidCallback? increaseSuccessfulImportCount
      }
      ) async {
    Uint8List? bytes;
    try {
      int? imageTimestampFromExif;
      bool failedToParseDateMetadata = false;

      if (timestamp == null) {
        failedToParseDateMetadata = true; // Assume we fail

        bytes = await CameraUtils.readBytesInIsolate(file.path);
        final Map<String, IfdTag> data = await tryReadExifFromBytes(bytes!);

        if (data.isNotEmpty) {
          (failedToParseDateMetadata, imageTimestampFromExif) = await GalleryUtils.parseExifDate(data);
        }

        if (imageTimestampFromExif == null) {
          final String basename = path.basenameWithoutExtension(file.path);
          DateTime? dateTime = parseAndFormatDate(basename, activeProcessingDateNotifier);
          if (dateTime != null) {
            imageTimestampFromExif = dateTime.millisecondsSinceEpoch;
            failedToParseDateMetadata = false;
          }
        }
      } else {
        imageTimestampFromExif = timestamp;
        bytes = await CameraUtils.readBytesInIsolate(file.path);
      }

      print("Here1");

      final bool result = await CameraUtils.savePhoto(
        file,
        projectId,
        true,
        imageTimestampFromExif,
        failedToParseDateMetadata,
        bytes: bytes,
        increaseSuccessfulImportCount: increaseSuccessfulImportCount,
      );

      print("savePhoto complete. Returning $result");

      return result;
    } catch (e) {
      print("Error caught $e");
      return false;
    } finally {
      bytes = null;
    }
  }

  static DateTime? parseAndFormatDate(String input, ValueNotifier<String> activeProcessingDateNotifier) {
    var pattern = RegExp(
      r'\b(\d{4})[-/](\d{1,2})[-/](\d{1,2})|(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})|(\d{1,2})(?:st|nd|rd|th)?\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{2,4})|(\d{1,2})(?:st|nd|rd|th)?\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{2,4})\b',
      caseSensitive: false,
    );

    var match = pattern.firstMatch(input);
    if (match == null) return null;

    String? testForm;
    if (match.group(1) != null) {
      testForm = '${match.group(1)}-${match.group(2)}-${match.group(3)}';
    } else if (match.group(4) != null) {
      var year = int.parse(match.group(6)!);
      year = year < 100 ? (year + 2000) : year;
      testForm = '$year-${match.group(5)?.padLeft(2, '0')}-${match.group(4)?.padLeft(2, '0')}';
    } else if (match.group(7) != null) {
      var month = DateFormat.MMM().parse(match.group(8)!).month.toString().padLeft(2, '0');
      testForm = '${match.group(9)}-$month-${match.group(7)?.replaceAll(RegExp(r'[a-z]+'), '').padLeft(2, '0')}';
    }

    if (testForm == null) return null;

    print("Date parsed as string: $testForm");
    activeProcessingDateNotifier.value = testForm;

    try {
      return DateTime.parse(testForm);
    } catch (e) {
      return null;
    }
  }

  static void zipFiles(ZipIsolateParams params) async {
    try {
      final encoder = ZipFileEncoder();
      encoder.create(params.zipFilePath);

      Map<String, int> rawFilenameCounts = {};
      Map<String, int> stabilizedFilenameCounts = {};

      for (var entry in params.filesToExport.entries) {
        String folderName = entry.key;
        List<String> files = entry.value;

        files.sort((a, b) {
          int timestampA = int.parse(path.basenameWithoutExtension(a));
          int timestampB = int.parse(path.basenameWithoutExtension(b));
          return timestampA.compareTo(timestampB);
        });

        int i = 1;
        for (String filePath in files) {
          File file = File(filePath);
          if (file.existsSync()) {
            String basename = path.basenameWithoutExtension(filePath);
            String extension = path.extension(filePath);

            int timestamp = int.parse(basename);
            DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp);
            String formattedDate = DateFormat('yyyy-MM-dd').format(date);

            String newFileName = formattedDate + extension;

            // Use separate filename counts for 'Raw' and 'Stabilized' folders
            Map<String, int> filenameCounts = folderName == 'Raw' ? rawFilenameCounts : stabilizedFilenameCounts;

            // Check for duplicates and rename accordingly
            if (filenameCounts.containsKey(newFileName)) {
              int count = filenameCounts[newFileName]!;
              filenameCounts[newFileName] = count + 1;
              newFileName = '$formattedDate (${count + 1})$extension';
            } else {
              filenameCounts[newFileName] = 1;
            }

            encoder.addFile(file, '$folderName/$newFileName');
          }

          double percent = (i / files.length) * 100;
          params.sendPort.send(percent);
          i++;
        }
      }

      encoder.close();
      params.sendPort.send('success');
    } catch (e) {
      params.sendPort.send('error');
    }
  }

  static Future<String> exportZipFile(int projectId, String projectName, Map<String, List<String>> filesToExport, void Function(double exportProgressIn) setExportProgress) async {
    try {
      String zipFilePath = await DirUtils.getZipFileExportPath(projectId, projectName);

      final receivePort = ReceivePort();
      await Isolate.spawn(
        zipFiles,
        ZipIsolateParams(receivePort.sendPort, projectId, projectName, filesToExport, zipFilePath),
      );

      await for (var message in receivePort) {
        if (message == 'success' || message == 'error') {
          receivePort.close();
          return message;
        } else {
          double percent;
          try {
            if (message is String) {
              percent = double.parse(message);
            } else if (message is double) {
              percent = message;
            } else {
              throw Exception("Unexpected message type");
            }
            setExportProgress(percent);
          } catch (e) {
            //print("Error: $e");
          }
        }
      }


      return 'error';  // In case the loop exits without receiving 'success' or 'error'
    } catch (e) {
      return 'error';
    }
  }


  static Future<String> waitForThumbnail(String thumbnailPath, int projectId) async {
    while (true) {
      final String timestamp = path.basenameWithoutExtension(thumbnailPath);

      Map<String, dynamic>? photo = await DB.instance.getPhotoByTimestamp(timestamp, projectId);
      if (photo != null) {
        print(photo);
        try {
          if (photo['noFacesFound'] == 1) {
            return "no_faces_found";
          } else if (photo['stabFailed'] == 1) {
            return "stab_failed";
          }
        } catch (e) {
          //print("Error: $e");
        }
      }

      if (await File(thumbnailPath).exists()) {
        return "success";
      }

//      print("Waiting for 1s for $thumbnailPath...");
      await Future.delayed(const Duration(seconds: 1));
    }
  }

}

class ZipIsolateParams {
  final SendPort sendPort;
  final int projectId;
  final String projectName;
  final Map<String, List<String>> filesToExport;
  final String zipFilePath;

  ZipIsolateParams(this.sendPort, this.projectId, this.projectName, this.filesToExport, this.zipFilePath);
}
