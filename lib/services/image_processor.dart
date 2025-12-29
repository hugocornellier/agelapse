import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as path;

import '../utils/gallery_utils.dart';
import '../utils/camera_utils.dart';
import 'log_service.dart';

class ImageProcessor {
  String? imagePath;
  int? projectId;
  ValueNotifier<String>? activeProcessingDateNotifier;
  Function? onImagesLoaded;
  int? timestamp;
  VoidCallback? increaseSuccessfulImportCount;

  ImageProcessor({
    required this.imagePath,
    required this.projectId,
    required this.activeProcessingDateNotifier,
    required this.onImagesLoaded,
    this.timestamp,
    this.increaseSuccessfulImportCount,
  });

  Future<bool> process() async {
    final String filename = path.basename(imagePath ?? 'unknown');
    LogService.instance.log('[ImageProcessor] START processing: $filename');
    try {
      XFile xFile = XFile(imagePath!);

      final String extension = path.extension(imagePath!).toLowerCase();
      LogService.instance.log('[ImageProcessor] File extension: $extension');

      if (extension == ".avif") {
        LogService.instance.log(
            '[ImageProcessor] AVIF detected, starting conversion for: $filename');

        final Uint8List? avifBytes =
            await CameraUtils.readBytesInIsolate(imagePath!);
        LogService.instance.log(
            '[ImageProcessor] Read AVIF bytes: ${avifBytes?.length ?? 'NULL'} bytes');

        int? overrideTs;
        if (avifBytes != null) {
          final Map<String, dynamic> exif =
              await GalleryUtils.tryReadExifFromBytes(avifBytes);
          LogService.instance
              .log('[ImageProcessor] AVIF EXIF data: ${exif.keys.toList()}');
          if (exif.isNotEmpty) {
            final res = await GalleryUtils.parseExifDate(exif);
            overrideTs = res.$2;
            LogService.instance
                .log('[ImageProcessor] AVIF parsed timestamp: $overrideTs');
          }
        }

        final String pngPath = imagePath!.replaceAll(".avif", ".png");
        LogService.instance
            .log('[ImageProcessor] Converting AVIF to PNG: $pngPath');

        final bool conversionSuccess =
            await GalleryUtils.convertAvifToPng(imagePath!, pngPath);
        LogService.instance
            .log('[ImageProcessor] AVIF conversion result: $conversionSuccess');

        if (!conversionSuccess) {
          LogService.instance.log(
              '[ImageProcessor] AVIF CONVERSION FAILED for: $filename - SKIPPING');
          return false;
        }

        final File pngFile = File(pngPath);
        final bool pngExists = await pngFile.exists();
        LogService.instance.log(
            '[ImageProcessor] PNG file exists after conversion: $pngExists');

        if (!pngExists) {
          LogService.instance.log(
              '[ImageProcessor] PNG file not created for: $filename - SKIPPING');
          return false;
        }

        xFile = XFile(pngPath);

        LogService.instance.log(
            '[ImageProcessor] Importing converted PNG with timestamp: ${overrideTs ?? timestamp}');
        final bool result = await GalleryUtils.importXFile(
          xFile,
          projectId!,
          activeProcessingDateNotifier!,
          timestamp: overrideTs ?? timestamp,
          increaseSuccessfulImportCount: increaseSuccessfulImportCount,
        );
        LogService.instance
            .log('[ImageProcessor] Import result for AVIF->PNG: $result');

        final tempFile = File(imagePath!);
        if (await tempFile.exists()) {
          LogService.instance
              .log('[ImageProcessor] Deleting original AVIF: $filename');
          await tempFile.delete();
        }

        LogService.instance.log(
            '[ImageProcessor] END AVIF processing: $filename -> result=$result');
        return result;
      }

      LogService.instance
          .log('[ImageProcessor] Importing non-AVIF file: $filename');
      final bool result = await GalleryUtils.importXFile(
        xFile,
        projectId!,
        activeProcessingDateNotifier!,
        timestamp: timestamp,
        increaseSuccessfulImportCount: increaseSuccessfulImportCount,
      );

      LogService.instance
          .log('[ImageProcessor] END processing: $filename -> result=$result');
      return result;
    } catch (e, stackTrace) {
      LogService.instance.log('[ImageProcessor] EXCEPTION for $filename: $e');
      LogService.instance.log('[ImageProcessor] Stack trace: $stackTrace');
      return false;
    } finally {
      dispose();
    }
  }

  void dispose() {
    imagePath = null;
    projectId = null;
    activeProcessingDateNotifier = null;
    onImagesLoaded = null;
    timestamp = null;
    increaseSuccessfulImportCount = null;
  }
}
