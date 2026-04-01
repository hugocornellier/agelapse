import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as path;

import '../utils/gallery_utils.dart';
import '../utils/camera_utils.dart';
import 'raw_decoder.dart';

class ImageProcessor {
  String? imagePath;
  int? projectId;
  ValueNotifier<String>? activeProcessingDateNotifier;
  int? timestamp;
  VoidCallback? increaseSuccessfulImportCount;
  String? originalFilePath;
  String? sourceFilename;

  ImageProcessor({
    required this.imagePath,
    required this.projectId,
    required this.activeProcessingDateNotifier,
    this.timestamp,
    this.increaseSuccessfulImportCount,
    this.originalFilePath,
    this.sourceFilename,
  });

  Future<bool> process() async {
    try {
      final XFile xFile = XFile(imagePath!);
      final String extension = path.extension(imagePath!).toLowerCase();

      // For AVIF and RAW formats, extract EXIF timestamp from the original
      // bytes before import. importXFile's internal EXIF parser may not
      // handle these formats, so we pre-extract and pass as an override.
      // No format conversion is performed — the original file is imported
      // as-is.
      int? overrideTs;
      if (extension == ".avif" || RawDecoder.isRawExtension(extension)) {
        final Uint8List? bytes = await CameraUtils.readBytesInIsolate(
          imagePath!,
        );
        if (bytes != null) {
          final Map<String, dynamic> exif =
              await GalleryUtils.tryReadExifFromBytes(bytes);
          if (exif.isNotEmpty) {
            final res = await GalleryUtils.parseExifDate(exif);
            overrideTs = res.$2;
          }
        }
      }

      final bool result = await GalleryUtils.importXFile(
        xFile,
        projectId!,
        activeProcessingDateNotifier!,
        timestamp: overrideTs ?? timestamp,
        increaseSuccessfulImportCount: increaseSuccessfulImportCount,
        originalFilePath: originalFilePath ?? imagePath,
        sourceFilename: sourceFilename,
      );

      return result;
    } catch (_) {
      return false;
    } finally {
      dispose();
    }
  }

  void dispose() {
    imagePath = null;
    projectId = null;
    activeProcessingDateNotifier = null;
    timestamp = null;
    increaseSuccessfulImportCount = null;
    originalFilePath = null;
    sourceFilename = null;
  }
}
