import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as path;
import '../utils/gallery_utils.dart';

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

      final String extension = path.extension(imagePath!);
      if (extension == ".avif") {
        final String pngPath = imagePath!.replaceAll(".avif", ".png");
        await GalleryUtils.convertAvifToPng(imagePath!, pngPath);
        xFile = XFile(pngPath);
      }

      final bool result = await GalleryUtils.importXFile(
        xFile,
        projectId!,
        activeProcessingDateNotifier!,
        timestamp: timestamp,
        increaseSuccessfulImportCount: increaseSuccessfulImportCount,
      );

      if (result) {
        //onImagesLoaded!();
      }

      // Clean up temporary files if any were created
      if (extension == ".avif") {
        final tempFile = File(imagePath!);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }

      return result;
    } catch (e) {
      return false;
    } finally {
      dispose();
    }
  }

  void dispose() {
    // Clean up resources if needed
    imagePath = null;
    projectId = null;
    activeProcessingDateNotifier = null;
    onImagesLoaded = null;
    timestamp = null;
    increaseSuccessfulImportCount = null;
  }
}
