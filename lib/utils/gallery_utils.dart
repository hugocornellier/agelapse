import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:async_zip/async_zip.dart';
import 'package:exif_reader/exif_reader.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_avif/flutter_avif.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:file_selector/file_selector.dart';

import '../services/database_helper.dart';
import '../services/face_stabilizer.dart';
import '../services/image_processor.dart';
import '../services/log_service.dart';
import '../services/thumbnail_service.dart';
import '../models/import_preview_item.dart';
import 'camera_utils.dart';
import 'dir_utils.dart';
import 'export_naming_utils.dart';
import 'image_format_utils.dart';
import 'platform_utils.dart';
import 'settings_utils.dart';
import 'test_mode.dart' as test_config;

/// Result from directory scanning operation
class DirectoryScanResult {
  final List<String> validImagePaths;
  final int totalFilesScanned;
  final int directoriesScanned;
  final List<String> errors;
  final bool wasCancelled;

  const DirectoryScanResult({
    required this.validImagePaths,
    required this.totalFilesScanned,
    required this.directoriesScanned,
    required this.errors,
    required this.wasCancelled,
  });
}

/// Input for directory scanning isolate
class DirectoryScanInput {
  final String directoryPath;
  final int maxRecursionDepth;
  final int minImageSizeBytes;
  final Set<String> allowedExtensions;

  const DirectoryScanInput({
    required this.directoryPath,
    required this.maxRecursionDepth,
    required this.minImageSizeBytes,
    required this.allowedExtensions,
  });
}

/// Top-level function for compute() - scans directory in isolate.
/// This moves the blocking stat() syscalls off the main thread.
DirectoryScanResult scanDirectoryIsolateEntry(DirectoryScanInput input) {
  final dir = Directory(input.directoryPath);
  if (!dir.existsSync()) {
    return DirectoryScanResult(
      validImagePaths: [],
      totalFilesScanned: 0,
      directoriesScanned: 0,
      errors: ['Directory does not exist: ${input.directoryPath}'],
      wasCancelled: false,
    );
  }

  final List<String> validPaths = [];
  final List<String> errors = [];
  int filesScanned = 0;
  int dirsScanned = 0;

  void scanDir(Directory currentDir, int depth) {
    if (depth > input.maxRecursionDepth) {
      errors.add(
        'Max depth (${input.maxRecursionDepth}) exceeded at: ${currentDir.path}',
      );
      return;
    }

    dirsScanned++;

    try {
      final entities = currentDir.listSync(
        recursive: false,
        followLinks: false,
      );
      for (final entity in entities) {
        final basename = path.basename(entity.path);

        // Skip hidden files/directories (starting with .)
        if (basename.startsWith('.')) continue;

        // Skip macOS metadata directories
        if (entity.path.contains('__MACOSX')) continue;

        if (entity is File) {
          filesScanned++;

          // Check extension
          final ext = path.extension(entity.path).toLowerCase();
          if (!input.allowedExtensions.contains(ext)) continue;

          // Check minimum file size
          try {
            final stat = entity.statSync();
            if (stat.size < input.minImageSizeBytes) continue;
          } catch (_) {
            continue;
          }

          validPaths.add(entity.path);
        } else if (entity is Directory) {
          scanDir(entity, depth + 1);
        }
        // Skip Links (symlinks) for safety
      }
    } on FileSystemException catch (e) {
      errors.add('Permission denied: ${currentDir.path} - ${e.message}');
    } catch (e) {
      errors.add('Error scanning ${currentDir.path}: $e');
    }
  }

  scanDir(dir, 0);

  // Sort alphabetically for consistent ordering (matches ZIP behavior)
  validPaths.sort(
    (a, b) => path
        .basename(a)
        .toLowerCase()
        .compareTo(path.basename(b).toLowerCase()),
  );

  return DirectoryScanResult(
    validImagePaths: validPaths,
    totalFilesScanned: filesScanned,
    directoriesScanned: dirsScanned,
    errors: errors,
    wasCancelled: false,
  );
}

class GalleryUtils {
  /// Maximum directory recursion depth to prevent stack overflow
  static const int maxRecursionDepth = 50;

  /// File count threshold that triggers user confirmation
  static const int largeDirectoryThreshold = 500;

  /// Minimum file size in bytes for valid images (matches ZIP processing)
  static const int minImageSizeBytes = 10000;

  /// Allowed image extensions for directory scanning
  static const Set<String> allowedImageExtensions =
      ImageFormats.acceptedExtensions;

  /// Compares two file paths by their basename as integers (timestamps).
  /// Falls back to string comparison for non-numeric basenames.
  static int compareByNumericBasename(String a, String b) {
    final ai = int.tryParse(path.basenameWithoutExtension(a));
    final bi = int.tryParse(path.basenameWithoutExtension(b));
    if (ai != null && bi != null) return ai.compareTo(bi);
    return path.basename(a).compareTo(path.basename(b));
  }

  /// Natural-order comparison: splits basenames into alpha/numeric chunks
  /// so that e.g. IMG_2 sorts before IMG_10.
  static int compareNatural(String a, String b) {
    final re = RegExp(r'(\d+|\D+)');
    final aParts = re.allMatches(path.basenameWithoutExtension(a)).toList();
    final bParts = re.allMatches(path.basenameWithoutExtension(b)).toList();
    for (var i = 0; i < aParts.length && i < bParts.length; i++) {
      final aStr = aParts[i].group(0)!;
      final bStr = bParts[i].group(0)!;
      final aNum = int.tryParse(aStr);
      final bNum = int.tryParse(bStr);
      final cmp = (aNum != null && bNum != null)
          ? aNum.compareTo(bNum)
          : aStr.compareTo(bStr);
      if (cmp != 0) return cmp;
    }
    return aParts.length.compareTo(bParts.length);
  }

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

  static Future<bool> convertAvifToPng(
    String avifFilePath,
    String pngFilePath,
  ) async {
    try {
      final File avifFile = File(avifFilePath);
      if (!await avifFile.exists()) {
        return false;
      }

      final avifBytes = await avifFile.readAsBytes();
      final List<AvifFrameInfo> frames = await decodeAvif(avifBytes);

      if (frames.isEmpty) {
        return false;
      }

      final ui.Image image = frames.first.image;

      // Convert dart:ui Image to PNG bytes
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        return false;
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // Write PNG to file
      final pngFile = File(pngFilePath);
      await pngFile.writeAsBytes(pngBytes);

      // Dispose frames to free memory
      for (final frame in frames) {
        frame.image.dispose();
      }

      return true;
    } catch (_) {
      return false;
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
    } catch (_) {
      return null;
    }
  }

  static String _normalizeOffset(String s) {
    final t = s.trim();
    if (RegExp(r'^[+-]\d{2}:\d{2}$').hasMatch(t)) return t;
    if (RegExp(r'^[+-]\d{2}\d{2}$').hasMatch(t)) {
      return '${t.substring(0, 3)}:${t.substring(3)}';
    }
    if (RegExp(r'^[+-]\d{2}$').hasMatch(t)) return '$t:00';
    return t;
  }

  static Future<(bool, int?)> parseExifDate(
    Map<String, dynamic> exifData,
  ) async {
    try {
      final String? gpsDateStr = exifData['GPS GPSDateStamp']?.toString();
      final String? gpsTimeStr = exifData['GPS GPSTimeStamp']?.toString();
      if (gpsDateStr != null && gpsTimeStr != null) {
        final dm = RegExp(
          r'^(\d{4})[:\-](\d{2})[:\-](\d{2})$',
        ).firstMatch(gpsDateStr);
        final tm = RegExp(
          r'^(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?$',
        ).firstMatch(gpsTimeStr);
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

      final m = RegExp(
        r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$',
      ).firstMatch(dtStr);
      if (m == null) {
        return (true, null);
      }

      final y = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final d = int.parse(m.group(3)!);
      final h = int.parse(m.group(4)!);
      final mi = int.parse(m.group(5)!);
      final s = int.parse(m.group(6)!);

      if (y < 1900 || mo < 1 || mo > 12 || d < 1 || d > 31) {
        return (true, null);
      }

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
      return (true, null);
    }
  }

  static Future<List<String>> getAllStabAndFailedImagePaths(
    int projectId,
  ) async {
    final String projectOrientation = await SettingsUtil.loadProjectOrientation(
      projectId.toString(),
    );
    final List<Map<String, dynamic>> stabPhotos = await DB.instance
        .getStabilizedAndFailedPhotosByProjectID(projectId, projectOrientation);

    List<Future<String>> futurePaths = stabPhotos.map((stabilizedPhoto) async {
      final String timestamp = stabilizedPhoto['timestamp'];
      final String? fileExtension = stabilizedPhoto['fileExtension'] as String?;
      final rawPhotoPath =
          await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        timestamp,
        projectId,
        fileExtension: fileExtension,
      );
      return await DirUtils
          .getStabilizedImagePathFromRawPathAndProjectOrientation(
        projectId,
        rawPhotoPath,
        projectOrientation,
      );
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
      getAllStabAndFailedImagePaths(projectId),
    ]);

    final List<String> rawImagePaths = results[0] as List<String>;
    final bool hasOpenedNonEmptyGallery = results[1] as bool;
    final List<String> stabImagePaths = results[2] as List<String>;

    if (!hasOpenedNonEmptyGallery && rawImagePaths.isNotEmpty) {
      await SettingsUtil.setHasOpenedNonEmptyGalleryToTrue(projectIdStr);
      onShowInfoDialog();
    }

    // Sort oldest first (ascending by filename/timestamp)
    rawImagePaths.sort(GalleryUtils.compareByNumericBasename);
    stabImagePaths.sort(GalleryUtils.compareByNumericBasename);

    await _prefetchThumbnailStatuses(stabImagePaths, projectId);

    await onImagesLoaded(rawImagePaths, stabImagePaths);
  }

  /// Batch prefetch thumbnail statuses to seed ThumbnailService cache.
  static Future<void> _prefetchThumbnailStatuses(
    List<String> stabImagePaths,
    int projectId,
  ) async {
    if (stabImagePaths.isEmpty) return;

    final timestamps =
        stabImagePaths.map((p) => path.basenameWithoutExtension(p)).toList();
    final statusMap = await DB.instance.getPhotoStatusBatch(
      timestamps,
      projectId,
    );

    final Map<String, ThumbnailStatus> cacheEntries = {};
    for (final stabPath in stabImagePaths) {
      final timestamp = path.basenameWithoutExtension(stabPath);
      final flags = statusMap[timestamp];

      if (flags != null) {
        final thumbnailPath = FaceStabilizer.getStabThumbnailPath(stabPath);
        if (flags['noFacesFound'] == 1) {
          cacheEntries[thumbnailPath] = ThumbnailStatus.noFacesFound;
        } else if (flags['stabFailed'] == 1) {
          cacheEntries[thumbnailPath] = ThumbnailStatus.stabFailed;
        }
      }
    }

    // Seed the cache with failure statuses
    if (cacheEntries.isNotEmpty) {
      ThumbnailService.instance.seedCache(cacheEntries);
    }
  }

  static Future<void> scrollToBottomInstantly(
    ScrollController scrollController,
  ) async {
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

  static Future<void> processPickedImage(
    String imagePath,
    int projectId,
    ValueNotifier<String> activeProcessingDateNotifier, {
    required Function onImagesLoaded,
    int? timestamp,
    VoidCallback? increaseSuccessfulImportCount,
    String? originalFilePath,
    String? sourceFilename,
  }) async {
    final imageProcessor = ImageProcessor(
      imagePath: imagePath,
      projectId: projectId,
      activeProcessingDateNotifier: activeProcessingDateNotifier,
      timestamp: timestamp,
      increaseSuccessfulImportCount: increaseSuccessfulImportCount,
      originalFilePath: originalFilePath,
      sourceFilename: sourceFilename,
    );

    await imageProcessor.process();
    imageProcessor.dispose();
  }

  /// Shared post-decode ZIP processing loop used by both desktop and mobile.
  ///
  /// [zipEntries] is a list of records describing each accepted entry:
  ///   - `name`: original entry name (used for sourceFilename and temp path)
  ///   - `writeTempFile`: async callback that writes the entry content to the
  ///     already-determined [tempFilePath]
  ///
  /// Callers are responsible for decoding the ZIP and filtering entries before
  /// calling this method, then passing write callbacks appropriate for their
  /// archive library.
  static Future<void> _processZipEntries(
    List<
            ({
              String name,
              Future<void> Function(String tempFilePath) writeTempFile
            })>
        zipEntries,
    int projectId,
    ValueNotifier<String> activeProcessingDateNotifier,
    Function onImagesLoaded,
    Function(int p1) setProgressInMain,
    void Function() increaseSuccessfulImportCount,
    void Function(int value) increasePhotosImported,
  ) async {
    increasePhotosImported(zipEntries.length);
    if (zipEntries.isEmpty) {
      setProgressInMain(100);
      return;
    }

    for (int i = 0; i < zipEntries.length; i++) {
      final entry = zipEntries[i];
      setProgressInMain(((i / zipEntries.length) * 100).toInt());

      final String tempFilePath = path.join(
        await DirUtils.getTemporaryDirPath(),
        path.basename(entry.name).toLowerCase(),
      );

      try {
        await entry.writeTempFile(tempFilePath);
        await processPickedImage(
          tempFilePath,
          projectId,
          activeProcessingDateNotifier,
          onImagesLoaded: onImagesLoaded,
          increaseSuccessfulImportCount: increaseSuccessfulImportCount,
          sourceFilename: path.basename(entry.name),
        );
      } catch (_) {
      } finally {
        final tempFile = File(tempFilePath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    }
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
        if (lowerName == '.ds_store' || f.name.startsWith('__MACOSX/')) {
          return false;
        }
        if (!ImageFormats.isAcceptedPath(lowerName)) return false;
        return f.size >= 10000;
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      final zipEntries = entries
          .map((f) => (
                name: f.name,
                writeTempFile: (String tempFilePath) async {
                  final out = OutputFileStream(tempFilePath);
                  f.writeContent(out);
                  out.close();
                },
              ))
          .toList();

      await _processZipEntries(
        zipEntries,
        projectId,
        activeProcessingDateNotifier,
        onImagesLoaded,
        setProgressInMain,
        increaseSuccessfulImportCount,
        increasePhotosImported,
      );
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
    int? overrideTimestamp,
  }) async {
    if (path.extension(file.path).toLowerCase() == ".zip") {
      if (isMobile) {
        await processPickedZipFile(
          file,
          projectId,
          activeProcessingDateNotifier,
          onImagesLoaded,
          setProgressInMain,
          increaseSuccessfulImportCount,
          increasePhotosImported,
        );
      } else {
        await processPickedZipFileDesktop(
          file,
          projectId,
          activeProcessingDateNotifier,
          onImagesLoaded,
          setProgressInMain,
          increaseSuccessfulImportCount,
          increasePhotosImported,
        );
      }
    } else if (ImageFormats.isAcceptedPath(file.path)) {
      increasePhotosImported(1);

      await processPickedImage(
        file.path,
        projectId,
        activeProcessingDateNotifier,
        onImagesLoaded: onImagesLoaded,
        increaseSuccessfulImportCount: increaseSuccessfulImportCount,
        sourceFilename: path.basename(file.path),
        timestamp: overrideTimestamp,
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
      final List<ZipEntry> rawEntries = (await reader.entries()).where((entry) {
        final String basenameOnly = path.basename(entry.name);
        return entry.size >= 10000 &&
            ImageFormats.isAcceptedPath(basenameOnly) &&
            !entry.isDir;
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      final zipEntries = rawEntries
          .map((entry) => (
                name: entry.name,
                writeTempFile: (String tempFilePath) =>
                    reader.readToFile(entry.name, File(tempFilePath)),
              ))
          .toList();

      await _processZipEntries(
        zipEntries,
        projectId,
        activeProcessingDateNotifier,
        onImagesLoaded,
        setProgressInMain,
        increaseSuccessfulImportCount,
        increasePhotosImported,
      );
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

  /// Collects valid image files from a directory recursively.
  ///
  /// Runs in an isolate to avoid blocking the UI during large directory scans.
  ///
  /// Filters using same rules as ZIP processing:
  /// - Skip hidden files/folders (starting with `.`)
  /// - Skip `.DS_Store`, `__MACOSX/`
  /// - Only allow valid image extensions
  /// - Minimum 10KB file size
  /// - Skip symlinks (prevents loops and security issues)
  /// - Enforce max depth of 50 levels
  ///
  /// Returns a [DirectoryScanResult] with found files and metadata.
  static Future<DirectoryScanResult> collectFilesFromDirectory(
    String directoryPath,
  ) async {
    final input = DirectoryScanInput(
      directoryPath: directoryPath,
      maxRecursionDepth: maxRecursionDepth,
      minImageSizeBytes: minImageSizeBytes,
      allowedExtensions: allowedImageExtensions,
    );

    // Run directory scanning in isolate to avoid UI blocking
    final result = await compute(scanDirectoryIsolateEntry, input);
    return result;
  }

  static Future<Map<String, dynamic>> tryReadExifFromBytes(
    Uint8List bytes,
  ) async {
    try {
      final exifData = await readExifFromBytes(bytes);
      // Convert ExifData.tags to Map<String, dynamic>
      final Map<String, dynamic> result = {};
      for (final entry in exifData.tags.entries) {
        result[entry.key] = entry.value;
      }
      return result;
    } catch (e) {
      return {};
    }
  }

  static Future<bool> importXFile(
    XFile file,
    int projectId,
    ValueNotifier<String> activeProcessingDateNotifier, {
    int? timestamp,
    VoidCallback? increaseSuccessfulImportCount,
    String? originalFilePath,
    String? sourceFilename,
    String? sourceRelativePath,
    String? sourceLocationType,
  }) async {
    Uint8List? bytes;
    try {
      int? imageTimestampFromExif;
      int? captureOffsetMinutes;

      if (timestamp == null) {
        bytes = await CameraUtils.readBytesInIsolate(file.path);
        final Map<String, dynamic> data = await tryReadExifFromBytes(bytes!);

        if (data.isNotEmpty) {
          (_, imageTimestampFromExif) = await GalleryUtils.parseExifDate(data);

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
          final DateTime? parsed = parseAndFormatDate(
            basename,
            activeProcessingDateNotifier,
          );
          if (parsed != null) {
            final DateTime localMidnight = DateTime(
              parsed.year,
              parsed.month,
              parsed.day,
            );
            final int utcMidnightMs =
                localMidnight.toUtc().millisecondsSinceEpoch;
            imageTimestampFromExif = utcMidnightMs;
            captureOffsetMinutes = localMidnight.timeZoneOffset.inMinutes;
          }
        }

        if (imageTimestampFromExif == null) {
          final DateTime lm = await File(file.path).lastModified();
          final DateTime localMidnight = DateTime(lm.year, lm.month, lm.day);
          final int utcMidnightMs =
              localMidnight.toUtc().millisecondsSinceEpoch;
          imageTimestampFromExif = utcMidnightMs;
          captureOffsetMinutes = localMidnight.timeZoneOffset.inMinutes;
        }

        captureOffsetMinutes ??= DateTime.fromMillisecondsSinceEpoch(
          imageTimestampFromExif,
          isUtc: true,
        ).toLocal().timeZoneOffset.inMinutes;
      } else {
        imageTimestampFromExif = timestamp;
        bytes = await CameraUtils.readBytesInIsolate(file.path);
        captureOffsetMinutes = DateTime.fromMillisecondsSinceEpoch(
          timestamp,
          isUtc: true,
        ).toLocal().timeZoneOffset.inMinutes;
      }

      final bool result = await CameraUtils.savePhoto(
        file,
        projectId,
        true,
        imageTimestampFromExif,
        bytes: bytes,
        increaseSuccessfulImportCount: increaseSuccessfulImportCount,
        originalFilePath: originalFilePath,
        sourceFilename: sourceFilename,
        sourceRelativePath: sourceRelativePath,
        sourceLocationType: sourceLocationType ?? 'direct_import',
      );

      if (result) {
        await DB.instance.setCaptureOffsetMinutesByTimestamp(
          imageTimestampFromExif.toString(),
          projectId,
          captureOffsetMinutes,
        );
      }

      return result;
    } catch (_) {
      return false;
    } finally {
      bytes = null;
    }
  }

  /// Read-only date extraction for import preview. Mirrors the date-detection
  /// logic in [importXFile] but never saves anything to disk or the database.
  ///
  /// Returns an [ImportPreviewItem] describing the best date found and the tier
  /// it came from (EXIF → Filename → File Modified). Never throws: on any
  /// error the method falls through to the fileModified tier.
  static Future<ImportPreviewItem> extractDateForPreview(
      String filePath) async {
    final (int ts, int offset, DateSourceTier tier) =
        await _extractDateTier(filePath);
    return ImportPreviewItem(
      filePath: filePath,
      filename: path.basename(filePath),
      timestampMs: ts,
      captureOffsetMinutes: offset,
      sourceTier: tier,
    );
  }

  static Future<(int, int, DateSourceTier)> _extractDateTier(
      String filePath) async {
    Future<(int, int, DateSourceTier)> fileModifiedFallback() async {
      final DateTime lm = await File(filePath).lastModified();
      final DateTime localMidnight = DateTime(lm.year, lm.month, lm.day);
      final int ts = localMidnight.toUtc().millisecondsSinceEpoch;
      final int off = localMidnight.timeZoneOffset.inMinutes;
      return (ts, off, DateSourceTier.fileModified);
    }

    try {
      int? timestampMs;
      int? captureOffsetMinutes;
      DateSourceTier sourceTier = DateSourceTier.fileModified;

      // Tier 1: EXIF
      final Uint8List? bytes = await CameraUtils.readBytesInIsolate(filePath);
      final Map<String, dynamic> exifData =
          bytes != null ? await tryReadExifFromBytes(bytes) : {};

      if (exifData.isNotEmpty) {
        (_, timestampMs) = await GalleryUtils.parseExifDate(exifData);

        if (timestampMs != null) {
          sourceTier = DateSourceTier.exif;

          final String? gpsDateStr = exifData['GPS GPSDateStamp']?.toString();
          final String? gpsTimeStr = exifData['GPS GPSTimeStamp']?.toString();
          if (gpsDateStr != null && gpsTimeStr != null) {
            captureOffsetMinutes = 0;
          } else {
            final String? rawOffset =
                exifData['EXIF OffsetTimeOriginal']?.toString() ??
                    exifData['EXIF OffsetTime']?.toString() ??
                    exifData['EXIF OffsetTimeDigitized']?.toString() ??
                    exifData['Time Zone for Original Date']?.toString() ??
                    exifData['Time Zone for Digitized Date']?.toString() ??
                    exifData['Time Zone for Modification Date']?.toString();
            if (rawOffset != null) {
              final norm = _normalizeOffset(rawOffset);
              final off = GalleryUtils.parseOffset(norm);
              if (off != null) {
                captureOffsetMinutes = off.inMinutes;
              }
            }
          }
        }
      }

      // Tier 2: filename
      if (timestampMs == null) {
        final DateTime? parsed = parseAndFormatDate(
          path.basenameWithoutExtension(filePath),
          ValueNotifier(''),
        );
        if (parsed != null) {
          final DateTime localMidnight =
              DateTime(parsed.year, parsed.month, parsed.day);
          timestampMs = localMidnight.toUtc().millisecondsSinceEpoch;
          captureOffsetMinutes = localMidnight.timeZoneOffset.inMinutes;
          sourceTier = DateSourceTier.filename;
        }
      }

      // Tier 3: file modified date
      if (timestampMs == null) {
        return fileModifiedFallback();
      }

      captureOffsetMinutes ??= DateTime.fromMillisecondsSinceEpoch(
        timestampMs,
        isUtc: true,
      ).toLocal().timeZoneOffset.inMinutes;

      return (timestampMs, captureOffsetMinutes, sourceTier);
    } catch (_) {
      return fileModifiedFallback();
    }
  }

  static DateTime? parseAndFormatDate(
    String input,
    ValueNotifier<String> activeProcessingDateNotifier,
  ) {
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

  /// Streams files directly to ZIP on disk using ZipFileEncoder.
  /// Memory usage: ~1x largest single file.
  ///
  /// Resilient: skips corrupt/unreadable files and continues.
  /// Only fails if the encoder itself can't be created or finalized.
  static void zipFiles(ZipIsolateParams params) async {
    final send = params.sendPort;
    void log(String m) => send.send({'type': 'log', 'msg': m});

    final zipPath = params.zipFilePath;
    final zipFile = File(zipPath);
    final sourceFilenames = params.sourceFilenames;

    try {
      zipFile.parent.createSync(recursive: true);
    } catch (e) {
      log('Cannot create export directory: ${zipFile.parent.path}: $e');
      send.send('error');
      return;
    }

    for (final e in params.filesToExport.entries) {
      e.value.removeWhere((p) => path.equals(p, zipPath));
    }

    if (zipFile.existsSync()) {
      try {
        zipFile.deleteSync();
      } catch (e) {
        log('Cannot delete pre-existing zip: $e');
        send.send('error');
        return;
      }
    }

    int added = 0, skipped = 0, missing = 0, badname = 0;

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

    ZipFileEncoder? encoder;
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
            log('File missing, skipping: $p');
            continue;
          }

          final base = path.basenameWithoutExtension(p);
          final ext = path.extension(p);
          int len;
          DateTime dt;

          try {
            len = f.lengthSync();
            if (len <= 0) {
              skipped++;
              log('File empty (len=$len), skipping: $p');
              continue;
            }
            final ts = int.tryParse(base);
            dt = ts != null
                ? DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true).toLocal()
                : f.lastModifiedSync();
          } catch (e) {
            skipped++;
            log('Cannot stat file, skipping: $p ($e)');
            continue;
          }

          final stamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(dt);

          var newName = '$stamp$ext';
          if (folder == 'Raw') {
            final sourceFilename = sourceFilenames[base];
            if (sourceFilename != null) {
              final sanitizedSourceFilename = path.basename(
                sourceFilename.trim(),
              );
              if (sanitizedSourceFilename.isNotEmpty) {
                newName = path.extension(sanitizedSourceFilename).isEmpty
                    ? '$sanitizedSourceFilename$ext'
                    : sanitizedSourceFilename;
              }
            }
          }

          final dup = counts[newName];
          if (dup != null) {
            final n = dup + 1;
            counts[newName] = n;
            final baseName = path.basenameWithoutExtension(newName);
            final nameExt = path.extension(newName);
            newName = '$baseName ($n)$nameExt';
          } else {
            counts[newName] = 1;
          }

          items.add((file: f, arcPath: '$folder/$newName', len: len));
        }
      }

      final totalInput = items.length + missing + skipped;
      log(
        'Export prepared: ${items.length} files to add, '
        '$missing missing, $skipped skipped, $badname bad-name '
        '(total input: $totalInput)',
      );

      if (items.isEmpty) {
        log('No exportable files found');
        send.send({
          'type': 'summary',
          'added': added,
          'skipped': skipped,
          'missing': missing,
          'badname': badname,
        });
        send.send('error');
        return;
      }

      final totalBytes = items.fold<int>(0, (s, it) => s + it.len);
      var stagedBytes = 0;
      log(
        'Total bytes to archive: $totalBytes '
        '(${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB)',
      );

      // Use ZipFileEncoder for streaming - writes directly to disk
      // level: 0 (store) = no compression, faster for already-compressed media
      encoder = ZipFileEncoder();
      try {
        encoder.create(zipPath, level: ZipFileEncoder.store);
      } catch (e, st) {
        log('Cannot create ZIP encoder at $zipPath: $e\n$st');
        send.send({
          'type': 'summary',
          'added': 0,
          'skipped': skipped,
          'missing': missing,
          'badname': badname,
        });
        send.send('error');
        return;
      }
      log('ZIP encoder created at: $zipPath');

      for (int i = 0; i < items.length; i++) {
        final it = items[i];
        try {
          await encoder.addFile(it.file, it.arcPath, ZipFileEncoder.store);
          added++;

          stagedBytes += it.len;
          final pct = totalBytes == 0 ? 0.0 : (stagedBytes / totalBytes) * 98.0;
          send.send(pct);
        } catch (e, st) {
          skipped++;
          log(
            'addFile failed [${i + 1}/${items.length}] '
            '${it.file.path} (${it.len} bytes): $e',
          );
          log('stack: $st');
          // Continue to next file instead of aborting
          continue;
        }
      }

      log('All files processed: added=$added, skipped=$skipped');

      if (added == 0) {
        log('No files were successfully added to the ZIP');
        try {
          encoder.close();
        } catch (_) {}
        encoder = null;
        send.send({
          'type': 'summary',
          'added': 0,
          'skipped': skipped,
          'missing': missing,
          'badname': badname,
        });
        DirUtils.safeDeleteFileSync(zipPath);
        send.send('error');
        return;
      }

      // Finalize ZIP — this writes the central directory and closes the file
      log('Closing ZIP encoder (added=$added files)...');
      try {
        await encoder.close();
      } catch (e, st) {
        log('encoder.close() failed: $e\n$st');
        encoder = null;
        send.send({
          'type': 'summary',
          'added': added,
          'skipped': skipped,
          'missing': missing,
          'badname': badname,
        });
        DirUtils.safeDeleteFileSync(zipPath);
        send.send('error');
        return;
      }
      encoder = null;

      // Verify the ZIP file was written successfully
      if (!zipFile.existsSync()) {
        log('ZIP file missing after close: $zipPath');
        send.send({
          'type': 'summary',
          'added': added,
          'skipped': skipped,
          'missing': missing,
          'badname': badname,
        });
        send.send('error');
        return;
      }

      final zipLen = zipFile.lengthSync();
      if (zipLen <= 0) {
        log('ZIP file is empty after close: $zipPath (length=$zipLen)');
        DirUtils.safeDeleteFileSync(zipPath);
        send.send({
          'type': 'summary',
          'added': added,
          'skipped': skipped,
          'missing': missing,
          'badname': badname,
        });
        send.send('error');
        return;
      }

      log(
        'ZIP created: $zipLen bytes '
        '(${(zipLen / 1024 / 1024).toStringAsFixed(1)} MB), '
        '$added files',
      );

      send.send({
        'type': 'summary',
        'added': added,
        'skipped': skipped,
        'missing': missing,
        'badname': badname,
      });
      send.send(100.0);
      send.send('success');
    } catch (e, st) {
      log('zipFiles crashed: $e\n$st');
      try {
        await encoder?.close();
      } catch (_) {}
      send.send({
        'type': 'summary',
        'added': added,
        'skipped': skipped,
        'missing': missing,
        'badname': badname,
      });
      DirUtils.safeDeleteFileSync(zipPath);
      send.send('error');
    }
  }

  static Future<String> exportZipFile(
    int projectId,
    String projectName,
    Map<String, List<String>> filesToExport,
    void Function(double exportProgressIn) setExportProgress,
  ) async {
    try {
      final rawCount = filesToExport['Raw']?.length ?? 0;
      final stabCount = filesToExport['Stabilized']?.length ?? 0;
      LogService.instance.log(
        '[zip] Starting export: project=$projectId "$projectName", '
        'raw=$rawCount, stabilized=$stabCount',
      );

      String zipTargetPath;
      String zipWorkPath;
      final rawTimestamps = (filesToExport['Raw'] ?? const <String>[])
          .map(path.basenameWithoutExtension)
          .where((timestamp) => timestamp.isNotEmpty)
          .toSet()
          .toList();
      final sourceFilenames = await DB.instance.getSourceFilenamesBatch(
        rawTimestamps,
        projectId,
      );

      if (isMobile || test_config.isTestMode) {
        zipWorkPath = await DirUtils.getZipFileExportPath(
          projectId,
          projectName,
        );
        final exportsDir = File(zipWorkPath).parent;
        if (!await exportsDir.exists()) {
          await exportsDir.create(recursive: true);
        }
        zipTargetPath = zipWorkPath;
      } else {
        final tmpDir = await DirUtils.getTemporaryDirPath();
        final tmpName = ExportNamingUtils.generateZipFilename(
          projectName: projectName,
        );
        zipWorkPath = path.join(tmpDir, tmpName);
        final workDir = File(zipWorkPath).parent;
        if (!await workDir.exists()) {
          await workDir.create(recursive: true);
        }
        zipTargetPath = '';
      }

      final receivePort = ReceivePort();
      final errorPort = ReceivePort();
      final exitPort = ReceivePort();
      final completer = Completer<String>();
      Isolate? isolate;

      // Inactivity timeout - reset on each progress message
      const inactivityLimit = Duration(minutes: 5);
      Timer? inactivityTimer;

      void cleanup() {
        inactivityTimer?.cancel();
        receivePort.close();
        errorPort.close();
        exitPort.close();
      }

      void resetInactivityTimer() {
        inactivityTimer?.cancel();
        inactivityTimer = Timer(inactivityLimit, () {
          if (!completer.isCompleted) {
            LogService.instance.log(
              '[zip] Isolate killed: no progress for $inactivityLimit',
            );
            isolate?.kill(priority: Isolate.immediate);
            completer.complete('error');
            cleanup();
          }
        });
      }

      // Handle isolate errors (uncaught exceptions)
      errorPort.listen((error) {
        LogService.instance.log('[zip] Isolate error: $error');
        if (!completer.isCompleted) {
          completer.complete('error');
          cleanup();
        }
      });

      // Handle isolate exit (crash, OOM, or normal termination without result)
      exitPort.listen((_) {
        if (!completer.isCompleted) {
          LogService.instance.log(
            '[zip] Isolate exited without sending result',
          );
          completer.complete('error');
          cleanup();
        }
      });

      // Handle normal messages from isolate
      receivePort.listen((message) {
        resetInactivityTimer(); // Reset on any message

        if (message == 'success' || message == 'error') {
          if (!completer.isCompleted) {
            completer.complete(message as String);
            cleanup();
          }
          return;
        }
        if (message is Map && message['type'] == 'log') {
          LogService.instance.log('[zip] ${message['msg']}');
          return;
        }
        if (message is Map && message['type'] == 'summary') {
          final added = message['added'] ?? 0;
          final skipped = message['skipped'] ?? 0;
          final missing = message['missing'] ?? 0;
          final badname = message['badname'] ?? 0;
          LogService.instance.log(
            '[zip] Summary: added=$added, skipped=$skipped, '
            'missing=$missing, badname=$badname',
          );
          if (added == 0) {
            LogService.instance.log('[zip] WARNING: 0 files added to ZIP');
          }
          return;
        }
        if (message is double) {
          setExportProgress(message);
          return;
        }
        if (message is String) {
          final p = double.tryParse(message);
          if (p != null) {
            setExportProgress(p);
            return;
          }
        }
      });

      isolate = await Isolate.spawn(
        zipFiles,
        ZipIsolateParams(
          receivePort.sendPort,
          projectId,
          projectName,
          filesToExport,
          zipWorkPath,
          sourceFilenames,
        ),
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
      );

      // Start inactivity timer
      resetInactivityTimer();

      final result = await completer.future;

      if (!isMobile && !test_config.isTestMode && result == 'success') {
        final suggested = ExportNamingUtils.generateZipFilename(
          projectName: projectName,
        );
        final location = await getSaveLocation(
          suggestedName: suggested,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'zip', extensions: ['zip']),
          ],
        );
        if (location == null) {
          DirUtils.safeDeleteFileSync(zipWorkPath);
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
        DirUtils.safeDeleteFileSync(zipWorkPath);
      }

      LogService.instance.log('[zip] Export result: $result');
      return result;
    } catch (e, st) {
      LogService.instance.log('[zip] exportZipFile crashed: $e\n$st');
      return 'error';
    }
  }

  /// Returns the path of the numerically-first PNG in [dirPath], or null if
  /// the directory does not exist or contains no PNG files.
  static Future<String?> checkForStabilizedImage(String dirPath) async {
    final directory = Directory(dirPath);
    if (!await directory.exists()) return null;
    try {
      final pngFiles = await directory
          .list()
          .where((item) => item.path.endsWith('.png') && item is File)
          .toList();
      if (pngFiles.isEmpty) return null;
      final minFile = pngFiles.reduce(
        (a, b) =>
            GalleryUtils.compareByNumericBasename(a.path, b.path) <= 0 ? a : b,
      );
      return minFile.path;
    } catch (e) {
      return null;
    }
  }
}

class ZipIsolateParams {
  final SendPort sendPort;
  final int projectId;
  final String projectName;
  final Map<String, List<String>> filesToExport;
  final String zipFilePath;
  final Map<String, String> sourceFilenames;

  ZipIsolateParams(
    this.sendPort,
    this.projectId,
    this.projectName,
    this.filesToExport,
    this.zipFilePath,
    this.sourceFilenames,
  );
}
