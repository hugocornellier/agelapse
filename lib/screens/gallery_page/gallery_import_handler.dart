import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../../services/log_service.dart';
import '../../utils/dir_utils.dart';
import '../../utils/gallery_utils.dart';
import '../../utils/settings_utils.dart';
import 'gallery_bottom_sheets.dart';

/// Handles photo import operations for the gallery.
/// Manages gallery picking, file picking, and desktop drag-drop imports.
class GalleryImportHandler {
  final int projectId;
  final String projectIdStr;
  final ValueNotifier<String> activeProcessingDateNotifier;
  final VoidCallback loadImages;
  final VoidCallback refreshSettings;
  final VoidCallback stabCallback;
  final Future<void> Function() cancelStabCallback;
  final bool Function() isStabilizingRunning;
  final Future<void> Function(FilePickerResult, Future<void> Function(dynamic))
      processPickedFiles;
  final void Function(String) setProjectOrientation;
  final void Function(int)? setProgressInMain;

  // Counters
  int _photosImported = 0;
  int _successfullyImported = 0;

  GalleryImportHandler({
    required this.projectId,
    required this.projectIdStr,
    required this.activeProcessingDateNotifier,
    required this.loadImages,
    required this.refreshSettings,
    required this.stabCallback,
    required this.cancelStabCallback,
    required this.isStabilizingRunning,
    required this.processPickedFiles,
    required this.setProjectOrientation,
    this.setProgressInMain,
  });

  int get photosImported => _photosImported;
  int get successfullyImported => _successfullyImported;
  int get skippedCount => _photosImported - _successfullyImported;

  void resetCounters() {
    _photosImported = 0;
    _successfullyImported = 0;
  }

  void increasePhotosImported(int value) {
    _photosImported += value;
  }

  void increaseSuccessfulImportCount() {
    _successfullyImported++;
  }

  /// Picks photos from the device gallery using AssetPicker.
  /// Returns true if import started, false if cancelled.
  Future<bool> pickFromGallery(BuildContext context) async {
    try {
      final List<AssetEntity>? result = await AssetPicker.pickAssets(
        context,
        pickerConfig: const AssetPickerConfig(
          maxAssets: 100,
          requestType: RequestType.image,
        ),
      );
      if (result == null) {
        return false;
      }

      GalleryUtils.startImportBatch(result.length);
      for (final AssetEntity asset in result) {
        await _processAsset(asset);
      }
      refreshSettings();
      loadImages();
      stabCallback();
      return true;
    } catch (e) {
      LogService.instance.log("Error picking images: $e");
      return false;
    }
  }

  /// Picks files using the file picker.
  /// [onImportStarted] is called when import begins.
  /// [onImportComplete] is called with (imported, skipped) counts when done.
  Future<void> pickFiles({
    required VoidCallback onImportStarted,
    required void Function(int imported, int skipped) onImportComplete,
  }) async {
    try {
      resetCounters();

      FilePickerResult? pickedFiles;
      try {
        pickedFiles = await FilePicker.platform.pickFiles(allowMultiple: true);
      } catch (e) {
        LogService.instance.log(e.toString());
        return;
      }
      if (pickedFiles == null) return;

      onImportStarted();

      if (isStabilizingRunning()) {
        await cancelStabCallback();
      }

      GalleryUtils.startImportBatch(pickedFiles.files.length);
      await processPickedFiles(pickedFiles, processPickedFile);

      final String projectOrientationRaw =
          await SettingsUtil.loadProjectOrientation(projectIdStr);
      setProjectOrientation(projectOrientationRaw);

      refreshSettings();
      stabCallback();
      loadImages();

      onImportComplete(_successfullyImported, skippedCount);
    } catch (e) {
      LogService.instance.log("ERROR CAUGHT IN PICK FILES: $e");
    }
  }

  /// Handles desktop drag-drop import.
  /// [files] - List of dropped file paths.
  /// [onImportStarted] - Called when import begins.
  /// [onImportComplete] - Called with (imported, skipped) counts when done.
  Future<void> handleDesktopDrop({
    required List<String> filePaths,
    required VoidCallback onImportStarted,
    required void Function(int imported, int skipped) onImportComplete,
  }) async {
    resetCounters();
    onImportStarted();

    if (isStabilizingRunning()) {
      await cancelStabCallback();
    }

    GalleryUtils.startImportBatch(filePaths.length);
    for (final filePath in filePaths) {
      await processPickedFile(File(filePath));
    }

    final String projectOrientationRaw =
        await SettingsUtil.loadProjectOrientation(projectIdStr);
    setProjectOrientation(projectOrientationRaw);

    refreshSettings();
    stabCallback();
    loadImages();

    onImportComplete(_successfullyImported, skippedCount);
  }

  /// Processes a single picked file.
  Future<void> processPickedFile(dynamic file) async {
    await GalleryUtils.processPickedFile(
      file,
      projectId,
      activeProcessingDateNotifier,
      onImagesLoaded: loadImages,
      setProgressInMain: setProgressInMain ?? (_) {},
      increaseSuccessfulImportCount: increaseSuccessfulImportCount,
      increasePhotosImported: increasePhotosImported,
    );
  }

  /// Processes a single asset from the gallery picker.
  Future<void> _processAsset(AssetEntity asset) async {
    final Uint8List? originBytes = await asset.originBytes;
    if (originBytes == null) return;

    final String originPath = (await asset.originFile)!.path;
    final String tempOriginPhotoPath = await _getTemporaryPhotoPath(
      asset,
      originPath,
    );
    final File tempOriginFile = File(tempOriginPhotoPath);

    if (await _isModifiedLivePhoto(asset, originPath)) {
      await _writeModifiedLivePhoto(asset, tempOriginFile);
    } else {
      await tempOriginFile.writeAsBytes(originBytes);
    }

    await GalleryUtils.processPickedImage(
      tempOriginPhotoPath,
      projectId,
      activeProcessingDateNotifier,
      onImagesLoaded: loadImages,
      timestamp: asset.createDateTime.millisecondsSinceEpoch,
    );
  }

  Future<String> _getTemporaryPhotoPath(
    AssetEntity asset,
    String originPath,
  ) async {
    final String basename = path
        .basenameWithoutExtension(originPath)
        .toLowerCase()
        .replaceAll(".", "");
    final String extension = path.extension(originPath).toLowerCase();
    final String tempDir = await DirUtils.getTemporaryDirPath();
    return path.join(tempDir, "$basename$extension");
  }

  Future<bool> _isModifiedLivePhoto(
    AssetEntity asset,
    String originPath,
  ) async {
    final String extension = path.extension(originPath).toLowerCase();
    return asset.isLivePhoto && (extension == ".jpg" || extension == ".jpeg");
  }

  Future<void> _writeModifiedLivePhoto(
    AssetEntity asset,
    File tempOriginFile,
  ) async {
    File? assetFile = await asset.file;
    var bytes = await assetFile?.readAsBytes();
    if (bytes != null) {
      await tempOriginFile.writeAsBytes(bytes);
    }
  }

  /// Shows the import options bottom sheet.
  static void showImportOptionsSheet({
    required BuildContext context,
    required bool isImporting,
    required VoidCallback onPickFromGallery,
    required VoidCallback onPickFiles,
    required Widget? desktopDropZone,
  }) {
    final bool isMobile = Platform.isAndroid || Platform.isIOS;
    final bool isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    final List<Widget> content = [
      if (isMobile) ...[
        GalleryBottomSheets.buildImportOptionTile(
          icon: Icons.photo_library_outlined,
          title: 'Photo Library',
          subtitle: 'Select photos from your device',
          onTap: isImporting ? null : onPickFromGallery,
        ),
        const SizedBox(height: 10),
      ],
      GalleryBottomSheets.buildImportOptionTile(
        icon: Icons.folder_outlined,
        title: isDesktop ? 'Browse Files' : 'Files',
        subtitle:
            isDesktop ? 'Select images or folders' : 'Import from file manager',
        onTap: isImporting ? null : onPickFiles,
      ),
      if (isDesktop && desktopDropZone != null) ...[
        const SizedBox(height: 16),
        desktopDropZone,
      ],
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return GalleryBottomSheets.buildOptionsSheet(
          context,
          'Import Photos',
          content,
        );
      },
    );
  }
}
