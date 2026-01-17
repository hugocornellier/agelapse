import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/database_helper.dart';
import '../../services/log_service.dart';
import '../../styles/styles.dart';
import '../../utils/capture_timezone.dart';
import '../../utils/date_stamp_utils.dart';
import '../../utils/dir_utils.dart';
import '../../utils/gallery_utils.dart';
import '../../utils/settings_utils.dart';
import 'gallery_bottom_sheets.dart';

/// Handles photo export operations for the gallery.
class GalleryExportHandler {
  /// Shows the export options bottom sheet.
  static void showExportOptionsSheet({
    required BuildContext context,
    required int projectId,
    required String projectName,
    required String projectIdStr,
    required String? projectOrientation,
    required List<String> rawImageFiles,
    required Future<List<String>> Function(String) listFilesInDirectory,
  }) {
    bool exportRawFiles = true;
    bool exportStabilizedFiles = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        bool localExportingToZip = false;
        bool exportSuccessful = false;
        double exportProgressPercent = 0;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            void setExportProgress(double exportProgressIn) {
              setState(() {
                exportProgressPercent = (exportProgressIn * 10).round() / 10;
              });
            }

            List<Widget> content = [
              if (!localExportingToZip && !exportSuccessful) ...[
                GalleryBottomSheets.buildExportOptionToggle(
                  icon: Icons.image_outlined,
                  title: 'Raw Photos',
                  subtitle: 'Original unprocessed images',
                  isSelected: exportRawFiles,
                  onChanged: (value) => setState(() => exportRawFiles = value),
                ),
                const SizedBox(height: 10),
                GalleryBottomSheets.buildExportOptionToggle(
                  icon: Icons.auto_fix_high_outlined,
                  title: 'Stabilized Photos',
                  subtitle: 'Face-aligned processed images',
                  isSelected: exportStabilizedFiles,
                  onChanged: (value) =>
                      setState(() => exportStabilizedFiles = value),
                ),
                const SizedBox(height: 20),
                _buildExportButton(
                  context: context,
                  exportRawFiles: exportRawFiles,
                  exportStabilizedFiles: exportStabilizedFiles,
                  projectId: projectId,
                  projectName: projectName,
                  projectIdStr: projectIdStr,
                  projectOrientation: projectOrientation,
                  rawImageFiles: rawImageFiles,
                  listFilesInDirectory: listFilesInDirectory,
                  setExportProgress: setExportProgress,
                  onExportStarted: () =>
                      setState(() => localExportingToZip = true),
                  onExportComplete: (success) {
                    setState(() {
                      localExportingToZip = false;
                      exportSuccessful = success;
                    });
                    if (success && (Platform.isAndroid || Platform.isIOS)) {
                      shareZipFile(projectId, projectName);
                    }
                  },
                ),
              ],
              if (localExportingToZip) ...[
                GalleryBottomSheets.buildExportProgressIndicator(
                    exportProgressPercent),
              ],
              if (!localExportingToZip && exportSuccessful) ...[
                GalleryBottomSheets.buildExportSuccessState(),
              ],
            ];

            return GalleryBottomSheets.buildOptionsSheet(
              context,
              'Export Photos',
              content,
            );
          },
        );
      },
    );
  }

  static Widget _buildExportButton({
    required BuildContext context,
    required bool exportRawFiles,
    required bool exportStabilizedFiles,
    required int projectId,
    required String projectName,
    required String projectIdStr,
    required String? projectOrientation,
    required List<String> rawImageFiles,
    required Future<List<String>> Function(String) listFilesInDirectory,
    required void Function(double) setExportProgress,
    required VoidCallback onExportStarted,
    required void Function(bool success) onExportComplete,
  }) {
    return GestureDetector(
      onTap: () async {
        if (!exportRawFiles && !exportStabilizedFiles) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please select at least one type of files to export',
              ),
            ),
          );
          return;
        }

        onExportStarted();

        final success = await _performExport(
          projectId: projectId,
          projectName: projectName,
          projectIdStr: projectIdStr,
          projectOrientation: projectOrientation,
          exportRawFiles: exportRawFiles,
          exportStabilizedFiles: exportStabilizedFiles,
          rawImageFiles: rawImageFiles,
          listFilesInDirectory: listFilesInDirectory,
          setExportProgress: setExportProgress,
        );

        onExportComplete(success);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: (exportRawFiles || exportStabilizedFiles)
              ? AppColors.settingsAccent
              : AppColors.settingsAccent.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'Export to ZIP',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  static Future<bool> _performExport({
    required int projectId,
    required String projectName,
    required String projectIdStr,
    required String? projectOrientation,
    required bool exportRawFiles,
    required bool exportStabilizedFiles,
    required List<String> rawImageFiles,
    required Future<List<String>> Function(String) listFilesInDirectory,
    required void Function(double) setExportProgress,
  }) async {
    String? dateStampTempDir;
    try {
      Map<String, List<String>> filesToExport = {
        'Raw': [],
        'Stabilized': [],
      };

      if (exportRawFiles) {
        filesToExport['Raw']!.addAll(rawImageFiles);
      }

      if (exportStabilizedFiles) {
        String stabilizedDir =
            await DirUtils.getStabilizedDirPathFromProjectIdAndOrientation(
          projectId,
          projectOrientation!,
        );
        List<String> stabilizedFiles =
            await listFilesInDirectory(stabilizedDir);

        // Check if date stamp export is enabled
        final dateStampEnabled =
            await SettingsUtil.loadExportDateStampEnabled(projectIdStr);
        LogService.instance.log(
          "[EXPORT] Date stamp enabled: $dateStampEnabled, stabilized files: ${stabilizedFiles.length}",
        );

        if (dateStampEnabled && stabilizedFiles.isNotEmpty) {
          // Load date stamp settings
          final dateFormat =
              await SettingsUtil.loadExportDateStampFormat(projectIdStr);
          final datePosition =
              await SettingsUtil.loadExportDateStampPosition(projectIdStr);
          final dateSize =
              await SettingsUtil.loadExportDateStampSize(projectIdStr);
          final dateOpacity =
              await SettingsUtil.loadExportDateStampOpacity(projectIdStr);

          // Load watermark settings for overlap prevention
          final watermarkEnabled =
              await SettingsUtil.loadWatermarkSetting(projectIdStr);
          final String? watermarkPos = watermarkEnabled
              ? (await DB.instance.getSettingValueByTitle('watermark_position'))
                  .toLowerCase()
              : null;

          // Load timezone offsets for accurate date stamps
          final captureOffsetMap = await CaptureTimezone.loadOffsetsForFiles(
            stabilizedFiles,
            projectId,
          );

          // Create temp directory for date-stamped files
          final tempBase = await DirUtils.getTemporaryDirPath();
          dateStampTempDir =
              '$tempBase/date_stamp_export_${DateTime.now().millisecondsSinceEpoch}';

          // Pre-process files with date stamps
          final processedMap = await DateStampUtils.processBatchWithDateStamps(
            inputPaths: stabilizedFiles,
            tempDir: dateStampTempDir,
            format: dateFormat,
            position: datePosition,
            sizePercent: dateSize,
            opacity: dateOpacity,
            captureOffsetMap: captureOffsetMap,
            watermarkPosition: watermarkPos,
            onProgress: (current, total) {
              // Show progress during pre-processing (0-30%)
              setExportProgress((current / total) * 30);
            },
          );

          // Use processed files for export
          filesToExport['Stabilized']!.addAll(
            stabilizedFiles.map(
              (original) => processedMap[original] ?? original,
            ),
          );
        } else {
          filesToExport['Stabilized']!.addAll(stabilizedFiles);
        }
      }

      // Adjust progress callback to account for pre-processing
      void adjustedProgress(double p) {
        // Map export progress (0-100) to (30-100) if date stamp was used
        if (dateStampTempDir != null) {
          setExportProgress(30 + (p * 0.7));
        } else {
          setExportProgress(p);
        }
      }

      String res = await GalleryUtils.exportZipFile(
        projectId,
        projectName,
        filesToExport,
        adjustedProgress,
      );

      return res == 'success';
    } catch (e) {
      LogService.instance.log(e.toString());
      return false;
    } finally {
      // Clean up temp directory
      if (dateStampTempDir != null) {
        try {
          final dir = Directory(dateStampTempDir);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        } catch (_) {}
      }
    }
  }

  /// Shares the exported ZIP file using the system share dialog.
  static Future<void> shareZipFile(int projectId, String projectName) async {
    String zipFileExportPath = await DirUtils.getZipFileExportPath(
      projectId,
      projectName,
    );
    final params = ShareParams(files: [XFile(zipFileExportPath)]);
    await SharePlus.instance.share(params);
  }

  /// Exports selected photos to a ZIP file.
  /// Used by selection mode export.
  static Future<bool> exportSelectedPhotos({
    required int projectId,
    required String projectName,
    required String projectIdStr,
    required String? projectOrientation,
    required Set<String> selectedPhotos,
    required bool exportRawFiles,
    required bool exportStabilizedFiles,
    required void Function(double) setExportProgress,
  }) async {
    String? dateStampTempDir;
    try {
      Map<String, List<String>> filesToExport = {
        'Raw': [],
        'Stabilized': [],
      };

      for (final photoPath in selectedPhotos) {
        final bool isRaw = photoPath.contains(DirUtils.photosRawDirname);
        if (isRaw && exportRawFiles) {
          filesToExport['Raw']!.add(photoPath);
        } else if (!isRaw && exportStabilizedFiles) {
          filesToExport['Stabilized']!.add(photoPath);
        }
      }

      // Check if date stamp export is enabled for stabilized files
      if (filesToExport['Stabilized']!.isNotEmpty) {
        final dateStampEnabled =
            await SettingsUtil.loadExportDateStampEnabled(projectIdStr);

        if (dateStampEnabled) {
          final stabilizedFiles = filesToExport['Stabilized']!;

          // Load date stamp settings
          final dateFormat =
              await SettingsUtil.loadExportDateStampFormat(projectIdStr);
          final datePosition =
              await SettingsUtil.loadExportDateStampPosition(projectIdStr);
          final dateSize =
              await SettingsUtil.loadExportDateStampSize(projectIdStr);
          final dateOpacity =
              await SettingsUtil.loadExportDateStampOpacity(projectIdStr);

          // Load watermark settings
          final watermarkEnabled =
              await SettingsUtil.loadWatermarkSetting(projectIdStr);
          final String? watermarkPos = watermarkEnabled
              ? (await DB.instance.getSettingValueByTitle('watermark_position'))
                  .toLowerCase()
              : null;

          // Load timezone offsets
          final captureOffsetMap = await CaptureTimezone.loadOffsetsForFiles(
            stabilizedFiles,
            projectId,
          );

          // Create temp directory
          final tempBase = await DirUtils.getTemporaryDirPath();
          dateStampTempDir =
              '$tempBase/date_stamp_export_${DateTime.now().millisecondsSinceEpoch}';

          // Pre-process files with date stamps
          final processedMap = await DateStampUtils.processBatchWithDateStamps(
            inputPaths: stabilizedFiles,
            tempDir: dateStampTempDir,
            format: dateFormat,
            position: datePosition,
            sizePercent: dateSize,
            opacity: dateOpacity,
            captureOffsetMap: captureOffsetMap,
            watermarkPosition: watermarkPos,
            onProgress: (current, total) {
              setExportProgress((current / total) * 30);
            },
          );

          // Replace with processed files
          filesToExport['Stabilized'] = stabilizedFiles
              .map((original) => processedMap[original] ?? original)
              .toList();
        }
      }

      void adjustedProgress(double p) {
        if (dateStampTempDir != null) {
          setExportProgress(30 + (p * 0.7));
        } else {
          setExportProgress(p);
        }
      }

      String res = await GalleryUtils.exportZipFile(
        projectId,
        projectName,
        filesToExport,
        adjustedProgress,
      );

      if (res == 'success' && (Platform.isAndroid || Platform.isIOS)) {
        await shareZipFile(projectId, projectName);
      }

      return res == 'success';
    } catch (e) {
      LogService.instance.log(e.toString());
      return false;
    } finally {
      if (dateStampTempDir != null) {
        try {
          final dir = Directory(dateStampTempDir);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        } catch (_) {}
      }
    }
  }

  /// Lists all files in a directory.
  static Future<List<String>> listFilesInDirectory(String dirPath) async {
    Directory directory = Directory(dirPath);
    List<String> filePaths = [];
    if (await directory.exists()) {
      await for (final file in directory.list()) {
        if (file is File) {
          filePaths.add(file.path);
        }
      }
    }
    return filePaths;
  }
}
