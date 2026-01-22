import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'transform_controller.dart';
import 'transform_handle.dart';
import 'transform_handle_painter.dart';
import 'transform_state.dart';

/// A widget that provides Pixelmator-style transform controls for an image.
///
/// Supports:
/// - Drag to move
/// - Corner/edge handles to resize
/// - Rotation handle to rotate
/// - Keyboard shortcuts for precise adjustments
/// - Touch-optimized hit targets on mobile
///
/// The widget displays the image with a bounding box overlay and interactive
/// handles. Transform changes are reported via callbacks.
class TransformTool extends StatefulWidget {
  /// The image to transform (raw bytes)
  final Uint8List imageBytes;

  /// Size of the canvas/viewport
  final Size canvasSize;

  /// Size of the original image
  final Size imageSize;

  /// Base scale factor for database value conversion
  final double baseScale;

  /// Initial transform state (if restoring from saved values)
  final TransformState? initialState;

  /// Called whenever the transform changes during a gesture
  final ValueChanged<TransformState>? onChanged;

  /// Called when a gesture ends (good time to save)
  final ValueChanged<TransformState>? onChangeEnd;

  /// Optional overlay widget (e.g., guide lines)
  final Widget? overlay;

  /// Whether the transform tool is enabled
  final bool enabled;

  /// Whether to show the rotation handle
  final bool showRotationHandle;

  /// Whether to maintain aspect ratio by default when resizing
  final bool maintainAspectRatio;

  /// Optional external controller for programmatic control
  final TransformController? controller;

  /// Whether this is running on a touch device (larger hit targets)
  final bool? isTouchDevice;

  /// Scale factor from canvas resolution to display size.
  /// Used to counter-scale handle sizes so they appear consistent on screen.
  /// displayScale = previewWidth / canvasWidth
  final double displayScale;

  const TransformTool({
    super.key,
    required this.imageBytes,
    required this.canvasSize,
    required this.imageSize,
    required this.baseScale,
    this.initialState,
    this.onChanged,
    this.onChangeEnd,
    this.overlay,
    this.enabled = true,
    this.showRotationHandle = true,
    this.maintainAspectRatio = true,
    this.controller,
    this.isTouchDevice,
    this.displayScale = 1.0,
  });

  @override
  State<TransformTool> createState() => TransformToolState();
}

class TransformToolState extends State<TransformTool> {
  late TransformController _controller;
  bool _ownsController = false;

  TransformHandle _hoveredHandle = TransformHandle.none;
  ui.Image? _decodedImage;
  bool _imageLoading = true;
  int _decodeGeneration =
      0; // Track decode requests for race condition handling

  // For keyboard input
  final FocusNode _focusNode = FocusNode();

  // Platform detection for touch optimization
  late bool _isTouchDevice;

  @override
  void initState() {
    super.initState();
    _detectPlatform();
    _initController();
    _decodeImage();
  }

  void _detectPlatform() {
    if (widget.isTouchDevice != null) {
      _isTouchDevice = widget.isTouchDevice!;
    } else {
      // Auto-detect: iOS/Android are touch, desktop is not
      _isTouchDevice = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    }
  }

  void _initController() {
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
      // Update controller settings for touch devices
      _controller.handleHitRadius = _isTouchDevice ? 22.0 : 14.0;
      _controller.rotationZoneRadius = _isTouchDevice ? 35.0 : 25.0;
    } else {
      final initialState = widget.initialState ??
          TransformState.identity(
            imageSize: widget.imageSize,
            canvasSize: widget.canvasSize,
          );

      _controller = TransformController(
        initialState: initialState,
        baseScale: widget.baseScale,
        maintainAspectRatio: widget.maintainAspectRatio,
        // Larger hit targets for touch devices (44pt minimum recommended)
        handleHitRadius: _isTouchDevice ? 22.0 : 14.0,
        rotationZoneRadius: _isTouchDevice ? 35.0 : 25.0,
      );
      _ownsController = true;
    }

    _controller.addListener(_onControllerChanged);
  }

  Future<void> _decodeImage() async {
    final int generation = ++_decodeGeneration;

    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      codec.dispose();

      // Check if this decode is still relevant (not superseded by newer request)
      if (!mounted || generation != _decodeGeneration) {
        frame.image.dispose();
        return;
      }

      setState(() {
        _decodedImage?.dispose();
        _decodedImage = frame.image;
        _imageLoading = false;
      });
    } catch (e) {
      if (mounted && generation == _decodeGeneration) {
        setState(() {
          _imageLoading = false;
        });
      }
    }
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
      widget.onChanged?.call(_controller.state);
    }
  }

  @override
  void didUpdateWidget(TransformTool oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle controller changes
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChanged);
      if (_ownsController) {
        _controller.dispose();
      }
      _initController();
    }

    // Handle image changes
    if (widget.imageBytes != oldWidget.imageBytes) {
      _decodeImage();
    }

    // Handle canvas size changes
    if (widget.canvasSize != oldWidget.canvasSize) {
      _controller.updateCanvasSize(widget.canvasSize);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    _focusNode.dispose();
    _decodedImage?.dispose();
    super.dispose();
  }

  /// Public access to the controller
  TransformController get controller => _controller;

  /// Current transform state
  TransformState get state => _controller.state;

  /// Reset the transform to identity (centered, no rotation, scale = 1)
  void reset() {
    _controller.reset();
    widget.onChanged?.call(_controller.state);
    widget.onChangeEnd?.call(_controller.state);
  }

  /// Fit the image to the canvas
  void fitToCanvas() {
    _controller.fitToCanvas();
    widget.onChanged?.call(_controller.state);
    widget.onChangeEnd?.call(_controller.state);
  }

  /// Determine if edge handles should be shown based on image size
  /// Hide edge handles when the scaled image is too small to avoid clutter
  bool _shouldShowEdgeHandles() {
    final scaledSize = _controller.state.scaledImageSize;
    // Hide edge handles when either dimension is less than 80px
    return scaledSize.width >= 80 && scaledSize.height >= 80;
  }

  @override
  Widget build(BuildContext context) {
    // Adjust handle sizes for touch devices
    final handleSize = _isTouchDevice ? 14.0 : 10.0;
    final edgeHandleSize = _isTouchDevice ? 12.0 : 8.0;
    final rotationHandleSize = _isTouchDevice ? 16.0 : 12.0;

    return Semantics(
      label:
          'Image transform tool. Use arrow keys to move, brackets to rotate, plus minus to scale. Command Z to undo, Command Shift Z to redo.',
      value: _buildAccessibilityValue(),
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: widget.enabled ? _handleKeyEvent : null,
        child: MouseRegion(
          cursor: widget.enabled
              ? (_controller.isGestureActive
                  ? _controller.activeHandle.activeCursor
                  : _hoveredHandle.cursor)
              : SystemMouseCursors.basic,
          onHover: widget.enabled ? _onHover : null,
          onExit: (_) => setState(() => _hoveredHandle = TransformHandle.none),
          child: GestureDetector(
            // Request focus on any tap/click to enable keyboard shortcuts
            // This fires before pan detection, ensuring focus is grabbed
            // even if the user just clicks without dragging
            onTapDown: widget.enabled ? (_) => _focusNode.requestFocus() : null,
            onPanStart: widget.enabled ? _onPanStart : null,
            onPanUpdate: widget.enabled ? _onPanUpdate : null,
            onPanEnd: widget.enabled ? _onPanEnd : null,
            child: ClipRect(
              child: Stack(
                children: [
                  // Transformed image
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TransformedImagePainter(
                        image: _decodedImage,
                        state: _controller.state,
                        loading: _imageLoading,
                      ),
                    ),
                  ),

                  // Overlay (e.g., guide lines)
                  if (widget.overlay != null)
                    Positioned.fill(child: widget.overlay!),

                  // Transform handles
                  if (widget.enabled)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: TransformHandlePainter(
                          state: _controller.state,
                          activeHandle: _controller.activeHandle,
                          hoveredHandle: _hoveredHandle,
                          showRotationHandle: widget.showRotationHandle,
                          showCornerHandles: true,
                          showEdgeHandles: _shouldShowEdgeHandles(),
                          handleSize: handleSize,
                          edgeHandleSize: edgeHandleSize,
                          rotationHandleSize: rotationHandleSize,
                          displayScale: widget.displayScale,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _buildAccessibilityValue() {
    final state = _controller.state;
    return 'Position: ${state.translateX.toStringAsFixed(1)}, ${state.translateY.toStringAsFixed(1)}. '
        'Scale: ${(state.scale * 100).round()}%. '
        'Rotation: ${state.rotation.toStringAsFixed(1)} degrees.';
  }

  void _onHover(PointerHoverEvent event) {
    final handle = _controller.hitTest(event.localPosition);
    if (handle != _hoveredHandle) {
      setState(() => _hoveredHandle = handle);
    }
  }

  void _onPanStart(DragStartDetails details) {
    _focusNode.requestFocus();
    final handle = _controller.hitTest(details.localPosition);
    _controller.beginGesture(handle, details.localPosition);
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final shiftHeld = HardwareKeyboard.instance.isShiftPressed;
    final altHeld = HardwareKeyboard.instance.isAltPressed;

    _controller.updateGesture(
      details.localPosition,
      shiftHeld: shiftHeld,
      altHeld: altHeld,
    );
  }

  void _onPanEnd(DragEndDetails details) {
    _controller.endGesture();
    widget.onChangeEnd?.call(_controller.state);
    setState(() {});
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final shiftHeld = HardwareKeyboard.instance.isShiftPressed;
    final ctrlOrCmd = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    final nudgeAmount = shiftHeld ? 10.0 : 1.0;
    final rotateAmount = shiftHeld ? 15.0 : 1.0;
    final scaleAmount = shiftHeld ? 10.0 : 1.0;

    bool handled = true;

    switch (event.logicalKey) {
      // Arrow keys for nudging position
      case LogicalKeyboardKey.arrowLeft:
        _controller.commitToHistory();
        _controller.nudge(-nudgeAmount, 0);
        _announceChange('Moved left ${nudgeAmount.round()} pixels');
        break;
      case LogicalKeyboardKey.arrowRight:
        _controller.commitToHistory();
        _controller.nudge(nudgeAmount, 0);
        _announceChange('Moved right ${nudgeAmount.round()} pixels');
        break;
      case LogicalKeyboardKey.arrowUp:
        _controller.commitToHistory();
        _controller.nudge(0, -nudgeAmount);
        _announceChange('Moved up ${nudgeAmount.round()} pixels');
        break;
      case LogicalKeyboardKey.arrowDown:
        _controller.commitToHistory();
        _controller.nudge(0, nudgeAmount);
        _announceChange('Moved down ${nudgeAmount.round()} pixels');
        break;

      // Bracket keys for rotation
      case LogicalKeyboardKey.bracketLeft:
        _controller.commitToHistory();
        _controller.adjustRotation(-rotateAmount);
        _announceChange(
            'Rotated ${rotateAmount.round()} degrees counter-clockwise');
        break;
      case LogicalKeyboardKey.bracketRight:
        _controller.commitToHistory();
        _controller.adjustRotation(rotateAmount);
        _announceChange('Rotated ${rotateAmount.round()} degrees clockwise');
        break;

      // Plus/minus for scale
      case LogicalKeyboardKey.equal: // + key
      case LogicalKeyboardKey.add:
      case LogicalKeyboardKey.numpadAdd:
        _controller.commitToHistory();
        _controller.adjustScale(scaleAmount);
        _announceChange('Scaled up ${scaleAmount.round()}%');
        break;
      case LogicalKeyboardKey.minus:
      case LogicalKeyboardKey.numpadSubtract:
        _controller.commitToHistory();
        _controller.adjustScale(-scaleAmount);
        _announceChange('Scaled down ${scaleAmount.round()}%');
        break;

      // Escape to cancel gesture or reset
      case LogicalKeyboardKey.escape:
        if (_controller.isGestureActive) {
          _controller.cancelGesture();
          _announceChange('Gesture cancelled');
        }
        break;

      // Ctrl/Cmd+R to reset
      case LogicalKeyboardKey.keyR:
        if (ctrlOrCmd) {
          _controller.commitToHistory();
          _controller.reset();
          _announceChange('Transform reset');
        } else {
          handled = false;
        }
        break;

      // Ctrl/Cmd+0 to fit to canvas
      case LogicalKeyboardKey.digit0:
      case LogicalKeyboardKey.numpad0:
        if (ctrlOrCmd) {
          _controller.commitToHistory();
          _controller.fitToCanvas();
          _announceChange('Fit to canvas');
        } else {
          handled = false;
        }
        break;

      // Home key to reset
      case LogicalKeyboardKey.home:
        _controller.commitToHistory();
        _controller.reset();
        _announceChange('Transform reset');
        break;

      // Ctrl/Cmd+Z to undo
      case LogicalKeyboardKey.keyZ:
        if (ctrlOrCmd) {
          if (shiftHeld) {
            // Cmd+Shift+Z = Redo (macOS standard)
            if (_controller.redo()) {
              _announceChange('Redo');
            }
          } else {
            // Cmd+Z = Undo
            if (_controller.undo()) {
              _announceChange('Undo');
            }
          }
        } else {
          handled = false;
        }
        break;

      // Ctrl+Y to redo (Windows standard)
      case LogicalKeyboardKey.keyY:
        if (ctrlOrCmd) {
          if (_controller.redo()) {
            _announceChange('Redo');
          }
        } else {
          handled = false;
        }
        break;

      default:
        handled = false;
    }

    if (handled) {
      widget.onChanged?.call(_controller.state);
      widget.onChangeEnd?.call(_controller.state);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _announceChange(String message) {
    // Trigger a semantic announcement for screen readers
    // ignore: deprecated_member_use
    SemanticsService.announce(message, TextDirection.ltr);
  }
}

/// CustomPainter that draws the transformed image.
class _TransformedImagePainter extends CustomPainter {
  final ui.Image? image;
  final TransformState state;
  final bool loading;

  _TransformedImagePainter({
    required this.image,
    required this.state,
    required this.loading,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black,
    );

    if (image == null) {
      if (loading) {
        // Draw loading indicator
        _drawLoadingIndicator(canvas, size);
      }
      return;
    }

    // Save canvas state
    canvas.save();

    // Apply transforms
    final center = state.imageCenter;

    // Translate to image center
    canvas.translate(center.dx, center.dy);

    // Rotate
    canvas.rotate(state.rotationRadians);

    // Scale (use effectiveScale which includes baseScale)
    canvas.scale(state.effectiveScale);

    // Draw image centered at origin
    final srcRect = Rect.fromLTWH(
      0,
      0,
      image!.width.toDouble(),
      image!.height.toDouble(),
    );

    final dstRect = Rect.fromCenter(
      center: Offset.zero,
      width: state.imageSize.width,
      height: state.imageSize.height,
    );

    canvas.drawImageRect(
      image!,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.high,
    );

    // Restore canvas state
    canvas.restore();
  }

  void _drawLoadingIndicator(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      center,
      20,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_TransformedImagePainter oldDelegate) {
    return image != oldDelegate.image ||
        state != oldDelegate.state ||
        loading != oldDelegate.loading;
  }
}
