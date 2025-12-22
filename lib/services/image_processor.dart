import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as path;

import '../utils/gallery_utils.dart';
import '../utils/camera_utils.dart';

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
    try {
      XFile xFile = XFile(imagePath!);

      final String extension = path.extension(imagePath!).toLowerCase();
      if (extension == ".avif") {
        final Uint8List? avifBytes =
            await CameraUtils.readBytesInIsolate(imagePath!);
        int? overrideTs;
        if (avifBytes != null) {
          final Map<String, dynamic> exif =
              await GalleryUtils.tryReadExifFromBytes(avifBytes);
          if (exif.isNotEmpty) {
            final res = await GalleryUtils.parseExifDate(exif);
            overrideTs = res.$2;
          }
        }

        final String pngPath = imagePath!.replaceAll(".avif", ".png");
        await GalleryUtils.convertAvifToPng(imagePath!, pngPath);
        xFile = XFile(pngPath);

        final bool result = await GalleryUtils.importXFile(
          xFile,
          projectId!,
          activeProcessingDateNotifier!,
          timestamp: overrideTs ?? timestamp,
          increaseSuccessfulImportCount: increaseSuccessfulImportCount,
        );

        final tempFile = File(imagePath!);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }

        return result;
      }

      final bool result = await GalleryUtils.importXFile(
        xFile,
        projectId!,
        activeProcessingDateNotifier!,
        timestamp: timestamp,
        increaseSuccessfulImportCount: increaseSuccessfulImportCount,
      );

      return result;
    } catch (e) {
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
