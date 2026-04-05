import 'dart:io';

import 'package:path/path.dart' as path;

import '../services/database_helper.dart';
import '../services/log_service.dart';
import 'platform_utils.dart';

class LinkedSourceConfig {
  final bool enabled;
  final String mode;
  final String displayPath;
  final String rootPath;
  final String treeUri;
  final String bookmark;
  final bool managedByApp;
  final int lastScanStartedAt;
  final int lastScanCompletedAt;

  const LinkedSourceConfig({
    required this.enabled,
    required this.mode,
    required this.displayPath,
    required this.rootPath,
    required this.treeUri,
    required this.bookmark,
    required this.managedByApp,
    required this.lastScanStartedAt,
    required this.lastScanCompletedAt,
  });

  bool get hasUsableDesktopRoot =>
      enabled &&
      mode == 'desktop_path' &&
      rootPath.trim().isNotEmpty &&
      isDesktop;

  static const empty = LinkedSourceConfig(
    enabled: false,
    mode: 'none',
    displayPath: '',
    rootPath: '',
    treeUri: '',
    bookmark: '',
    managedByApp: false,
    lastScanStartedAt: 0,
    lastScanCompletedAt: 0,
  );
}

class LinkedSourcePlacement {
  final String absolutePath;
  final String relativePath;
  final String filename;

  const LinkedSourcePlacement({
    required this.absolutePath,
    required this.relativePath,
    required this.filename,
  });
}

class LinkedSourceUtils {
  static bool get supportsDesktopLinkedFolders => isDesktop;

  static Future<LinkedSourceConfig> loadConfig(int projectId) async {
    try {
      final projectIdStr = projectId.toString();
      final values = await Future.wait([
        DB.instance.getSettingValueByTitle(
          'linked_source_enabled',
          projectIdStr,
        ),
        DB.instance.getSettingValueByTitle('linked_source_mode', projectIdStr),
        DB.instance.getSettingValueByTitle(
          'linked_source_display_path',
          projectIdStr,
        ),
        DB.instance.getSettingValueByTitle(
          'linked_source_root_path',
          projectIdStr,
        ),
        DB.instance.getSettingValueByTitle(
          'linked_source_tree_uri',
          projectIdStr,
        ),
        DB.instance.getSettingValueByTitle(
          'linked_source_bookmark',
          projectIdStr,
        ),
        DB.instance.getSettingValueByTitle(
          'linked_source_managed_by_app',
          projectIdStr,
        ),
        DB.instance.getSettingValueByTitle(
          'linked_source_last_scan_started_at',
          projectIdStr,
        ),
        DB.instance.getSettingValueByTitle(
          'linked_source_last_scan_completed_at',
          projectIdStr,
        ),
      ]);

      return LinkedSourceConfig(
        enabled: values[0].toLowerCase() == 'true',
        mode: values[1],
        displayPath: values[2],
        rootPath: values[3],
        treeUri: values[4],
        bookmark: values[5],
        managedByApp: values[6].toLowerCase() == 'true',
        lastScanStartedAt: int.tryParse(values[7]) ?? 0,
        lastScanCompletedAt: int.tryParse(values[8]) ?? 0,
      );
    } catch (e) {
      LogService.instance.log(
        'Failed to load linked source config for project $projectId: $e',
      );
      return LinkedSourceConfig.empty;
    }
  }

  static Future<void> _saveBulkSettings(
    String projectIdStr,
    Map<String, String> settings,
  ) async {
    for (final entry in settings.entries) {
      await DB.instance.setSettingByTitle(entry.key, entry.value, projectIdStr);
    }
  }

  static Future<void> persistDesktopFolderSelection(
    int projectId,
    String folderPath, {
    bool enabled = true,
    bool managedByApp = false,
  }) =>
      _saveBulkSettings(projectId.toString(), {
        'linked_source_enabled': enabled.toString(),
        'linked_source_mode': 'desktop_path',
        'linked_source_display_path': folderPath,
        'linked_source_root_path': folderPath,
        'linked_source_tree_uri': '',
        'linked_source_bookmark': '',
        'linked_source_managed_by_app': managedByApp.toString(),
      });

  static Future<void> disableLinkedSource(int projectId) =>
      _saveBulkSettings(projectId.toString(), {
        'linked_source_enabled': 'false',
        'linked_source_mode': 'none',
        'linked_source_display_path': '',
        'linked_source_root_path': '',
        'linked_source_tree_uri': '',
        'linked_source_bookmark': '',
        'linked_source_managed_by_app': 'false',
      });

  static String? validateLinkedFolderPath({
    required int projectId,
    required String selectedPath,
    required String projectDirPath,
  }) {
    if (!supportsDesktopLinkedFolders) {
      return 'Linked source folders are only supported on desktop right now.';
    }

    final normalizedSelected = _normalizeAbsolutePath(selectedPath);
    final normalizedProject = _normalizeAbsolutePath(projectDirPath);

    if (normalizedSelected == null || normalizedProject == null) {
      return 'Invalid folder path.';
    }

    if (normalizedSelected == normalizedProject ||
        path.isWithin(normalizedSelected, normalizedProject) ||
        path.isWithin(normalizedProject, normalizedSelected)) {
      return 'Cannot link a folder inside the project storage or link the project storage itself.';
    }

    return null;
  }

  static Future<LinkedSourcePlacement?> placeSourceFile({
    required int projectId,
    required String sourceFilePath,
    String? preferredFilename,
  }) async {
    final config = await loadConfig(projectId);
    if (!config.hasUsableDesktopRoot) return null;

    final sourceFile = File(sourceFilePath);
    if (!await sourceFile.exists()) return null;

    final normalizedRoot = _normalizeAbsolutePath(config.rootPath);
    final normalizedSource = _normalizeAbsolutePath(sourceFilePath);
    if (normalizedRoot == null || normalizedSource == null) return null;

    if (normalizedSource == normalizedRoot ||
        path.isWithin(normalizedRoot, normalizedSource)) {
      final relativePath = path.relative(
        normalizedSource,
        from: normalizedRoot,
      );
      final filename = path.basename(normalizedSource);
      return LinkedSourcePlacement(
        absolutePath: normalizedSource,
        relativePath: relativePath,
        filename: filename,
      );
    }

    try {
      final rootDir = Directory(config.rootPath);
      if (!await rootDir.exists()) {
        await rootDir.create(recursive: true);
      }
    } catch (e) {
      LogService.instance.log(
        'Failed to create linked source directory ${config.rootPath}: $e',
      );
      return null;
    }

    final desiredFilename = _sanitizeFilename(
      preferredFilename?.trim().isNotEmpty == true
          ? preferredFilename!.trim()
          : path.basename(sourceFilePath),
    );

    final targetPath = await _uniqueSequentialPath(
      config.rootPath,
      desiredFilename,
    );
    try {
      await sourceFile.copy(targetPath);
    } catch (e) {
      LogService.instance.log(
        'Failed to copy source file to linked folder $targetPath: $e',
      );
      return null;
    }

    return LinkedSourcePlacement(
      absolutePath: targetPath,
      relativePath: path.relative(targetPath, from: config.rootPath),
      filename: path.basename(targetPath),
    );
  }

  static String buildSequentialFilename(String filename, int suffix) {
    final base = path.basenameWithoutExtension(filename);
    final ext = path.extension(filename);
    return '$base ($suffix)$ext';
  }

  static String? _normalizeAbsolutePath(String input) {
    if (input.trim().isEmpty) return null;
    return path.normalize(path.absolute(input));
  }

  static String _sanitizeFilename(String filename) {
    final base = path.basename(filename);
    if (base.isEmpty) return 'photo.jpg';
    final sanitized = base.replaceAll(RegExp(r'[<>:"/\\|?*\x00]'), '_');
    return sanitized.isEmpty ? 'photo.jpg' : sanitized;
  }

  static Future<String> _uniqueSequentialPath(
    String dir,
    String filename,
  ) async {
    var candidate = path.join(dir, filename);
    if (!await File(candidate).exists()) return candidate;

    int suffix = 2;
    while (await File(candidate).exists()) {
      candidate = path.join(dir, buildSequentialFilename(filename, suffix));
      suffix++;
    }
    return candidate;
  }
}
