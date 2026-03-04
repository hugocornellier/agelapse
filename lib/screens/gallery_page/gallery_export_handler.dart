import 'dart:io';

import 'package:downloadsfolder/downloadsfolder.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
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
                  onExportComplete: (success) async {
                    if (success && Platform.isAndroid) {
                      // Android: Save directly to Downloads via MediaStore
                      final (saved, error) = await saveZipToDownloads(
                        projectId,
                        projectName,
                      );
                      setState(() {
                        localExportingToZip = false;
                        exportSuccessful = saved;
                      });
                      if (saved) {
                        LogService.instance.log('[EXPORT] Saved to Downloads');
                      } else if (error == 'save_failed') {
                        // Downloads save failed, fall back to share sheet
                        LogService.instance.log(
                          '[EXPORT] Downloads save failed, using share sheet',
                        );
                        await shareZipFile(projectId, projectName);
                        setState(() => exportSuccessful = true);
                      } else {
                        LogService.instance.log('[EXPORT] Save failed: $error');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Export failed: $error')),
                          );
                        }
                      }
                    } else if (success && Platform.isIOS) {
                      // iOS: Share sheet is the expected UX
                      setState(() {
                        localExportingToZip = false;
                        exportSuccessful = true;
                      });
                      await shareZipFile(projectId, projectName);
                    } else {
                      // Desktop or failure
                      setState(() {
                        localExportingToZip = false;
                        exportSuccessful = success;
                      });
                      if (!success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Export failed. Please try again or check app logs.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
              if (localExportingToZip) ...[
                GalleryBottomSheets.buildExportProgressIndicator(
                  exportProgressPercent,
                ),
              ],
              if (!localExportingToZip && exportSuccessful) ...[
                GalleryBottomSheets.buildExportSuccessState(
                  onShare: Platform.isAndroid
                      ? () => shareZipFile(projectId, projectName)
                      : null,
                ),
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
        child: Center(
          child: Text(
            'Export to ZIP',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: AppTypography.lg,
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
      Map<String, List<String>> filesToExport = {'Raw': [], 'Stabilized': []};

      if (exportRawFiles) {
        filesToExport['Raw']!.addAll(rawImageFiles);
      }

      if (exportStabilizedFiles) {
        String stabilizedDir =
            await DirUtils.getStabilizedDirPathFromProjectIdAndOrientation(
          projectId,
          projectOrientation!,
        );
        List<String> stabilizedFiles = await listFilesInDirectory(
          stabilizedDir,
        );

        // Check if date stamp export is enabled
        final dateStampEnabled = await SettingsUtil.loadExportDateStampEnabled(
          projectIdStr,
        );
        LogService.instance.log(
          "[EXPORT] Date stamp enabled: $dateStampEnabled, stabilized files: ${stabilizedFiles.length}",
        );

        if (dateStampEnabled && stabilizedFiles.isNotEmpty) {
          // Load date stamp settings
          final dateFormat = await SettingsUtil.loadExportDateStampFormat(
            projectIdStr,
          );
          final datePosition = await SettingsUtil.loadExportDateStampPosition(
            projectIdStr,
          );
          final dateSize = await SettingsUtil.loadExportDateStampSize(
            projectIdStr,
          );
          final gallerySize = await SettingsUtil.loadGalleryDateStampSize(
            projectIdStr,
          );
          final resolvedSize = DateStampUtils.resolveExportSize(
            dateSize,
            gallerySize,
          );
          final dateOpacity = await SettingsUtil.loadExportDateStampOpacity(
            projectIdStr,
          );
          final exportFont = await SettingsUtil.loadExportDateStampFont(
            projectIdStr,
          );
          final galleryFont = await SettingsUtil.loadGalleryDateStampFont(
            projectIdStr,
          );
          final resolvedFont = DateStampUtils.resolveExportFont(
            exportFont,
            galleryFont,
          );

          // Load watermark settings for overlap prevention
          final watermarkEnabled = await SettingsUtil.loadWatermarkSetting(
            projectIdStr,
          );
          final String? watermarkPos = watermarkEnabled
              ? (await DB.instance.getSettingValueByTitle(
                  'watermark_position',
                ))
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
            sizePercent: resolvedSize,
            opacity: dateOpacity,
            captureOffsetMap: captureOffsetMap,
            watermarkPosition: watermarkPos,
            onProgress: (current, total) {
              // Show progress during pre-processing (0-30%)
              setExportProgress((current / total) * 30);
            },
            fontFamily: resolvedFont,
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

      if (res != 'success') {
        LogService.instance.log(
          '[EXPORT] Failed: raw=${filesToExport['Raw']?.length ?? 0}, '
          'stabilized=${filesToExport['Stabilized']?.length ?? 0}',
        );
      }

      return res == 'success';
    } catch (e, st) {
      LogService.instance.log('[EXPORT] _performExport crashed: $e\n$st');
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

  /// Cleans up old exports from private storage to prevent bloat.
  /// Keeps only the most recent export for the Share button.
  static Future<void> _cleanupOldPrivateExports(int projectId) async {
    try {
      final exportsDir = Directory(await DirUtils.getExportsDirPath(projectId));
      if (!await exportsDir.exists()) return;

      final files = await exportsDir
          .list()
          .where((e) => e is File && e.path.endsWith('.zip'))
          .cast<File>()
          .toList();

      // Sort by modification time, newest first
      files.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });

      // Delete all but the newest (which will be replaced by current export)
      for (int i = 1; i < files.length; i++) {
        try {
          await files[i].delete();
          LogService.instance.log(
            '[EXPORT] Cleaned up old export: ${files[i].path}',
          );
        } catch (_) {}
      }
    } catch (e) {
      LogService.instance.log('[EXPORT] Cleanup error (non-fatal): $e');
    }
  }

  /// Saves ZIP to public Downloads folder using downloadsfolder package.
  /// Uses MediaStore on Android API 29+ for scoped storage compliance.
  /// Returns (success, errorMessage).
  static Future<(bool, String?)> saveZipToDownloads(
    int projectId,
    String projectName,
  ) async {
    if (!Platform.isAndroid) {
      return (false, 'not_android');
    }

    try {
      // Find the most recent ZIP in exports directory
      final zipFile = await _findMostRecentZip(projectId);
      if (zipFile == null || !await zipFile.exists()) {
        LogService.instance.log('[EXPORT] No ZIP file found to save');
        return (false, 'zip_not_found');
      }

      final zipPath = zipFile.path;
      final fileName = path.basename(zipPath);
      LogService.instance.log('[EXPORT] Saving to Downloads: $fileName');

      // Use downloadsfolder package - uses MediaStore on API 29+
      final success = await copyFileIntoDownloadFolder(zipPath, fileName);

      if (success == true) {
        LogService.instance.log('[EXPORT] Saved to Downloads/$fileName');
        // Clean up old private exports
        await _cleanupOldPrivateExports(projectId);
        return (true, null);
      } else {
        LogService.instance.log('[EXPORT] copyFileIntoDownloadFolder failed');
        return (false, 'save_failed');
      }
    } catch (e, st) {
      LogService.instance.log('[EXPORT] saveZipToDownloads error: $e\n$st');
      return (false, e.toString());
    }
  }

  /// Finds the most recent ZIP file in the project's exports directory.
  /// Returns null if no ZIP files exist.
  static Future<File?> _findMostRecentZip(int projectId) async {
    try {
      final exportsDir = Directory(await DirUtils.getExportsDirPath(projectId));
      if (!await exportsDir.exists()) return null;

      final zipFiles = await exportsDir
          .list()
          .where((e) => e is File && e.path.endsWith('.zip'))
          .cast<File>()
          .toList();

      if (zipFiles.isEmpty) return null;

      // Sort by modification time, newest first
      zipFiles.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });

      return zipFiles.first;
    } catch (e) {
      LogService.instance.log('[EXPORT] _findMostRecentZip error: $e');
      return null;
    }
  }

  /// Shares the exported ZIP file using the system share dialog.
  /// Returns true if share was successful, false if dismissed or failed.
  static Future<bool> shareZipFile(int projectId, String projectName) async {
    try {
      // Find the most recent ZIP (don't regenerate path with new timestamp)
      final zipFile = await _findMostRecentZip(projectId);
      if (zipFile == null || !await zipFile.exists()) {
        LogService.instance.log('[EXPORT] No ZIP file found to share');
        return false;
      }

      final zipPath = zipFile.path;
      LogService.instance.log('[EXPORT] Sharing ZIP: $zipPath');

      final params = ShareParams(
        files: [XFile(zipPath, mimeType: 'application/zip')],
      );

      final result = await SharePlus.instance.share(params);

      if (result.status == ShareResultStatus.success) {
        LogService.instance.log('[EXPORT] Share completed successfully');
        return true;
      } else if (result.status == ShareResultStatus.dismissed) {
        LogService.instance.log('[EXPORT] Share dismissed by user');
        return false;
      } else {
        LogService.instance.log('[EXPORT] Share failed: ${result.status}');
        return false;
      }
    } catch (e, st) {
      LogService.instance.log('[EXPORT] shareZipFile error: $e\n$st');
      return false;
    }
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
      Map<String, List<String>> filesToExport = {'Raw': [], 'Stabilized': []};

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
        final dateStampEnabled = await SettingsUtil.loadExportDateStampEnabled(
          projectIdStr,
        );

        if (dateStampEnabled) {
          final stabilizedFiles = filesToExport['Stabilized']!;

          // Load date stamp settings
          final dateFormat = await SettingsUtil.loadExportDateStampFormat(
            projectIdStr,
          );
          final datePosition = await SettingsUtil.loadExportDateStampPosition(
            projectIdStr,
          );
          final dateSize = await SettingsUtil.loadExportDateStampSize(
            projectIdStr,
          );
          final gallerySize = await SettingsUtil.loadGalleryDateStampSize(
            projectIdStr,
          );
          final resolvedSize = DateStampUtils.resolveExportSize(
            dateSize,
            gallerySize,
          );
          final dateOpacity = await SettingsUtil.loadExportDateStampOpacity(
            projectIdStr,
          );
          final exportFont = await SettingsUtil.loadExportDateStampFont(
            projectIdStr,
          );
          final galleryFont = await SettingsUtil.loadGalleryDateStampFont(
            projectIdStr,
          );
          final resolvedFont = DateStampUtils.resolveExportFont(
            exportFont,
            galleryFont,
          );

          // Load watermark settings
          final watermarkEnabled = await SettingsUtil.loadWatermarkSetting(
            projectIdStr,
          );
          final String? watermarkPos = watermarkEnabled
              ? (await DB.instance.getSettingValueByTitle(
                  'watermark_position',
                ))
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
            sizePercent: resolvedSize,
            opacity: dateOpacity,
            captureOffsetMap: captureOffsetMap,
            watermarkPosition: watermarkPos,
            onProgress: (current, total) {
              setExportProgress((current / total) * 30);
            },
            fontFamily: resolvedFont,
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

      if (res != 'success') {
        LogService.instance.log(
          '[EXPORT] Selected export failed: '
          'raw=${filesToExport['Raw']?.length ?? 0}, '
          'stabilized=${filesToExport['Stabilized']?.length ?? 0}',
        );
        return false;
      }

      // Handle platform-specific export finalization
      if (Platform.isAndroid) {
        // Android: Save directly to Downloads via MediaStore
        final (saved, error) = await saveZipToDownloads(projectId, projectName);
        if (saved) {
          LogService.instance.log(
            '[EXPORT] Selected photos saved to Downloads',
          );
          return true;
        } else if (error == 'save_failed') {
          // Downloads save failed, fall back to share sheet
          LogService.instance.log(
            '[EXPORT] Downloads save failed, using share sheet',
          );
          await shareZipFile(projectId, projectName);
          return true;
        } else {
          LogService.instance.log('[EXPORT] Save failed: $error');
          return false;
        }
      } else if (Platform.isIOS) {
        // iOS: Share sheet is the expected UX
        await shareZipFile(projectId, projectName);
        return true;
      }

      // Desktop: Already handled by file_selector in exportZipFile()
      return true;
    } catch (e, st) {
      LogService.instance.log('[EXPORT] exportSelectedPhotos crashed: $e\n$st');
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
