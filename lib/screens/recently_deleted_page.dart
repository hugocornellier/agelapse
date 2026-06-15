import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../services/database_helper.dart';
import '../services/log_service.dart';
import '../services/thumbnail_service.dart';
import '../styles/styles.dart';
import '../utils/dir_utils.dart';
import '../utils/project_utils.dart';
import '../widgets/confirm_action_dialog.dart';

/// iPhone-Photos-style Recently Deleted album, scoped to a single project.
///
/// Lists every photo soft-deleted from this project, shows the days remaining
/// before the launch-time purge claims it, and lets the user restore or
/// permanently delete (single or bulk).
class RecentlyDeletedPage extends StatefulWidget {
  final int projectId;
  final String projectName;

  /// Fired after at least one photo was successfully restored. The gallery
  /// uses this to reload its image list AND recompile the video; restore
  /// changes which frames make it into the video.
  final Future<void> Function()? onRestored;

  /// Fired after permanent-delete actions complete (success, partial, or
  /// failure, at least one row touched). The gallery uses this to refresh
  /// the Recently Deleted *count badge* only; the active photo set didn't
  /// change so no video recompile is necessary.
  final Future<void> Function()? onPurged;

  const RecentlyDeletedPage({
    super.key,
    required this.projectId,
    required this.projectName,
    this.onRestored,
    this.onPurged,
  });

  @override
  State<RecentlyDeletedPage> createState() => _RecentlyDeletedPageState();
}

class _RecentlyDeletedPageState extends State<RecentlyDeletedPage> {
  static const int _retentionDays = DB.recentlyDeletedRetentionDays;

  List<Map<String, dynamic>> _photos = const [];
  final Set<String> _selected = <String>{};
  bool _selectionMode = false;
  bool _loading = true;
  bool _busy = false;

  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    // Run the retention purge on entry too. Launch-time purge handles cold
    // starts, but a long-running session (>30d) would otherwise let expired
    // items linger in the list with a "Today" label until app restart.
    _purgeAndLoad();
  }

  Future<void> _purgeAndLoad() async {
    try {
      await ProjectUtils.purgeExpiredDeletedImages();
    } catch (e) {
      LogService.instance
          .log('RecentlyDeletedPage page-entry purge failed: $e');
    }
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final rows = await DB.instance.getRecentlyDeletedPhotosByProjectID(
        widget.projectId,
      );
      if (!mounted) return;
      setState(() {
        _photos = rows;
        _loading = false;
        _loadFailed = false;
        _selected.removeWhere(
          (ts) => !rows.any((r) => r['timestamp'] == ts),
        );
      });
    } catch (e) {
      LogService.instance.log('RecentlyDeletedPage load failed: $e');
      if (!mounted) return;
      setState(() {
        _photos = const [];
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _toggleSelection(String timestamp) {
    setState(() {
      if (_selected.contains(timestamp)) {
        _selected.remove(timestamp);
        if (_selected.isEmpty) _selectionMode = false;
      } else {
        _selected.add(timestamp);
        _selectionMode = true;
      }
    });
  }

  void _enterSelection(String timestamp) {
    setState(() {
      _selectionMode = true;
      _selected.add(timestamp);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _selectAll() {
    setState(() {
      _selectionMode = true;
      _selected
        ..clear()
        ..addAll(_photos.map((r) => r['timestamp'] as String));
    });
  }

  /// Resolves the timestamps the action should apply to. When in selection
  /// mode, the user's picks; otherwise the single tapped row.
  List<Map<String, dynamic>> _targets({String? singleTimestamp}) {
    if (singleTimestamp != null) {
      return _photos
          .where((r) => r['timestamp'] == singleTimestamp)
          .toList(growable: false);
    }
    return _photos
        .where((r) => _selected.contains(r['timestamp']))
        .toList(growable: false);
  }

  Future<void> _restore({String? singleTimestamp}) async {
    if (_busy) return;
    final targets = _targets(singleTimestamp: singleTimestamp);
    if (targets.isEmpty) return;

    setState(() => _busy = true);
    int restored = 0;
    int missingFile = 0;
    for (final row in targets) {
      final ts = row['timestamp'] as String?;
      if (ts == null) continue;
      try {
        final outcome = await ProjectUtils.restoreImage(ts, widget.projectId);
        if (outcome == RestoreOutcome.success) {
          restored++;
        } else if (outcome == RestoreOutcome.rawFileMissing) {
          missingFile++;
        }
      } catch (e) {
        LogService.instance.log('Restore failed for $ts: $e');
      }
    }

    await _load();
    if (mounted) {
      setState(() {
        _busy = false;
        _selectionMode = false;
        _selected.clear();
      });
    }

    // Only the restore path actually changes which photos make it into the
    // active gallery / video, so it's the only one that needs a full
    // recompile-on-return. Skip notifying for a no-op restore.
    if (restored > 0 && widget.onRestored != null) {
      try {
        await widget.onRestored!();
      } catch (_) {}
    }

    if (!mounted) return;
    final int failed = targets.length - restored - missingFile;
    final String msg = _restoreSnackbarMessage(
      restored: restored,
      missingFile: missingFile,
      failed: failed,
    );
    final bool isError = failed > 0 || missingFile > 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.danger : null,
      ),
    );
  }

  String _restoreSnackbarMessage({
    required int restored,
    required int missingFile,
    required int failed,
  }) {
    if (missingFile == 0 && failed == 0) {
      return restored == 1 ? 'Restored 1 photo' : 'Restored $restored photos';
    }
    final parts = <String>[];
    if (restored > 0) parts.add('$restored restored');
    if (missingFile > 0) {
      parts.add(
        missingFile == 1
            ? '1 file missing on disk'
            : '$missingFile files missing on disk',
      );
    }
    if (failed > 0) parts.add('$failed failed');
    return parts.join(', ');
  }

  Future<void> _permanentlyDelete({String? singleTimestamp}) async {
    if (_busy) return;
    final targets = _targets(singleTimestamp: singleTimestamp);
    if (targets.isEmpty) return;

    final bool isSingle = targets.length == 1;
    final confirmed = await ConfirmActionDialog.showSimpleConfirmation(
      context,
      title: isSingle ? 'Delete Photo Forever?' : 'Delete Photos Forever?',
      description: isSingle
          ? 'This photo will be permanently deleted. This cannot be undone.'
          : '${targets.length} photos will be permanently deleted. '
              'This cannot be undone.',
      titleIcon: Icons.delete_forever_rounded,
      confirmText: 'Delete Forever',
      accentColor: AppColors.danger,
    );
    if (!confirmed || !mounted) return;

    await _runPermanentDeletes(targets);
  }

  /// Body of permanent-delete with no confirm dialog. Used by both
  /// [_permanentlyDelete] (which prompts first) and [_emptyTrash] (which
  /// already prompted at the menu).
  Future<void> _runPermanentDeletes(
    List<Map<String, dynamic>> targets,
  ) async {
    if (targets.isEmpty) return;
    setState(() => _busy = true);
    int removed = 0;
    int filesPartiallyRemain = 0;
    for (final row in targets) {
      final ts = row['timestamp'] as String?;
      final ext = row['fileExtension'] as String?;
      if (ts == null || ext == null) continue;
      try {
        final rawPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
          ts,
          widget.projectId,
          fileExtension: ext,
        );
        final outcome = await ProjectUtils.permanentlyDeleteImage(
          File(rawPath),
          widget.projectId,
        );
        if (outcome == PermDeleteOutcome.success ||
            outcome == PermDeleteOutcome.filesPartiallyRemain) {
          removed++;
          if (outcome == PermDeleteOutcome.filesPartiallyRemain) {
            filesPartiallyRemain++;
          }
          ThumbnailService.instance.clearCache(
            await _thumbnailPath(widget.projectId, ts),
          );
        }
      } catch (e) {
        LogService.instance.log('Delete-forever failed for $ts: $e');
      }
    }

    await _load();
    if (mounted) {
      setState(() {
        _busy = false;
        _selectionMode = false;
        _selected.clear();
      });
    }

    // Permanent delete of an *already* soft-deleted row doesn't change the
    // active photo set, so the video doesn't need recompiling. Just refresh
    // the count so the gallery's "Recently Deleted" badge updates.
    if (widget.onPurged != null) {
      try {
        await widget.onPurged!();
      } catch (_) {}
    }

    if (!mounted) return;
    final int failedCount = targets.length - removed;
    final String msg = _permDeleteSnackbarMessage(
      removed: removed,
      filesPartiallyRemain: filesPartiallyRemain,
      failed: failedCount,
    );
    final bool isError = failedCount > 0 || filesPartiallyRemain > 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.danger : null,
      ),
    );
  }

  String _permDeleteSnackbarMessage({
    required int removed,
    required int filesPartiallyRemain,
    required int failed,
  }) {
    if (failed == 0 && filesPartiallyRemain == 0) {
      return removed == 1
          ? 'Permanently deleted 1 photo'
          : 'Permanently deleted $removed photos';
    }
    final parts = <String>[];
    if (removed - filesPartiallyRemain > 0) {
      parts.add('${removed - filesPartiallyRemain} deleted');
    }
    if (filesPartiallyRemain > 0) {
      parts.add(
        filesPartiallyRemain == 1
            ? '1 row removed but file remained on disk'
            : '$filesPartiallyRemain rows removed but files remained on disk',
      );
    }
    if (failed > 0) parts.add('$failed failed');
    return parts.join(', ');
  }

  static Future<String> _thumbnailPath(int projectId, String timestamp) async {
    final dir = await DirUtils.getThumbnailDirPath(projectId);
    return path.join(dir, '$timestamp.jpg');
  }

  String _daysRemainingLabel(int deletedAtMs) {
    final deletedAt = DateTime.fromMillisecondsSinceEpoch(deletedAtMs);
    final purgeAt = deletedAt.add(const Duration(days: _retentionDays));
    final remaining = purgeAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Today';
    if (remaining.inHours < 24) {
      final hours = remaining.inHours;
      return hours <= 1 ? '< 1h' : '${hours}h';
    }
    // Ceil so a freshly-deleted photo reads "30d" instead of "29d".
    final days = (remaining.inMinutes / (60 * 24)).ceil();
    return '${days}d';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
              ? _buildErrorState()
              : _photos.isEmpty
                  ? _buildEmptyState()
                  : _buildGrid(),
      bottomNavigationBar: _selectionMode ? _buildSelectionBar() : null,
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: AppColors.danger,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load Recently Deleted',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: AppTypography.lg,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_selectionMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _exitSelection,
        ),
        title: Text(
          _selected.length == 1 ? '1 selected' : '${_selected.length} selected',
        ),
        actions: [
          TextButton(
            onPressed: _selected.length == _photos.length ? null : _selectAll,
            child: const Text('Select All'),
          ),
        ],
      );
    }
    return AppBar(
      title: const Text('Recently Deleted'),
      actions: [
        if (_photos.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.checklist_rounded),
            tooltip: 'Select',
            onPressed: () => setState(() => _selectionMode = true),
          ),
        if (_photos.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              switch (value) {
                case 'restore_all':
                  _restoreAll();
                  break;
                case 'empty_trash':
                  _emptyTrash();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'restore_all',
                child: Row(
                  children: [
                    Icon(Icons.restore_rounded, color: AppColors.success),
                    const SizedBox(width: 12),
                    const Text('Restore All'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'empty_trash',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_forever_rounded,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 12),
                    const Text('Empty Trash'),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _restoreAll() async {
    if (_busy || _photos.isEmpty) return;
    final int count = _photos.length;
    final confirmed = await ConfirmActionDialog.showSimpleConfirmation(
      context,
      title: 'Restore All Photos?',
      description: count == 1
          ? 'This photo will be restored to the gallery.'
          : 'All $count photos will be restored to the gallery.',
      titleIcon: Icons.restore_rounded,
      confirmText: 'Restore All',
      accentColor: AppColors.success,
    );
    if (!confirmed || !mounted) return;
    // Pre-select everything and reuse the regular bulk-restore path so the
    // SnackBar / busy / reload logic stays consistent.
    setState(() {
      _selectionMode = true;
      _selected
        ..clear()
        ..addAll(_photos.map((r) => r['timestamp'] as String));
    });
    await _restore();
  }

  Future<void> _emptyTrash() async {
    if (_busy || _photos.isEmpty) return;
    final int count = _photos.length;
    final confirmed = await ConfirmActionDialog.showSimpleConfirmation(
      context,
      title: 'Empty Recently Deleted?',
      description: count == 1
          ? 'This photo will be permanently deleted. This cannot be undone.'
          : 'All $count photos will be permanently deleted. '
              'This cannot be undone.',
      titleIcon: Icons.delete_forever_rounded,
      confirmText: 'Empty Trash',
      accentColor: AppColors.danger,
    );
    if (!confirmed || !mounted) return;
    final targets = List<Map<String, dynamic>>.from(_photos);
    setState(() {
      _selectionMode = true;
      _selected
        ..clear()
        ..addAll(_photos.map((r) => r['timestamp'] as String));
    });
    await _runPermanentDeletes(targets);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline_rounded,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No recently deleted photos',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: AppTypography.lg,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Photos you delete from ${widget.projectName} will appear here '
              'for $_retentionDays days before being permanently removed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppTypography.sm,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width >= 1200
        ? 6
        : width >= 800
            ? 5
            : width >= 500
                ? 4
                : 3;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: AppColors.surface,
          child: Text(
            'Photos are kept for $_retentionDays days. After that they are '
            'permanently removed.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppTypography.sm,
              height: 1.4,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: _photos.length,
            itemBuilder: (context, index) {
              return _RecentlyDeletedTile(
                projectId: widget.projectId,
                row: _photos[index],
                selected:
                    _selected.contains(_photos[index]['timestamp'] as String),
                selectionMode: _selectionMode,
                daysLabel: _daysRemainingLabel(
                  (_photos[index]['deletedAt'] as int?) ?? 0,
                ),
                onTap: () {
                  final ts = _photos[index]['timestamp'] as String;
                  if (_selectionMode) {
                    _toggleSelection(ts);
                  } else {
                    _showSingleActionsSheet(ts);
                  }
                },
                onLongPress: () =>
                    _enterSelection(_photos[index]['timestamp'] as String),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showSingleActionsSheet(String timestamp) async {
    if (_busy) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.restore_rounded, color: AppColors.success),
                title: const Text('Restore'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _restore(singleTimestamp: timestamp);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_forever_rounded,
                  color: AppColors.danger,
                ),
                title: const Text('Delete Forever'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _permanentlyDelete(singleTimestamp: timestamp);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSelectionBar() {
    final hasSelection = _selected.isNotEmpty;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(
              color: AppColors.textSecondary.withValues(alpha: 0.15),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: hasSelection && !_busy ? () => _restore() : null,
              icon: Icon(Icons.restore_rounded, color: AppColors.success),
              label: Text(
                'Restore',
                style: TextStyle(color: AppColors.success),
              ),
            ),
            TextButton.icon(
              onPressed:
                  hasSelection && !_busy ? () => _permanentlyDelete() : null,
              icon: Icon(Icons.delete_forever_rounded, color: AppColors.danger),
              label: Text(
                'Delete Forever',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentlyDeletedTile extends StatelessWidget {
  final int projectId;
  final Map<String, dynamic> row;
  final bool selected;
  final bool selectionMode;
  final String daysLabel;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _RecentlyDeletedTile({
    required this.projectId,
    required this.row,
    required this.selected,
    required this.selectionMode,
    required this.daysLabel,
    required this.onTap,
    required this.onLongPress,
  });

  static Future<({String thumbPath, String? rawPath})> _resolvePaths(
    int projectId,
    String timestamp,
    String? fileExtension,
  ) async {
    final thumbPath = await _RecentlyDeletedPageState._thumbnailPath(
      projectId,
      timestamp,
    );
    String? rawPath;
    if (fileExtension != null && fileExtension.isNotEmpty) {
      try {
        rawPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
          timestamp,
          projectId,
          fileExtension: fileExtension,
        );
      } catch (_) {
        rawPath = null;
      }
    }
    return (thumbPath: thumbPath, rawPath: rawPath);
  }

  @override
  Widget build(BuildContext context) {
    final timestamp = row['timestamp'] as String;
    final fileExtension = row['fileExtension'] as String?;
    final originalFilename = (row['originalFilename'] as String?) ??
        (row['sourceFilename'] as String?);
    final dateLabel = _humanDate(timestamp);
    final semanticsLabel =
        '${originalFilename ?? dateLabel}, $daysLabel until permanent deletion';

    return Semantics(
      button: true,
      selected: selectionMode ? selected : null,
      label: semanticsLabel,
      hint: selectionMode
          ? 'Double-tap to ${selected ? 'deselect' : 'select'}'
          : 'Double-tap for restore or delete forever options. '
              'Long-press to enter selection mode.',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: AppColors.surface,
              child: FutureBuilder<({String thumbPath, String? rawPath})>(
                future: _resolvePaths(projectId, timestamp, fileExtension),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final paths = snapshot.data!;
                  return _ThumbnailWithFallback(
                    thumbPath: paths.thumbPath,
                    rawPath: paths.rawPath,
                    captionFallback: originalFilename ?? dateLabel,
                  );
                },
              ),
            ),
            // Dim slightly so the user perceives these as "trash".
            Container(color: Colors.black.withValues(alpha: 0.25)),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  daysLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (selectionMode)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.danger : Colors.transparent,
                    border: Border.all(color: Colors.white, width: 2),
                    shape: BoxShape.circle,
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _humanDate(String timestamp) {
    final ms = int.tryParse(timestamp);
    if (ms == null) return timestamp;
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }
}

/// Thumbnail loader with three-tier fallback so a missing or corrupted
/// thumbnail file doesn't render an opaque blank tile (which would make
/// recovery impossible; the user can't tell which photo it was).
///
/// Tier 1: thumbnail file (fast, small)
/// Tier 2: raw file (slow but always available if the row is restorable)
/// Tier 3: text caption with the photo's original filename or capture date
class _ThumbnailWithFallback extends StatelessWidget {
  final String thumbPath;
  final String? rawPath;
  final String captionFallback;

  const _ThumbnailWithFallback({
    required this.thumbPath,
    required this.rawPath,
    required this.captionFallback,
  });

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(thumbPath),
      fit: BoxFit.cover,
      cacheWidth: 256,
      errorBuilder: (_, __, ___) {
        if (rawPath == null) return _captionTile(context);
        return Image.file(
          File(rawPath!),
          fit: BoxFit.cover,
          cacheWidth: 256,
          errorBuilder: (_, __, ___) => _captionTile(context),
        );
      },
    );
  }

  Widget _captionTile(BuildContext context) {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            color: AppColors.textSecondary,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            captionFallback,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
