import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../utils/dir_utils.dart';
import '../utils/gallery_utils.dart';
import '../utils/linked_source_utils.dart';
import 'database_helper.dart';
import 'log_service.dart';
import 'settings_cache.dart';

enum SyncState { idle, scanning, importing, complete, error }

class SyncResult {
  final int filesScanned;
  final int filesImported;
  final int filesSkipped;
  final List<String> errors;

  const SyncResult({
    required this.filesScanned,
    required this.filesImported,
    required this.filesSkipped,
    required this.errors,
  });
}

class ProjectFolderSyncService {
  ProjectFolderSyncService._();

  static final instance = ProjectFolderSyncService._();

  final StreamController<SyncState> _stateController =
      StreamController<SyncState>.broadcast();
  Stream<SyncState> get stateStream => _stateController.stream;

  StreamSubscription<FileSystemEvent>? _watchSubscription;
  Timer? _debounceTimer;
  Timer? _fallbackPollingTimer;
  Future<SyncResult>? _activeSync;
  bool _rescanRequested = false;
  int? _watchedProjectId;
  String? _watchedFolderPath;
  int _watcherRestartCount = 0;
  static const int _maxWatcherRestarts = 5;
  final Set<String> _pendingUnstableFiles = {};

  Future<SyncResult> runStartupSync(int projectId, SettingsCache cache) async {
    final config = LinkedSourceConfig(
      enabled: cache.linkedSourceEnabled,
      mode: cache.linkedSourceMode,
      displayPath: cache.linkedSourceDisplayPath,
      rootPath: cache.linkedSourceRootPath,
      treeUri: cache.linkedSourceTreeUri,
      bookmark: cache.linkedSourceBookmark,
      managedByApp: cache.linkedSourceManagedByApp,
      lastScanStartedAt: cache.linkedSourceLastScanStartedAt,
      lastScanCompletedAt: cache.linkedSourceLastScanCompletedAt,
    );

    if (!config.hasUsableDesktopRoot) {
      await stopWatching();
      return const SyncResult(
        filesScanned: 0,
        filesImported: 0,
        filesSkipped: 0,
        errors: [],
      );
    }

    final result = await _runSync(projectId, config);
    await startWatching(projectId, config.rootPath);
    return result;
  }

  Future<void> startWatching(int projectId, String folderPath) async {
    if (!LinkedSourceUtils.supportsDesktopLinkedFolders) return;

    if (_watchedProjectId == projectId && _watchedFolderPath == folderPath) {
      return;
    }

    await stopWatching();

    _watchedProjectId = projectId;
    _watchedFolderPath = folderPath;
    _watcherRestartCount = 0;

    // Start a fallback polling timer on all desktop platforms.
    // macOS/Windows: every 60s as a safety net; Linux: every 30s (primary mechanism).
    final pollInterval = Platform.isLinux
        ? const Duration(seconds: 30)
        : const Duration(seconds: 60);
    _fallbackPollingTimer = Timer.periodic(
      pollInterval,
      (_) => scheduleDebouncedRescan(),
    );

    if (!Platform.isLinux) {
      _startWatcherStream(projectId, folderPath);
    }
  }

  void _startWatcherStream(int projectId, String folderPath) {
    try {
      _watchSubscription = Directory(folderPath).watch(recursive: true).listen(
        (event) {
          if (event.type == FileSystemEvent.create ||
              event.type == FileSystemEvent.move ||
              event.type == FileSystemEvent.modify) {
            scheduleDebouncedRescan();
          }
        },
        onError: (Object e) {
          LogService.instance.log('[LinkedSync] Watcher error: $e');
          _emitState(SyncState.error);
          _scheduleWatcherRestart(projectId, folderPath);
        },
        onDone: () {
          LogService.instance.log('[LinkedSync] Watcher stream closed');
          _scheduleWatcherRestart(projectId, folderPath);
        },
        cancelOnError: false,
      );
    } catch (e) {
      LogService.instance.log('[LinkedSync] Failed to start watcher: $e');
      _emitState(SyncState.error);
      _scheduleWatcherRestart(projectId, folderPath);
    }
  }

  void _scheduleWatcherRestart(int projectId, String folderPath) {
    if (_watcherRestartCount >= _maxWatcherRestarts) {
      LogService.instance.log(
        '[LinkedSync] Watcher restart limit reached ($_maxWatcherRestarts), relying on polling',
      );
      return;
    }
    _watcherRestartCount++;
    LogService.instance.log(
      '[LinkedSync] Scheduling watcher restart #$_watcherRestartCount',
    );
    Future.delayed(const Duration(seconds: 5), () {
      if (_watchedProjectId == projectId && _watchedFolderPath == folderPath) {
        _watchSubscription?.cancel();
        _watchSubscription = null;
        _startWatcherStream(projectId, folderPath);
      }
    });
  }

  void scheduleDebouncedRescan() {
    final projectId = _watchedProjectId;
    if (projectId == null) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () async {
      final config = await LinkedSourceUtils.loadConfig(projectId);
      if (!config.hasUsableDesktopRoot) return;

      if (_activeSync != null) {
        _rescanRequested = true;
        return;
      }

      await _runSync(projectId, config);
    });
  }

  Future<void> stopWatching() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _fallbackPollingTimer?.cancel();
    _fallbackPollingTimer = null;
    await _watchSubscription?.cancel();
    _watchSubscription = null;
    _watchedProjectId = null;
    _watchedFolderPath = null;
    _watcherRestartCount = 0;
    _pendingUnstableFiles.clear();
    _emitState(SyncState.idle);
  }

  void dispose() {
    stopWatching();
    _stateController.close();
  }

  Future<bool> isFileStable(File file) async {
    if (!await file.exists()) return false;
    final size1 = await file.length();
    if (size1 < GalleryUtils.minImageSizeBytes) return false;
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!await file.exists()) return false;
    final size2 = await file.length();
    return size1 == size2;
  }

  Future<SyncResult> _runSync(
    int projectId,
    LinkedSourceConfig config,
  ) async {
    if (_activeSync != null) return _activeSync!;

    final completer = Completer<SyncResult>();
    _activeSync = completer.future;

    try {
      await _cleanupOrphanedLinkedRecords(projectId);

      final startedAt = DateTime.now().millisecondsSinceEpoch;
      await DB.instance.setSettingByTitle(
        'linked_source_last_scan_started_at',
        startedAt.toString(),
        projectId.toString(),
      );

      final scanResult = await GalleryUtils.collectFilesFromDirectory(
        config.rootPath,
      );
      final errors = <String>[...scanResult.errors];
      final candidates =
          <({String filePath, String relativePath, String filename})>[];
      int skipped = 0;

      for (final filePath in scanResult.validImagePaths) {
        final relativePath = _relativeToRoot(config.rootPath, filePath);
        if (relativePath == null) {
          skipped++;
          continue;
        }

        final existing = await DB.instance.getPhotoBySourceRelativePath(
          relativePath,
          projectId,
        );
        if (existing != null) {
          skipped++;
          continue;
        }

        if (await DB.instance.isLinkedSourceDeleted(projectId, relativePath)) {
          skipped++;
          continue;
        }

        if (!await isFileStable(File(filePath))) {
          _pendingUnstableFiles.add(filePath);
          skipped++;
          continue;
        }
        _pendingUnstableFiles.remove(filePath);

        candidates.add((
          filePath: filePath,
          relativePath: relativePath,
          filename: path.basename(filePath),
        ));
      }

      int imported = 0;
      if (candidates.isNotEmpty) {
        _emitState(SyncState.scanning);
      }

      for (final candidate in candidates) {
        _emitState(SyncState.importing);
        final importedOk = await GalleryUtils.importXFile(
          XFile(candidate.filePath),
          projectId,
          ValueNotifier<String>(''),
          originalFilePath: candidate.filePath,
          sourceFilename: candidate.filename,
          sourceRelativePath: candidate.relativePath,
          sourceLocationType: 'external_linked',
        );
        if (importedOk) {
          imported++;
        } else {
          // Import failed — likely a duplicate. Try to backfill source metadata
          // on the existing photo so sync recognizes it on future runs.
          final fileSize = await File(candidate.filePath).length();
          final backfilled = await _tryBackfillSourceInfo(
            projectId,
            fileSize,
            candidate.filename,
            candidate.relativePath,
          );
          if (backfilled) {
            skipped++;
          } else {
            errors.add('Failed to import ${candidate.relativePath}');
          }
        }
      }

      final completedAt = DateTime.now().millisecondsSinceEpoch;
      await DB.instance.setSettingByTitle(
        'linked_source_last_scan_completed_at',
        completedAt.toString(),
        projectId.toString(),
      );

      if (imported > 0) {
        _emitState(SyncState.complete);
      }

      final result = SyncResult(
        filesScanned: scanResult.validImagePaths.length,
        filesImported: imported,
        filesSkipped: skipped,
        errors: errors,
      );
      completer.complete(result);
      return result;
    } catch (e) {
      _emitState(SyncState.error);
      final result = SyncResult(
        filesScanned: 0,
        filesImported: 0,
        filesSkipped: 0,
        errors: ['$e'],
      );
      completer.complete(result);
      return result;
    } finally {
      _activeSync = null;
      if (_rescanRequested || _pendingUnstableFiles.isNotEmpty) {
        _rescanRequested = false;
        scheduleDebouncedRescan();
      } else {
        _emitState(SyncState.idle);
      }
    }
  }

  Future<void> _cleanupOrphanedLinkedRecords(int projectId) async {
    final linkedPhotos = await DB.instance.getPhotosBySourceLocationType(
      projectId,
      'external_linked',
    );

    for (final photo in linkedPhotos) {
      final timestamp = photo['timestamp'] as String?;
      final fileExtension = photo['fileExtension'] as String?;
      if (timestamp == null || fileExtension == null) continue;

      final rawPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        timestamp,
        projectId,
        fileExtension: fileExtension,
      );
      if (!await File(rawPath).exists()) {
        final parsedTimestamp = int.tryParse(timestamp);
        if (parsedTimestamp != null) {
          await DB.instance.deletePhoto(parsedTimestamp, projectId);
        }
      }
    }
  }

  /// Try to find an existing photo (imported before sync was enabled) that
  /// matches this file by size, and backfill its source metadata so future
  /// syncs skip it instead of reporting a failure.
  Future<bool> _tryBackfillSourceInfo(
    int projectId,
    int fileSize,
    String filename,
    String relativePath,
  ) async {
    try {
      final matches = await DB.instance.getPhotosByImageLength(
        projectId,
        fileSize,
        whereSourceRelativePathIsNull: true,
      );
      if (matches.length != 1) return false;

      final timestamp = matches.first['timestamp'] as String?;
      if (timestamp == null) return false;

      await DB.instance.updatePhotoSourceInfo(
        timestamp,
        projectId,
        sourceFilename: filename,
        sourceRelativePath: relativePath,
        sourceLocationType: 'external_linked',
      );
      return true;
    } catch (e) {
      LogService.instance.log(
        'Failed to backfill source info for $relativePath: $e',
      );
      return false;
    }
  }

  String? _relativeToRoot(String rootPath, String absolutePath) {
    final normalizedRoot = path.normalize(path.absolute(rootPath));
    final normalizedFile = path.normalize(path.absolute(absolutePath));
    if (normalizedRoot == normalizedFile) return null;
    if (!path.isWithin(normalizedRoot, normalizedFile)) return null;
    return path
        .relative(normalizedFile, from: normalizedRoot)
        .replaceAll('\\', '/');
  }

  void _emitState(SyncState state) {
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }
}
