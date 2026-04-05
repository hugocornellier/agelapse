import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/import_preview_item.dart';
import '../styles/styles.dart';
import '../utils/capture_timezone.dart';
import '../utils/gallery_utils.dart';
import '../utils/platform_utils.dart';
import 'dialog_button_row.dart';
import 'dialog_title_row.dart';

/// Shows a two-phase import preview dialog.
///
/// Phase 1: Runs date extraction on all [filePaths] and shows a progress bar.
/// Phase 2: Displays a sortable review table of filenames, dates, and sources.
///
/// Returns `List<ImportPreviewItem>` on Import, or `null` on Cancel.
Future<List<ImportPreviewItem>?> showImportPreviewDialog(
  BuildContext context,
  List<String> filePaths,
) {
  return showDialog<List<ImportPreviewItem>>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ImportPreviewDialog(filePaths: filePaths),
  );
}

class ImportPreviewDialog extends StatefulWidget {
  final List<String> filePaths;

  const ImportPreviewDialog({super.key, required this.filePaths});

  @override
  State<ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<ImportPreviewDialog> {
  bool _isProcessing = true;
  int _processedCount = 0;
  final List<ImportPreviewItem> _items = [];
  bool _isCancelled = false;
  String _sortColumn = 'date';
  bool _sortAscending = true;
  bool _infoExpanded = true;
  bool _useFilenameOrder = false;
  List<ImportPreviewItem> _originalItems = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _processFiles();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _processFiles() async {
    for (final filePath in widget.filePaths) {
      if (_isCancelled) break;

      final item = await GalleryUtils.extractDateForPreview(filePath);

      if (_isCancelled) break;

      if (mounted) {
        setState(() {
          _items.add(item);
          _processedCount++;
        });
      }
    }

    if (!_isCancelled && mounted) {
      setState(() {
        _items.sort((a, b) => a.displayDate.compareTo(b.displayDate));
        _originalItems = List.of(_items);
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isProcessing ? _buildProcessingPhase() : _buildReviewPhase(context);
  }

  Widget _buildDateInfoCard() {
    return GestureDetector(
      onTap: () => setState(() => _infoExpanded = !_infoExpanded),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: AppColors.info.withValues(alpha: 0.9),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'How are dates extracted?',
                      style: TextStyle(
                        color: AppColors.textPrimary.withValues(alpha: 0.9),
                        fontSize: AppTypography.sm,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _infoExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.textPrimary.withValues(alpha: 0.5),
                      size: 20,
                    ),
                  ),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoBullet(
                        'First choice: EXIF metadata (camera date/time)',
                      ),
                      const SizedBox(height: 6),
                      _buildInfoBullet(
                        'Second choice: Filename (e.g. 2023-01-15_photo.jpg)',
                      ),
                      const SizedBox(height: 6),
                      _buildInfoBullet(
                        'Third choice: File modification date (last resort)',
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () async {
                          final uri = Uri.parse(
                            'https://agelapse.com/docs/user-guide/photo-dates',
                          );
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Read full guide',
                              style: TextStyle(
                                color: AppColors.info.withValues(alpha: 0.9),
                                fontSize: AppTypography.sm,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.open_in_new,
                              color: AppColors.info.withValues(alpha: 0.9),
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                crossFadeState: _infoExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildInfoBullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.textPrimary.withValues(alpha: 0.75),
              fontSize: AppTypography.sm,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColumnHeader(String label, String column, {required int flex}) {
    final bool isActive = _sortColumn == column;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _onSort(column),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppTypography.sm,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                if (isActive)
                  Icon(
                    _sortAscending
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 14,
                    color: AppColors.textSecondary,
                  )
                else
                  Icon(
                    Icons.unfold_more_rounded,
                    size: 14,
                    color: AppColors.textTertiary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onToggleFilenameOrder(bool value) {
    setState(() {
      _useFilenameOrder = value;
      if (value) {
        _items.sort(
          (a, b) => GalleryUtils.compareNatural(a.filePath, b.filePath),
        );
        _sortColumn = 'file';
        _sortAscending = true;
      } else {
        _items.clear();
        _items.addAll(List.of(_originalItems));
        _sortColumn = 'date';
        _sortAscending = true;
      }
    });
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
      _items.sort((a, b) {
        final int cmp;
        switch (_sortColumn) {
          case 'file':
            cmp = a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
          case 'date':
            cmp = a.displayDate.compareTo(b.displayDate);
          case 'source':
            cmp = a.sourceTier.index.compareTo(b.sourceTier.index);
          default:
            cmp = 0;
        }
        return _sortAscending ? cmp : -cmp;
      });
    });
  }

  Widget _buildProcessingPhase() {
    final total = widget.filePaths.length;
    final progress = total > 0 ? _processedCount / total : 0.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.textPrimary.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DialogTitleRow(
              icon: Icons.hourglass_top_rounded,
              title: 'Processing...',
              iconColor: AppColors.accent,
              iconBackgroundColor: AppColors.accent.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppColors.textPrimary.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                '$_processedCount / $total',
                style: TextStyle(
                  fontSize: AppTypography.md,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  _isCancelled = true;
                  Navigator.of(context).pop(null);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: AppColors.textPrimary.withValues(alpha: 0.7),
                        fontSize: AppTypography.lg,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewPhase(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxWidth = isMobile ? screenWidth * 0.96 : 780.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: screenHeight * 0.82,
        ),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.textPrimary.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DialogTitleRow(
                  icon: Icons.photo_library_outlined,
                  title: 'Review Import',
                  iconColor: AppColors.accent,
                  iconBackgroundColor: AppColors.accent.withValues(alpha: 0.15),
                ),
                const Spacer(),
                Text(
                  'Order by Filename (Force)',
                  style: TextStyle(
                    fontSize: AppTypography.sm,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 24,
                  child: FittedBox(
                    child: CupertinoSwitch(
                      value: _useFilenameOrder,
                      onChanged: _onToggleFilenameOrder,
                      activeTrackColor: AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${_items.length} files',
                  style: TextStyle(
                    fontSize: AppTypography.sm,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDateInfoCard(),
            const SizedBox(height: 12),
            // Table header
            Row(
              children: [
                _buildColumnHeader('File', 'file', flex: 4),
                _buildColumnHeader('Date', 'date', flex: 3),
                _buildColumnHeader('Source', 'source', flex: 2),
              ],
            ),
            Divider(
              height: 1,
              color: AppColors.textPrimary.withValues(alpha: 0.1),
            ),
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _scrollController,
                  shrinkWrap: false,
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final isLast = index == _items.length - 1;
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 8,
                                ),
                                child: Text(
                                  item.filename,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: AppTypography.sm,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 8,
                                ),
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: DateFormat(
                                          'yyyy-MM-dd HH:mm',
                                        ).format(item.displayDate),
                                      ),
                                      TextSpan(
                                        text:
                                            '\n${CaptureTimezone.formatOffsetLabel(item.captureOffsetMinutes)}',
                                        style: TextStyle(
                                          fontSize: AppTypography.xs,
                                          color: AppColors.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  style: TextStyle(
                                    fontSize: AppTypography.sm,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 8,
                                ),
                                child: Text(
                                  item.sourceLabel,
                                  style: TextStyle(
                                    fontSize: AppTypography.sm,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!isLast)
                          Divider(
                            height: 1,
                            color: AppColors.textPrimary.withValues(
                              alpha: 0.06,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: DialogButtonRow(
                  cancelLabel: 'Cancel',
                  actionLabel: 'Import',
                  actionColor: AppColors.accent,
                  onCancel: () => Navigator.of(context).pop(null),
                  onAction: () => Navigator.of(context).pop(_items),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
