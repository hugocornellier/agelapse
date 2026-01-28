import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/database_helper.dart';
import '../../services/thumbnail_service.dart';
import '../styles/styles.dart';
import '../utils/utils.dart';
import '../widgets/grid_painter_se.dart';
import '../widgets/info_tooltip_icon.dart';
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
  MouseCursor _currentCursor = SystemMouseCursors.basic;
  final GlobalKey _widgetKey = GlobalKey();
  late OutputImageLoader outputImageLoader;
  bool _isInfoWidgetVisible = true;
  Timer? _checkmarkTimer;

  // Text input controllers and state
  final TextEditingController _xController = TextEditingController();
  final TextEditingController _yController = TextEditingController();
  final FocusNode _xFocusNode = FocusNode();
  final FocusNode _yFocusNode = FocusNode();
  bool _suppressTextListener = false;
  Timer? _textDebounce;
  bool _controlsExpanded = true;

  @override
  void initState() {
    super.initState();
    outputImageLoader = OutputImageLoader(widget.projectId);
    _init();

    // Set up text input listeners
    _xController.addListener(_onTextChanged);
    _yController.addListener(_onTextChanged);
    _xFocusNode.addListener(_onXFocusChanged);
    _yFocusNode.addListener(_onYFocusChanged);
  }

  @override
  void dispose() {
    _checkmarkTimer?.cancel();
    _textDebounce?.cancel();
    _xController.removeListener(_onTextChanged);
    _yController.removeListener(_onTextChanged);
    _xFocusNode.removeListener(_onXFocusChanged);
    _yFocusNode.removeListener(_onYFocusChanged);
    _xController.dispose();
    _yController.dispose();
    _xFocusNode.dispose();
    _yFocusNode.dispose();
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

    // Initialize text controllers with current values (as percentages)
    _updateTextControllersFromOffsets();
  }

  /// Converts internal offset (0.0-1.0) to display percentage (0-100)
  String _offsetToPercent(double offset) {
    return (offset * 100).toStringAsFixed(2);
  }

  /// Converts internal X offset to display percentage (doubled for eye distance)
  String _offsetXToPercent(double offset) {
    return (offset * 2 * 100).toStringAsFixed(2);
  }

  /// Converts display percentage (0-100) to internal offset (0.0-1.0)
  double _percentToOffset(String text) {
    final parsed = double.tryParse(text);
    if (parsed == null) return 0.0;
    return (parsed / 100).clamp(0.0, 1.0);
  }

  /// Converts display X percentage to internal offset (halved for storage)
  double _percentToOffsetX(String text) {
    final parsed = double.tryParse(text);
    if (parsed == null) return 0.0;
    return (parsed / 200).clamp(0.0, 0.5);
  }

  /// Updates text controllers from current offset values (drag → text)
  void _updateTextControllersFromOffsets() {
    _suppressTextListener = true;
    _xController.text = _offsetXToPercent(_offsetX);
    _yController.text = _offsetToPercent(_offsetY);
    _suppressTextListener = false;
  }

  /// Called when text changes - debounced to avoid excessive updates
  void _onTextChanged() {
    if (_suppressTextListener) return;

    _textDebounce?.cancel();
    _textDebounce = Timer(const Duration(milliseconds: 300), () {
      _applyTextInputValues();
    });
  }

  /// Applies values from text inputs to the offset state
  void _applyTextInputValues() {
    final newX = _percentToOffsetX(_xController.text);
    final newY = _percentToOffset(_yController.text);

    if ((newX - _offsetX).abs() > 0.0001 || (newY - _offsetY).abs() > 0.0001) {
      setState(() {
        _offsetX = newX;
        _offsetY = newY;
        _hasUnsavedChanges = true;
      });
    }
  }

  /// Focus lost on X field - commit and validate
  void _onXFocusChanged() {
    if (!_xFocusNode.hasFocus) {
      _commitTextValueX(_xController, _offsetX);
    }
  }

  /// Focus lost on Y field - commit and validate
  void _onYFocusChanged() {
    if (!_yFocusNode.hasFocus) {
      _commitTextValueY(_yController, _offsetY);
    }
  }

  /// Validates and normalizes X text input on blur (max 100% = 0.5 internal)
  void _commitTextValueX(
      TextEditingController controller, double currentOffset) {
    final text = controller.text.trim();
    final parsed = double.tryParse(text);

    if (parsed == null || parsed < 0 || parsed > 100) {
      // Invalid - revert to current offset value
      _suppressTextListener = true;
      controller.text = _offsetXToPercent(currentOffset);
      _suppressTextListener = false;
    } else {
      // Valid - apply the value
      _applyTextInputValues();
    }
  }

  /// Validates and normalizes Y text input on blur
  void _commitTextValueY(
      TextEditingController controller, double currentOffset) {
    final text = controller.text.trim();
    final parsed = double.tryParse(text);

    if (parsed == null || parsed < 0 || parsed > 100) {
      // Invalid - revert to current offset value
      _suppressTextListener = true;
      controller.text = _offsetToPercent(currentOffset);
      _suppressTextListener = false;
    } else {
      // Valid - apply the value
      _applyTextInputValues();
    }
  }

  /// Adjusts X offset by delta percentage points (in display units, doubled)
  void _adjustX(double deltaPct) {
    // Display shows _offsetX * 2 * 100, so to change display by deltaPct,
    // we change _offsetX by deltaPct / 200
    final newX = (_offsetX + deltaPct / 200).clamp(0.0, 0.5);
    setState(() {
      _offsetX = newX;
      _hasUnsavedChanges = true;
    });
    _updateTextControllersFromOffsets();
  }

  /// Adjusts Y offset by delta percentage points
  void _adjustY(double deltaPct) {
    final newY = ((_offsetY * 100) + deltaPct).clamp(0.0, 100.0) / 100;
    setState(() {
      _offsetY = newY;
      _hasUnsavedChanges = true;
    });
    _updateTextControllersFromOffsets();
  }

  Widget _buildControlsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Collapsible header
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() => _controlsExpanded = !_controlsExpanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: AppColors.settingsTextSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'POSITION CONTROLS',
                    style: TextStyle(
                      fontSize: AppTypography.sm,
                      fontWeight: FontWeight.w600,
                      color: AppColors.settingsTextSecondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _controlsExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: AppColors.settingsTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Collapsible content
        AnimatedCrossFade(
          firstChild: Container(
            decoration: BoxDecoration(
              color: AppColors.settingsCardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.settingsCardBorder, width: 1),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildOffsetInput(
                    controller: _xController,
                    focusNode: _xFocusNode,
                    label: 'Eye Distance',
                    icon: Icons.swap_horiz_rounded,
                    onDecrement: () => _adjustX(-0.1),
                    onIncrement: () => _adjustX(0.1),
                    tooltip:
                        'The spacing between the eye guide lines, shown as a percentage of the image width.',
                  ),
                ),
                Container(
                  width: 1,
                  height: 50,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: AppColors.settingsCardBorder,
                ),
                Expanded(
                  child: _buildOffsetInput(
                    controller: _yController,
                    focusNode: _yFocusNode,
                    label: 'Vertical Offset',
                    icon: Icons.swap_vert_rounded,
                    onDecrement: () => _adjustY(-0.1),
                    onIncrement: () => _adjustY(0.1),
                    tooltip:
                        'How far down the eye guide line sits, shown as a percentage of the image height.',
                  ),
                ),
              ],
            ),
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState: _controlsExpanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Widget _buildOffsetInput({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
    String? tooltip,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppColors.settingsTextTertiary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: AppTypography.sm,
                color: AppColors.settingsTextTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (tooltip != null) InfoTooltipIcon(content: tooltip),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Decrement button
            _buildIncrementButton(
              icon: Icons.remove_rounded,
              onTap: onDecrement,
            ),
            const SizedBox(width: 8),
            // Text input with % suffix
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.settingsCardBorder,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: false,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*$'),
                          ),
                        ],
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: AppTypography.lg,
                          color: AppColors.settingsTextPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          border: InputBorder.none,
                          hintText: '0',
                          hintStyle: TextStyle(
                            color: AppColors.settingsTextTertiary,
                          ),
                        ),
                        onSubmitted: (_) => focusNode.unfocus(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        '%',
                        style: TextStyle(
                          fontSize: AppTypography.lg,
                          color: AppColors.settingsTextSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Increment button
            _buildIncrementButton(
              icon: Icons.add_rounded,
              onTap: onIncrement,
            ),
          ],
        ),
      ],
    );
  }

  /// Determines the appropriate cursor based on proximity to guide lines
  MouseCursor _getCursorForPosition(
    Offset position,
    double width,
    double height,
  ) {
    const threshold = 20.0;

    final centerX = width / 2;
    final leftX = centerX - _offsetX * width;
    final rightX = centerX + _offsetX * width;
    final lineY = _offsetY * height;

    final distanceToLeftX = (position.dx - leftX).abs();
    final distanceToRightX = (position.dx - rightX).abs();
    final distanceToHorizontalLine = (position.dy - lineY).abs();

    // Vertical lines get priority (same as drag logic)
    if (distanceToLeftX < threshold || distanceToRightX < threshold) {
      return SystemMouseCursors.resizeColumn;
    }
    if (distanceToHorizontalLine < threshold) {
      return SystemMouseCursors.resizeRow;
    }
    return SystemMouseCursors.basic;
  }

  Widget _buildIncrementButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.settingsCardBorder,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: AppColors.settingsTextSecondary,
          ),
        ),
      ),
    );
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
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildControlsSection(),
                    const SizedBox(height: 16.0),
                    Expanded(child: _buildImageLayer(context)),
                  ],
                ),
              ),
              if (_isInfoWidgetVisible) _buildInfoBanner(),
            ],
          ),
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
          title: Row(
            children: [
              Icon(
                Icons.save_outlined,
                color: AppColors.settingsAccent,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Unsaved Changes',
                style: TextStyle(
                  color: AppColors.settingsTextPrimary,
                  fontSize: AppTypography.xl,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'You have unsaved changes. Do you want to save them before leaving?',
                style: TextStyle(
                  color: AppColors.settingsTextSecondary,
                  fontSize: AppTypography.md,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16.0),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningMuted.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.warningMuted.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.warningMuted,
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'All photos will need to be re-stabilized.',
                        style: TextStyle(
                          color: AppColors.warningMuted,
                          fontSize: AppTypography.sm,
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
              child: Text(
                'Discard',
                style: TextStyle(
                  color: AppColors.settingsTextSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: Text(
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
        title: Row(
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
                fontSize: AppTypography.xl,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            'This screen controls where eyes are positioned in the output frame.\n\n'
            'Drag the horizontal guide line up or down to adjust the vertical eye position.\n\n'
            'Drag the vertical guide lines left or right to adjust the horizontal eye spacing.\n\n'
            'Your photos are transformed so that detected eyes align to these positions.',
            style: TextStyle(
              color: AppColors.settingsTextSecondary,
              fontSize: AppTypography.md,
              height: 1.6,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
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
      title: Text(
        'Output Position',
        style: TextStyle(
          fontSize: AppTypography.xxl,
          fontWeight: FontWeight.w600,
          color: AppColors.settingsTextPrimary,
        ),
      ),
      leading: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
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
            child: Icon(
              Icons.arrow_back,
              color: AppColors.settingsTextPrimary,
              size: 20,
            ),
          ),
        ),
      ),
      actions: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _showHelpDialog,
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppColors.settingsCardBackground,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.settingsCardBorder, width: 1),
              ),
              child: Icon(
                Icons.help_outline_rounded,
                color: AppColors.settingsTextSecondary,
                size: 20,
              ),
            ),
          ),
        ),
        if (_hasUnsavedChanges)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
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
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.settingsAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _showCheckmark
                        ? AppColors.success.withValues(alpha: 0.3)
                        : AppColors.settingsAccent.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: _isSaving
                    ? Padding(
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
                            ? AppColors.success
                            : AppColors.settingsAccent,
                        size: 22,
                      ),
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
              child: Icon(
                Icons.lightbulb_outline_rounded,
                color: AppColors.settingsAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                "Drag lines or edit values above. Tap save to apply.\n"
                "Note: Output guide lines are separate from your camera guide lines.",
                style: TextStyle(
                  color: AppColors.settingsTextSecondary,
                  fontSize: AppTypography.sm,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(width: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => setState(() => _isInfoWidgetVisible = false),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.settingsCardBorder,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.close,
                    color: AppColors.settingsTextSecondary,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageLayer(BuildContext context) {
    return LayoutBuilder(
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
                      child: MouseRegion(
                        cursor: _currentCursor,
                        onHover: (event) {
                          final newCursor = _getCursorForPosition(
                            event.localPosition,
                            adjustedWidth,
                            adjustedHeight,
                          );
                          if (newCursor != _currentCursor) {
                            setState(() {
                              _currentCursor = newCursor;
                            });
                          }
                        },
                        onExit: (_) {
                          if (_currentCursor != SystemMouseCursors.basic) {
                            setState(() {
                              _currentCursor = SystemMouseCursors.basic;
                            });
                          }
                        },
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
                              _updateTextControllersFromOffsets();
                            } else if (_isDraggingHorizontal) {
                              setState(() {
                                final delta = details.delta.dy / adjustedHeight;
                                _offsetY += delta;
                                _offsetY = _offsetY.clamp(0.0, 1.0);
                                _hasUnsavedChanges = true;
                              });
                              _updateTextControllersFromOffsets();
                            }
                          },
                          onPanEnd: (details) {
                            _isDraggingVertical = false;
                            _isDraggingHorizontal = false;
                            _updateTextControllersFromOffsets();
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
                              hideToolTip: true,
                              backgroundColor:
                                  outputImageLoader.backgroundColor,
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
              ),
            if (outputImageLoader.guideImage == null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.settingsAccent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading preview...',
                      style: TextStyle(
                        color: AppColors.settingsTextSecondary,
                        fontSize: AppTypography.md,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
