import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/database_helper.dart';
import '../../utils/dir_utils.dart';
import '../utils/utils.dart';
import '../widgets/grid_painter_se.dart';
import '../utils/output_image_loader.dart';

class SetEyePositionPage extends StatefulWidget {
  final int projectId;
  final String projectName;
  final Future<void> Function() cancelStabCallback;
  final VoidCallback refreshSettings;

  const SetEyePositionPage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.cancelStabCallback,
    required this.refreshSettings,
  });

  @override
  SetEyePositionPageState createState() => SetEyePositionPageState();
}

class SetEyePositionPageState extends State<SetEyePositionPage> {
  late double _defaultOffsetX;
  late double _defaultOffsetY;
  late double _offsetX;
  late double _offsetY;
  String? stabDirPath;
  String? offSetXColName;
  String? offSetYColName;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;
  bool _showCheckmark = false;
  bool _isDraggingVertical = false;
  bool _draggingRight = false;
  bool _isDraggingHorizontal = false;
  final GlobalKey _widgetKey = GlobalKey();
  double _widgetHeight = 0.0;
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
    super.dispose();
  }

  Future<void> _init() async {
    await outputImageLoader.initialize();

    setState(() {
      _defaultOffsetX = outputImageLoader.offsetX;
      _defaultOffsetY = outputImageLoader.offsetY;
      _offsetX = _defaultOffsetX;
      _offsetY = _defaultOffsetY;
    });

    stabDirPath = await DirUtils.getStabilizedDirPath(widget.projectId);
  }

  Future<void> _saveChanges() async {
    setState(() {
      _isSaving = true;
    });

    widget.cancelStabCallback();

    final projectOrientation = outputImageLoader.projectOrientation!;
    offSetXColName = projectOrientation == 'landscape'
        ? "eyeOffsetXLandscape"
        : "eyeOffsetXPortrait";
    offSetYColName = projectOrientation == 'landscape'
        ? "eyeOffsetYLandscape"
        : "eyeOffsetYPortrait";

    await DB.instance.setSettingByTitle(
        offSetXColName!, _offsetX.toString(), widget.projectId.toString());
    await DB.instance.setSettingByTitle(
        offSetYColName!, _offsetY.toString(), widget.projectId.toString());
    await DB.instance.resetStabilizationStatusForProject(
        widget.projectId, projectOrientation);
    widget.refreshSettings();
    await DirUtils.deleteDirectoryContents(Directory(stabDirPath!));

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

  void _getWidgetHeight() {
    final RenderBox renderBox =
        _widgetKey.currentContext!.findRenderObject() as RenderBox;
    setState(() {
      _widgetHeight = renderBox.size.height;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_hasUnsavedChanges) {
          bool? saveChanges = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Unsaved Changes'),
                content: const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                        'You have unsaved changes. Do you want to save them before leaving?'),
                    SizedBox(height: 16.0),
                    Text(
                      '⚠️ WARNING: ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('All photos will need to be re-stabilized.'),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  TextButton(
                    child: const Text('Save'),
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              );
            },
          );

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
        appBar: AppBar(
          title: const Text("Output Position"),
          actions: [
            if (_hasUnsavedChanges)
              IconButton(
                icon: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : (_showCheckmark
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : const Icon(Icons.playlist_add_check_circle)),
                onPressed: _isSaving
                    ? null
                    : () async {
                        final bool shouldProceed =
                            await Utils.showConfirmChangeDialog(
                                context, "eye position");
                        if (shouldProceed) await _saveChanges();
                      },
              ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                _buildImageLayer(context),
                const SizedBox(height: 20.0),
              ],
            ),
            if (_isInfoWidgetVisible)
              Positioned(
                bottom: 64,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.black
                        .withAlpha(230), // Equivalent to opacity 0.9
                    borderRadius:
                        BorderRadius.circular(16), // More rounded corners
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Drag guide lines to optimal position. Tap\n"
                        "checkmark to save changes. Note: Camera guide\n"
                        "lines don't affect output guide lines.",
                        style: TextStyle(color: Colors.white, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _isInfoWidgetVisible = false),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // TO REPLACE WITH
  Widget _buildImageLayer(BuildContext context) {
    return Expanded(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          double aspectRatioValue;
          if (outputImageLoader.aspectRatio == '4:3') {
            aspectRatioValue =
                outputImageLoader.projectOrientation == 'landscape'
                    ? 3 / 4
                    : 4 / 3;
          } else {
            aspectRatioValue =
                outputImageLoader.projectOrientation == 'landscape'
                    ? 9 / 16
                    : 16 / 9;
          }

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
                        final distanceToHorizontalLine = (dy - centerY).abs();

                        setState(() {
                          _isDraggingVertical =
                              (distanceToLeftX < 20 || distanceToRightX < 20);
                          _draggingRight = distanceToRightX < distanceToLeftX;
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
                      child: ClipRect(
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
            ],
          );
        },
      ),
    );
  }
}
