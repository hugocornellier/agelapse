import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:archive/archive.dart';
import 'package:async_zip/async_zip.dart';
import 'package:camera/camera.dart';
import 'package:exif_reader/exif_reader.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';

import '../services/database_helper.dart';
import '../services/image_processor.dart';
import 'camera_utils.dart';
import 'dir_utils.dart';
import 'image_utils.dart';
import 'settings_utils.dart';
import 'utils.dart';

class GalleryUtils {
  static var fileList = [];
  static int _batchTotal = 0;
  static int _batchDone = 0;

  static void startImportBatch(int total) {
    _batchTotal = total;
    _batchDone = 0;
  }

  static void _tickBatchProgress(Function(int) setProgressInMain) {
    if (_batchTotal <= 0) return;
    _batchDone++;
    final p = ((_batchDone / _batchTotal) * 100).round();
    setProgressInMain(p);
    if (_batchDone >= _batchTotal) {
      setProgressInMain(100);
      _batchTotal = 0;
      _batchDone = 0;
    }
  }

  static Future<void> convertAvifToPng(
      String avifFilePath, String pngFilePath) async {
    try {
      final avifBytes = await File(avifFilePath).readAsBytes();
      // Convert in isolate to avoid blocking UI
      final pngBytes = await ImageUtils.convertToPngInIsolate(avifBytes);

      if (pngBytes != null) {
        final pngFile = File(pngFilePath);
        await pngFile.writeAsBytes(pngBytes);
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

  static String _normalizeOffset(String s) {
    final t = s.trim();
    if (RegExp(r'^[+-]\d{2}:\d{2}$').hasMatch(t)) return t;
    if (RegExp(r'^[+-]\d{2}\d{2}$').hasMatch(t))
      return '${t.substring(0, 3)}:${t.substring(3)}';
    if (RegExp(r'^[+-]\d{2}$').hasMatch(t)) return '${t}:00';
    return t;
  }

  static Future<(bool, int?)> parseExifDate(
      Map<String, dynamic> exifData) async {
    try {
      final String? gpsDateStr = exifData['GPS GPSDateStamp']?.toString();
      final String? gpsTimeStr = exifData['GPS GPSTimeStamp']?.toString();
      if (gpsDateStr != null && gpsTimeStr != null) {
        final dm =
            RegExp(r'^(\d{4})[:\-](\d{2})[:\-](\d{2})$').firstMatch(gpsDateStr);
        final tm = RegExp(r'^(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?$')
            .firstMatch(gpsTimeStr);
        if (dm != null && tm != null) {
          final y = int.parse(dm.group(1)!);
          final mo = int.parse(dm.group(2)!);
          final d = int.parse(dm.group(3)!);
          final h = int.parse(tm.group(1)!);
          final mi = int.parse(tm.group(2)!);
          final s = int.parse(tm.group(3)!);
          final ms = tm.group(4) != null
              ? int.parse(tm.group(4)!.padRight(3, '0'))
              : 0;
          final utc = DateTime.utc(y, mo, d, h, mi, s, ms);
          return (false, utc.millisecondsSinceEpoch);
        }
      }

      final String? dtStr = exifData['EXIF DateTimeOriginal']?.toString() ??
          exifData['Image DateTime']?.toString();
      if (dtStr == null) return (true, null);

      final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$')
          .firstMatch(dtStr);
      if (m == null) return (true, null);

      final y = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final d = int.parse(m.group(3)!);
      final h = int.parse(m.group(4)!);
      final mi = int.parse(m.group(5)!);
      final s = int.parse(m.group(6)!);

      final String? rawOffset =
          exifData['EXIF OffsetTimeOriginal']?.toString() ??
              exifData['EXIF OffsetTime']?.toString() ??
              exifData['EXIF OffsetTimeDigitized']?.toString() ??
              exifData['Time Zone for Original Date']?.toString() ??
              exifData['Time Zone for Digitized Date']?.toString() ??
              exifData['Time Zone for Modification Date']?.toString();

      if (rawOffset != null) {
        final norm = _normalizeOffset(rawOffset);
        final offset = GalleryUtils.parseOffset(norm);
        if (offset != null) {
          final wallUtc = DateTime.utc(y, mo, d, h, mi, s);
          final utcInstant = wallUtc.subtract(offset);
          return (false, utcInstant.millisecondsSinceEpoch);
        }
      }

      final local = DateTime(y, mo, d, h, mi, s);
      final utcGuess = local.toUtc();
      return (false, utcGuess.millisecondsSinceEpoch);
    } catch (e) {
      print('Failed to parse EXIF date: $e');
      return (true, null);
    }
  }

  static String formatDate(File image) {
    final String filename = path.basenameWithoutExtension(image.path);
    final int timestamp = int.tryParse(filename) ?? 0;
    final DateTime dateTime =
        DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true).toLocal();
    final int currentYear = DateTime.now().year;

    const List<String> monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    final String month = monthNames[dateTime.month - 1];
    final int day = dateTime.day;

    if (dateTime.year == currentYear) {
      return '$month $day';
    } else {
      return '$month $day ${dateTime.year}';
    }
  }

  static Future<List<String>> getAllStabAndFailedImagePaths(
      int projectId) async {
    final String projectOrientation =
        await SettingsUtil.loadProjectOrientation(projectId.toString());
    final List<Map<String, dynamic>> stabPhotos = await DB.instance
        .getStabilizedAndFailedPhotosByProjectID(projectId, projectOrientation);

    List<Future<String>> futurePaths = stabPhotos.map((stabilizedPhoto) async {
      final String timestamp = stabilizedPhoto['timestamp'];
      final rawPhotoPath =
          await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
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

    rawImagePaths
        .sort((b, a) => b.split('/').last.compareTo(a.split('/').last));
    stabImagePaths
        .sort((b, a) => b.split('/').last.compareTo(a.split('/').last));

    await onImagesLoaded(rawImagePaths, stabImagePaths);
  }

  static Future<void> scrollToBottomInstantly(
      ScrollController scrollController) async {
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

  static Future<String> processZipInIsolate(
      String zipFileExportPath, List<File> imageFiles) async {
    final List<String> filePaths = imageFiles.map((f) => f.path).toList();

    final receivePort = ReceivePort();
    final params = {
      'sendPort': receivePort.sendPort,
      'zipFileExportPath': zipFileExportPath,
      'filePaths': filePaths,
    };

    final isolate =
        await Isolate.spawn(GalleryUtils._galleryIsolateOperation, params);
    final res = await receivePort.first;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
    return res;
  }

  static void _galleryIsolateOperation(Map<String, dynamic> params) {
    final String zipFileExportPath = params['zipFileExportPath'];
    final List<String> filePaths = List<String>.from(params['filePaths']);
    final SendPort sendPort = params['sendPort'];

    final encoder = ZipFileEncoder();
    bool ok = true;

    try {
      encoder.create(zipFileExportPath);
      for (final fp in filePaths) {
        final f = File(fp);
        if (f.existsSync()) {
          encoder.addFile(f, path.basename(fp));
        }
      }
    } catch (_) {
      ok = false;
    } finally {
      encoder.close();
      sendPort.send(ok ? "success" : "error");
    }
  }

  static Future<void> processPickedImage(String imagePath, int projectId,
      ValueNotifier<String> activeProcessingDateNotifier,
      {required Function onImagesLoaded,
      int? timestamp,
      VoidCallback? increaseSuccessfulImportCount}) async {
    final imageProcessor = ImageProcessor(
        imagePath: imagePath,
        projectId: projectId,
        activeProcessingDateNotifier: activeProcessingDateNotifier,
        onImagesLoaded: onImagesLoaded,
        timestamp: timestamp,
        increaseSuccessfulImportCount: increaseSuccessfulImportCount);

    await imageProcessor.process();
    imageProcessor.dispose();
  }

  static Future<void> processPickedZipFileDesktop(
    File file,
    int projectId,
    ValueNotifier<String> activeProcessingDateNotifier,
    Function onImagesLoaded,
    Function(int p1) setProgressInMain,
    void Function() increaseSuccessfulImportCount,
    void Function(int value) increasePhotosImported,
  ) async {
    final input = InputFileStream(file.path);
    try {
      final archive = ZipDecoder().decodeStream(input);

      final entries = archive.files.where((f) {
        if (!f.isFile) return false;
        final lowerName = path.basename(f.name).toLowerCase();
        if (lowerName == '.ds_store' || f.name.startsWith('__MACOSX/'))
          return false;

        const allowed = {
          '.jpg',
          '.jpeg',
          '.png',
          '.webp',
          '.bmp',
          '.tif',
          '.tiff',
          '.heic',
          '.heif',
          '.avif',
          '.gif'
        };
        final ext = path.extension(lowerName);
        if (!allowed.contains(ext)) return false;

        return f.size >= 10000;
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      increasePhotosImported(entries.length);
      if (entries.isEmpty) {
        setProgressInMain(100); // or 0
        return;
      }

      debugPrint(
          '[unzip] total in zip: ${archive.files.length}'); // or the async_zip entries list length
      debugPrint('[unzip] usable images: ${entries.length}');
      if (entries.isEmpty) {
        for (final f in archive.files) {
          debugPrint('  - ${f.name} size=${f.size} isFile=${f.isFile}');
        }
      }

      for (int i = 0; i < entries.length; i++) {
        final f = entries[i];
        setProgressInMain(((i / entries.length) * 100).toInt());

        final String tempFilePath = path.join(
          await DirUtils.getTemporaryDirPath(),
          path.basename(f.name).toLowerCase(),
        );

        final out = OutputFileStream(tempFilePath);
        f.writeContent(out);
        out.close();

        try {
          await processPickedImage(
            tempFilePath,
            projectId,
            activeProcessingDateNotifier,
            onImagesLoaded: onImagesLoaded,
            increaseSuccessfulImportCount: increaseSuccessfulImportCount,
          );
        } catch (_) {
        } finally {
          final tempFile = File(tempFilePath);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        }
      }
    } finally {
      input.close();
    }
  }

  static Future<void> processPickedFile(
    File file,
    int projectId,
    ValueNotifier<String> activeProcessingDateNotifier, {
    required Function onImagesLoaded,
    required Function(int p1) setProgressInMain,
    required void Function() increaseSuccessfulImportCount,
    required void Function(int value) increasePhotosImported,
  }) async {
    if (path.extension(file.path).toLowerCase() == ".zip") {
      if (Platform.isAndroid || Platform.isIOS) {
        await processPickedZipFile(
            file,
            projectId,
            activeProcessingDateNotifier,
            onImagesLoaded,
            setProgressInMain,
            increaseSuccessfulImportCount,
            increasePhotosImported);
      } else {
        await processPickedZipFileDesktop(
            file,
            projectId,
            activeProcessingDateNotifier,
            onImagesLoaded,
            setProgressInMain,
            increaseSuccessfulImportCount,
            increasePhotosImported);
      }
    } else if (Utils.isImage(file.path)) {
      increasePhotosImported(1);

      await processPickedImage(
        file.path,
        projectId,
        activeProcessingDateNotifier,
        onImagesLoaded: onImagesLoaded,
        increaseSuccessfulImportCount: increaseSuccessfulImportCount,
      );

      _tickBatchProgress(setProgressInMain);
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
      List<ZipEntry> entries = (await reader.entries()).where((entry) {
        final String basenameOnly = path.basename(entry.name);
        return entry.size >= 10000 &&
            Utils.isImage(basenameOnly) &&
            !entry.isDir;
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      increasePhotosImported(entries.length);
      if (entries.isEmpty) {
        setProgressInMain(100); // or 0
        return;
      }

      for (int i = 0; i < entries.length; i++) {
        final entry = entries[i];
        setProgressInMain(((i / entries.length) * 100).toInt());

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
          //
        } finally {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        }
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

  static Future<Map<String, dynamic>> tryReadExifFromBytes(
      Uint8List bytes) async {
    try {
      final data = await readExifFromBytes(bytes);
      return Map<String, dynamic>.from(data);
    } catch (e) {
      return {};
    }
  }

  static Future<bool> importXFile(XFile file, int projectId,
      ValueNotifier<String> activeProcessingDateNotifier,
      {int? timestamp, VoidCallback? increaseSuccessfulImportCount}) async {
    Uint8List? bytes;
    try {
      int? imageTimestampFromExif;
      bool failedToParseDateMetadata = false;
      int? captureOffsetMinutes;

      if (timestamp == null) {
        failedToParseDateMetadata = true;

        bytes = await CameraUtils.readBytesInIsolate(file.path);
        final Map<String, dynamic> data = await tryReadExifFromBytes(bytes!);

        print('[import] EXIF keys: ${data.keys.toList()}');
        print(
            '[import] DateTimeOriginal: ${data['EXIF DateTimeOriginal']} CreateDate:${data['EXIF CreateDate']} ImageDateTime:${data['Image DateTime']}');
        print(
            '[import] OffsetTimeOriginal:${data['EXIF OffsetTimeOriginal']} OffsetTime:${data['EXIF OffsetTime']} OffsetTimeDigitized:${data['EXIF OffsetTimeDigitized']}');
        print(
            '[import] GPSDateStamp:${data['GPS GPSDateStamp']} GPSTimeStamp:${data['GPS GPSTimeStamp']}');

        if (data.isNotEmpty) {
          (failedToParseDateMetadata, imageTimestampFromExif) =
              await GalleryUtils.parseExifDate(data);

          final String? gpsDateStr = data['GPS GPSDateStamp']?.toString();
          final String? gpsTimeStr = data['GPS GPSTimeStamp']?.toString();
          if (gpsDateStr != null && gpsTimeStr != null) {
            captureOffsetMinutes = 0;
          } else {
            final String? rawOffset =
                data['EXIF OffsetTimeOriginal']?.toString() ??
                    data['EXIF OffsetTime']?.toString() ??
                    data['EXIF OffsetTimeDigitized']?.toString() ??
                    data['Time Zone for Original Date']?.toString() ??
                    data['Time Zone for Digitized Date']?.toString() ??
                    data['Time Zone for Modification Date']?.toString();
            if (rawOffset != null) {
              final norm = _normalizeOffset(rawOffset);
              final off = GalleryUtils.parseOffset(norm);
              if (off != null) {
                captureOffsetMinutes = off.inMinutes;
              }
            }
          }
        }

        if (imageTimestampFromExif == null) {
          final String basename = path.basenameWithoutExtension(file.path);
          final DateTime? parsed =
              parseAndFormatDate(basename, activeProcessingDateNotifier);
          if (parsed != null) {
            final DateTime localMidnight =
                DateTime(parsed.year, parsed.month, parsed.day);
            final int utcMidnightMs =
                localMidnight.toUtc().millisecondsSinceEpoch;
            imageTimestampFromExif = utcMidnightMs;
            captureOffsetMinutes = localMidnight.timeZoneOffset.inMinutes;
            failedToParseDateMetadata = false;
          }
        }

        if (imageTimestampFromExif == null) {
          final DateTime lm = await File(file.path).lastModified();
          final DateTime localMidnight = DateTime(lm.year, lm.month, lm.day);
          final int utcMidnightMs =
              localMidnight.toUtc().millisecondsSinceEpoch;
          imageTimestampFromExif = utcMidnightMs;
          captureOffsetMinutes = localMidnight.timeZoneOffset.inMinutes;
          failedToParseDateMetadata = false;
        }

        if (captureOffsetMinutes == null && imageTimestampFromExif != null) {
          captureOffsetMinutes = DateTime.fromMillisecondsSinceEpoch(
                  imageTimestampFromExif,
                  isUtc: true)
              .toLocal()
              .timeZoneOffset
              .inMinutes;
        }
      } else {
        imageTimestampFromExif = timestamp;
        bytes = await CameraUtils.readBytesInIsolate(file.path);
        captureOffsetMinutes =
            DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true)
                .toLocal()
                .timeZoneOffset
                .inMinutes;
        print(
            '[import] External timestamp provided -> utcMs:${imageTimestampFromExif} offsetMin:${captureOffsetMinutes}');
      }

      print(
          '[import] FINAL -> utcMs:${imageTimestampFromExif} captureOffsetMin:${captureOffsetMinutes} failedToParse:${failedToParseDateMetadata}');

      final bool result = await CameraUtils.savePhoto(
        file,
        projectId,
        true,
        imageTimestampFromExif,
        failedToParseDateMetadata,
        bytes: bytes,
        increaseSuccessfulImportCount: increaseSuccessfulImportCount,
      );

      if (result && imageTimestampFromExif != null) {
        await DB.instance.setCaptureOffsetMinutesByTimestamp(
          imageTimestampFromExif.toString(),
          projectId,
          captureOffsetMinutes,
        );
      }

      return result;
    } catch (e) {
      print("Error caught $e");
      return false;
    } finally {
      bytes = null;
    }
  }

  static DateTime? parseAndFormatDate(
      String input, ValueNotifier<String> activeProcessingDateNotifier) {
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
      testForm =
          '$year-${match.group(5)?.padLeft(2, '0')}-${match.group(4)?.padLeft(2, '0')}';
    } else if (match.group(7) != null) {
      var month = DateFormat.MMM()
          .parse(match.group(8)!)
          .month
          .toString()
          .padLeft(2, '0');
      testForm =
          '${match.group(9)}-$month-${match.group(7)?.replaceAll(RegExp(r'[a-z]+'), '').padLeft(2, '0')}';
    }

    if (testForm == null) return null;

    activeProcessingDateNotifier.value = testForm;

    try {
      return DateTime.parse(testForm);
    } catch (e) {
      return null;
    }
  }

  static void zipFiles(ZipIsolateParams params) async {
    final send = params.sendPort;
    void log(String m) => send.send({'type': 'log', 'msg': m});

    final outFile = File(params.zipFilePath);
    outFile.parent.createSync(recursive: true);

    for (final e in params.filesToExport.entries) {
      e.value.removeWhere((p) => path.equals(p, params.zipFilePath));
    }

    if (outFile.existsSync()) {
      try {
        outFile.deleteSync();
      } catch (e) {
        log('Cannot delete pre-existing zip: $e');
        send.send('error');
        return;
      }
    }

    bool ok = true;
    int added = 0, missing = 0, badname = 0;

    int safeNumCompare(String a, String b) {
      final aBase = path.basenameWithoutExtension(a);
      final bBase = path.basenameWithoutExtension(b);
      final ai = int.tryParse(aBase);
      final bi = int.tryParse(bBase);
      if (ai != null && bi != null) return ai.compareTo(bi);
      if (ai == null) badname++;
      if (bi == null) badname++;
      return aBase.compareTo(bBase);
    }

    try {
      final Map<String, int> rawCounts = {};
      final Map<String, int> stabCounts = {};
      final items = <({File file, String arcPath, int len})>[];

      for (final entry in params.filesToExport.entries) {
        final folder = entry.key; // "Raw" or "Stabilized"
        final files = List<String>.from(entry.value)..sort(safeNumCompare);
        final counts = folder == 'Raw' ? rawCounts : stabCounts;

        for (final p in files) {
          final f = File(p);
          if (!f.existsSync()) {
            missing++;
            continue;
          }

          final base = path.basenameWithoutExtension(p);
          final ext = path.extension(p);
          final ts = int.tryParse(base);
          final dt = ts != null
              ? DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true).toLocal()
              : f.lastModifiedSync();
          final stamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(dt);

          var newName = '$stamp$ext';
          final dup = counts[newName];
          if (dup != null) {
            final n = dup + 1;
            counts[newName] = n;
            newName = '$stamp ($n)$ext';
          } else {
            counts[newName] = 1;
          }

          final len = f.lengthSync();
          if (len <= 0) continue;
          items.add((file: f, arcPath: '$folder/$newName', len: len));
        }
      }

      if (items.isEmpty) {
        log('No files to add (missing=$missing, badname=$badname)');
        send.send({
          'type': 'summary',
          'added': added,
          'missing': missing,
          'badname': badname
        });
        send.send('error');
        return;
      }

      final totalBytes = items.fold<int>(0, (s, it) => s + it.len);
      var stagedBytes = 0;

      final archive = Archive();
      for (final it in items) {
        try {
          final bytes = it.file.readAsBytesSync();
          final af = ArchiveFile.noCompress(it.arcPath, bytes.length, bytes);
          archive.addFile(af);
          added++;

          stagedBytes += it.len;
          final pct = totalBytes == 0 ? 0.0 : (stagedBytes / totalBytes) * 98.0;
          send.send(pct);
        } catch (e, st) {
          ok = false;
          log('read/add failed for ${it.file.path}: $e');
          log('stack: $st');
          break;
        }
      }

      if (ok) {
        final zipBytes = ZipEncoder().encode(archive, level: 0);
        outFile.writeAsBytesSync(zipBytes, flush: true);
      }
    } catch (e, st) {
      ok = false;
      log('zipFiles crashed: $e\n$st');
    } finally {
      send.send({
        'type': 'summary',
        'added': added,
        'missing': missing,
        'badname': badname
      });
      if (ok) {
        send.send(100.0);
        send.send('success');
      } else {
        try {
          if (outFile.existsSync()) outFile.deleteSync();
        } catch (_) {}
        send.send('error');
      }
    }
  }

  static Future<String> exportZipFile(
      int projectId,
      String projectName,
      Map<String, List<String>> filesToExport,
      void Function(double exportProgressIn) setExportProgress) async {
    try {
      String zipTargetPath;
      String zipWorkPath;

      if (Platform.isAndroid || Platform.isIOS) {
        zipWorkPath =
            await DirUtils.getZipFileExportPath(projectId, projectName);
        final exportsDir = File(zipWorkPath).parent;
        if (!await exportsDir.exists()) {
          await exportsDir.create(recursive: true);
        }
        zipTargetPath = zipWorkPath;
      } else {
        final tmpDir = await DirUtils.getTemporaryDirPath();
        final tmpName =
            '${projectName.isEmpty ? "Export" : projectName}-AgeLapse-Export-${DateTime.now().millisecondsSinceEpoch}.zip';
        zipWorkPath = path.join(tmpDir, tmpName);
        final workDir = File(zipWorkPath).parent;
        if (!await workDir.exists()) {
          await workDir.create(recursive: true);
        }
        zipTargetPath = '';
      }

      final receivePort = ReceivePort();
      await Isolate.spawn(
        zipFiles,
        ZipIsolateParams(receivePort.sendPort, projectId, projectName,
            filesToExport, zipWorkPath),
      );

      String result = 'error';
      await for (var message in receivePort) {
        if (message == 'success' || message == 'error') {
          result = message as String;
          receivePort.close();
          break;
        }
        if (message is Map && message['type'] == 'log') {
          debugPrint('[zip] ${message['msg']}');
          continue;
        }
        if (message is Map && message['type'] == 'summary') {
          debugPrint(
              '[zip] summary added=${message['added']} missing=${message['missing']} badname=${message['badname']}');
          if ((message['added'] ?? 0) == 0) {
            debugPrint('[zip] WARNING: 0 files added');
          }
          continue;
        }
        if (message is double) {
          setExportProgress(message);
          continue;
        }
        if (message is String) {
          final p = double.tryParse(message);
          if (p != null) {
            setExportProgress(p);
            continue;
          }
        }
        debugPrint('[zip] Unrecognized message: $message');
      }

      if (!(Platform.isAndroid || Platform.isIOS) && result == 'success') {
        final suggested =
            '${projectName.isEmpty ? "Export" : projectName}-AgeLapse-Export.zip';
        final location = await getSaveLocation(
          suggestedName: suggested,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'zip', extensions: ['zip'])
          ],
        );
        if (location == null) {
          try {
            File(zipWorkPath).deleteSync();
          } catch (_) {}
          return 'error';
        }
        zipTargetPath = location.path.toLowerCase().endsWith('.zip')
            ? location.path
            : '${location.path}.zip';
        final targetDir = File(zipTargetPath).parent;
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
        await File(zipWorkPath).copy(zipTargetPath);
        try {
          File(zipWorkPath).deleteSync();
        } catch (_) {}
      }

      return result;
    } catch (e) {
      return 'error';
    }
  }

  static Future<String> waitForThumbnail(String thumbnailPath, int projectId,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final sw = Stopwatch()..start();
    int? lastLen;
    while (sw.elapsed < timeout) {
      final String timestamp = path.basenameWithoutExtension(thumbnailPath);
      final photo = await DB.instance.getPhotoByTimestamp(timestamp, projectId);
      if (photo != null) {
        if (photo['noFacesFound'] == 1) return "no_faces_found";
        if (photo['stabFailed'] == 1) return "stab_failed";
      }
      final f = File(thumbnailPath);
      if (await f.exists()) {
        final len = await f.length();
        if (len > 0 && lastLen != null && len == lastLen) {
          // Validate image in isolate to avoid blocking UI
          final valid = await ImageUtils.validateImageInIsolate(thumbnailPath);
          if (valid) return "success";
        }
        lastLen = len;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return "stab_failed";
  }
}

class ZipIsolateParams {
  final SendPort sendPort;
  final int projectId;
  final String projectName;
  final Map<String, List<String>> filesToExport;
  final String zipFilePath;

  ZipIsolateParams(this.sendPort, this.projectId, this.projectName,
      this.filesToExport, this.zipFilePath);
}
