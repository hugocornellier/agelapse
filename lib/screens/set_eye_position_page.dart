import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/database_helper.dart';
import '../../services/thumbnail_service.dart';
import '../styles/styles.dart';
import '../utils/utils.dart';
import '../widgets/grid_painter_se.dart';
import '../utils/output_image_loader.dart';

class SetEyePositionPage extends StatefulWidget {
  final int projectId;
  final String projectName;
  final Future<void> Function() cancelStabCallback;
  final VoidCallback refreshSettings;
  final VoidCallback clearRawAndStabPhotos;
  final VoidCallback stabCallback;

  const SetEyePositionPage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.cancelStabCallback,
    required this.refreshSettings,
    required this.clearRawAndStabPhotos,
    required this.stabCallback,
  });

  @override
  SetEyePositionPageState createState() => SetEyePositionPageState();
}

class SetEyePositionPageState extends State<SetEyePositionPage> {
  late double _defaultOffsetX;
  late double _defaultOffsetY;
  late double _offsetX;
  late double _offsetY;
  String? offSetXColName;
  String? offSetYColName;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;
  bool _showCheckmark = false;
  bool _isDraggingVertical = false;
  bool _draggingRight = false;
  bool _isDraggingHorizontal = false;
  final GlobalKey _widgetKey = GlobalKey();
  late OutputImageLoader outputImageLoader;
  bool _isInfoWidgetVisible = true;
  Timer? _checkmarkTimer;

  @override
  void initState() {
    super.initState();
    outputImageLoader = OutputImageLoader(widget.projectId);
    _init();
  }

  @override
  void dispose() {
    _checkmarkTimer?.cancel();
    outputImageLoader.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await outputImageLoader.initialize();
    if (!mounted) return;

    setState(() {
      _defaultOffsetX = outputImageLoader.offsetX;
      _defaultOffsetY = outputImageLoader.offsetY;
      _offsetX = _defaultOffsetX;
      _offsetY = _defaultOffsetY;
    });
  }

  Future<void> _saveChanges() async {
    setState(() {
      _isSaving = true;
    });

    // 1. Await cancellation FIRST (prevents race condition)
    await widget.cancelStabCallback();

    final projectOrientation = outputImageLoader.projectOrientation!;
    offSetXColName = projectOrientation == 'landscape'
        ? "eyeOffsetXLandscape"
        : "eyeOffsetXPortrait";
    offSetYColName = projectOrientation == 'landscape'
        ? "eyeOffsetYLandscape"
        : "eyeOffsetYPortrait";

    // 2. Save new settings
    await DB.instance.setSettingByTitle(
      offSetXColName!,
      _offsetX.toString(),
      widget.projectId.toString(),
    );
    await DB.instance.setSettingByTitle(
      offSetYColName!,
      _offsetY.toString(),
      widget.projectId.toString(),
    );

    // 3. Reset DB + delete files (resetStabilizationStatusForProject handles deletion)
    await DB.instance.resetStabilizationStatusForProject(
      widget.projectId,
      projectOrientation,
    );

    // 4. Clear ALL caches
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    ThumbnailService.instance.clearAllCache();

    // 5. Refresh settings and clear gallery state
    widget.refreshSettings();
    widget.clearRawAndStabPhotos();

    // 6. Restart stabilization
    widget.stabCallback();

    setState(() {
      _isSaving = false;
      _hasUnsavedChanges = false;
      _showCheckmark = true;
    });

    _checkmarkTimer?.cancel();
    _checkmarkTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showCheckmark = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_hasUnsavedChanges) {
          bool? saveChanges = await _showUnsavedChangesDialog();

          if (saveChanges == true) {
            await _saveChanges();
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          } else if (saveChanges == false) {
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          }
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.settingsBackground,
        appBar: _buildAppBar(),
        body: Stack(
          children: [
            Column(
              children: [
                _buildImageLayer(context),
                const SizedBox(height: 20.0),
              ],
            ),
            if (_isInfoWidgetVisible) _buildInfoBanner(),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showUnsavedChangesDialog() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.settingsCardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.save_outlined,
                color: AppColors.settingsAccent,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'Unsaved Changes',
                style: TextStyle(
                  color: AppColors.settingsTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'You have unsaved changes. Do you want to save them before leaving?',
                style: TextStyle(
                  color: AppColors.settingsTextSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16.0),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.orange.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.orange,
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'All photos will need to be re-stabilized.',
                        style: TextStyle(
                          color: AppColors.orange,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Discard',
                style: TextStyle(
                  color: AppColors.settingsTextSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text(
                'Save',
                style: TextStyle(
                  color: AppColors.settingsAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.settingsCardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(
              Icons.lightbulb_outline_rounded,
              color: AppColors.settingsAccent,
              size: 24,
            ),
            SizedBox(width: 12),
            Text(
              'Quick Guide',
              style: TextStyle(
                color: AppColors.settingsTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'This screen controls where eyes are positioned in the output frame.\n\n'
            'Drag the horizontal guide line up or down to adjust the vertical eye position.\n\n'
            'Drag the vertical guide lines left or right to adjust the horizontal eye spacing.\n\n'
            'Photos are transformed so that detected eyes align to these positions, ensuring consistent framing across all images in your timelapse.',
            style: TextStyle(
              color: AppColors.settingsTextSecondary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Got it',
              style: TextStyle(
                color: AppColors.settingsAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      toolbarHeight: 56,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      backgroundColor: AppColors.settingsBackground,
      title: const Text(
        'Output Position',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.settingsTextPrimary,
        ),
      ),
      leading: GestureDetector(
        onTap: () {
          if (_hasUnsavedChanges) {
            _showUnsavedChangesDialog().then((saveChanges) async {
              if (saveChanges == true) {
                await _saveChanges();
                if (mounted) Navigator.of(context).pop();
              } else if (saveChanges == false) {
                if (mounted) Navigator.of(context).pop();
              }
            });
          } else {
            Navigator.pop(context);
          }
        },
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.settingsCardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.settingsCardBorder, width: 1),
          ),
          child: const Icon(
            Icons.arrow_back,
            color: AppColors.settingsTextPrimary,
            size: 20,
          ),
        ),
      ),
      actions: [
        GestureDetector(
          onTap: _showHelpDialog,
          child: Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: AppColors.settingsCardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.settingsCardBorder, width: 1),
            ),
            child: const Icon(
              Icons.help_outline_rounded,
              color: AppColors.settingsTextSecondary,
              size: 20,
            ),
          ),
        ),
        if (_hasUnsavedChanges)
          GestureDetector(
            onTap: _isSaving
                ? null
                : () async {
                    final bool shouldProceed =
                        await Utils.showConfirmChangeDialog(
                      context,
                      "eye position",
                    );
                    if (shouldProceed) await _saveChanges();
                  },
            child: Container(
              width: 44,
              height: 44,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _showCheckmark
                    ? Colors.green.withValues(alpha: 0.15)
                    : AppColors.settingsAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _showCheckmark
                      ? Colors.green.withValues(alpha: 0.3)
                      : AppColors.settingsAccent.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: _isSaving
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.settingsAccent,
                      ),
                    )
                  : Icon(
                      _showCheckmark
                          ? Icons.check_circle_rounded
                          : Icons.save_rounded,
                      color: _showCheckmark
                          ? Colors.green
                          : AppColors.settingsAccent,
                      size: 22,
                    ),
            ),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.settingsDivider),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.settingsCardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.settingsCardBorder, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.settingsAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.lightbulb_outline_rounded,
                color: AppColors.settingsAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                "Drag guide lines to optimal position. Tap save to apply changes.\n"
                "Note: Camera guide lines don't affect output.",
                style: TextStyle(
                  color: AppColors.settingsTextSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _isInfoWidgetVisible = false),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.settingsCardBorder,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.close,
                  color: AppColors.settingsTextSecondary,
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageLayer(BuildContext context) {
    return Expanded(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Use actual output dimensions (handles custom resolutions)
          final double aspectRatioValue =
              outputImageLoader.getDisplayAspectRatio();

          final double maxW = constraints.maxWidth;
          final double maxH = constraints.maxHeight;

          double adjustedWidth = maxW;
          double adjustedHeight = adjustedWidth * aspectRatioValue;
          if (adjustedHeight > maxH) {
            adjustedHeight = maxH;
            adjustedWidth = adjustedHeight / aspectRatioValue;
          }

          final double leftPad = (maxW - adjustedWidth) / 2;
          final double topPad = (maxH - adjustedHeight) / 2;

          return Stack(
            children: [
              if (outputImageLoader.guideImage != null)
                Positioned(
                  left: leftPad,
                  right: leftPad,
                  top: topPad,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.settingsCardBorder,
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: SizedBox(
                        width: adjustedWidth,
                        height: adjustedHeight,
                        child: GestureDetector(
                          key: _widgetKey,
                          onPanStart: (details) {
                            final dx = details.localPosition.dx;
                            final dy = details.localPosition.dy;

                            final centerX = adjustedWidth / 2;
                            final leftX = centerX - _offsetX * adjustedWidth;
                            final rightX = centerX + _offsetX * adjustedWidth;
                            final centerY = _offsetY * adjustedHeight;

                            final distanceToLeftX = (dx - leftX).abs();
                            final distanceToRightX = (dx - rightX).abs();
                            final distanceToHorizontalLine =
                                (dy - centerY).abs();

                            setState(() {
                              _isDraggingVertical = (distanceToLeftX < 20 ||
                                  distanceToRightX < 20);
                              _draggingRight =
                                  distanceToRightX < distanceToLeftX;
                              _isDraggingHorizontal = (!_isDraggingVertical &&
                                  distanceToHorizontalLine < 20);
                            });
                          },
                          onPanUpdate: (details) {
                            if (_isDraggingVertical) {
                              setState(() {
                                final delta = details.delta.dx / adjustedWidth;
                                _offsetX += _draggingRight ? delta : -delta;
                                _offsetX = _offsetX.clamp(0.0, 1.0);
                                _hasUnsavedChanges = true;
                              });
                            } else if (_isDraggingHorizontal) {
                              setState(() {
                                final delta = details.delta.dy / adjustedHeight;
                                _offsetY += delta;
                                _offsetY = _offsetY.clamp(0.0, 1.0);
                                _hasUnsavedChanges = true;
                              });
                            }
                          },
                          onPanEnd: (details) {
                            _isDraggingVertical = false;
                            _isDraggingHorizontal = false;
                          },
                          child: CustomPaint(
                            painter: GridPainterSE(
                              _offsetX,
                              _offsetY,
                              outputImageLoader.ghostImageOffsetX,
                              outputImageLoader.ghostImageOffsetY,
                              outputImageLoader.guideImage,
                              outputImageLoader.aspectRatio!,
                              outputImageLoader.projectOrientation!,
                            ),
                            child: SizedBox(
                              width: adjustedWidth,
                              height: adjustedHeight,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (outputImageLoader.guideImage == null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.settingsAccent,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Loading preview...',
                        style: TextStyle(
                          color: AppColors.settingsTextSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
