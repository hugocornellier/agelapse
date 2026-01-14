import 'package:flutter/widgets.dart';

import 'transform_gesture_handler.dart';
import 'transform_handle.dart';
import 'transform_history.dart';
import 'transform_state.dart';

/// Controller for managing transform state and handling gestures.
///
/// This is a ChangeNotifier that can be listened to for state updates.
/// It manages the transform state and provides methods for applying
/// gestures and direct value changes.
class TransformController extends ChangeNotifier {
  TransformState _state;
  TransformState? _dragStartState;
  Offset? _dragStartPosition;
  TransformHandle _activeHandle = TransformHandle.none;

  /// Configuration
  bool maintainAspectRatio;
  bool snapToAngles;
  double handleHitRadius;
  double rotationHandleDistance;
  double rotationZoneRadius;

  /// Base scale factor for database value conversion
  final double baseScale;

  /// History manager for undo/redo support
  final TransformHistory _history;

  /// Whether history is enabled (can be disabled for programmatic changes)
  bool historyEnabled;

  TransformController({
    required TransformState initialState,
    required this.baseScale,
    this.maintainAspectRatio = true,
    this.snapToAngles = false,
    this.handleHitRadius = 14.0,
    this.rotationHandleDistance = 30.0,
    this.rotationZoneRadius = 25.0,
    this.historyEnabled = true,
    int maxHistorySize = 100,
  })  : _state = initialState,
        _history = TransformHistory(maxHistorySize: maxHistorySize);

  /// Create controller from database values
  factory TransformController.fromDatabaseValues({
    required double translateX,
    required double translateY,
    required double scaleFactor,
    required double rotationDegrees,
    required Size imageSize,
    required Size canvasSize,
    required double baseScale,
  }) {
    final state = TransformState(
      translateX: translateX,
      translateY: translateY,
      scale: scaleFactor / baseScale,
      rotation: rotationDegrees,
      pivot: Offset(canvasSize.width / 2, canvasSize.height / 2),
      imageSize: imageSize,
      canvasSize: canvasSize,
      baseScale: baseScale,
    );

    return TransformController(
      initialState: state,
      baseScale: baseScale,
    );
  }

  /// Current transform state
  TransformState get state => _state;

  /// Whether a gesture is currently in progress
  bool get isGestureActive => _activeHandle != TransformHandle.none;

  /// The currently active handle
  TransformHandle get activeHandle => _activeHandle;

  /// Effective scale factor (actual multiplier including base scale)
  double get effectiveScaleFactor => _state.scale * baseScale;

  /// Whether undo is available
  bool get canUndo => _history.canUndo;

  /// Whether redo is available
  bool get canRedo => _history.canRedo;

  /// Update the state and notify listeners
  void _updateState(TransformState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  /// Commit the current state to history.
  ///
  /// Call this after completing an action that should be undoable.
  /// This is automatically called at the end of gestures, but should be
  /// called manually after text field changes or other discrete actions.
  void commitToHistory() {
    if (historyEnabled) {
      _history.push(_state);
    }
  }

  /// Undo the last action.
  ///
  /// Returns true if undo was successful, false if nothing to undo.
  bool undo() {
    final previousState = _history.undo(_state);
    if (previousState != null) {
      _updateState(previousState);
      return true;
    }
    return false;
  }

  /// Redo the last undone action.
  ///
  /// Returns true if redo was successful, false if nothing to redo.
  bool redo() {
    final nextState = _history.redo(_state);
    if (nextState != null) {
      _updateState(nextState);
      return true;
    }
    return false;
  }

  /// Clear all history (both undo and redo stacks)
  void clearHistory() {
    _history.clear();
  }

  /// Begin a gesture operation.
  ///
  /// [handle] The handle being interacted with
  /// [position] The starting position in canvas coordinates
  void beginGesture(TransformHandle handle, Offset position) {
    _activeHandle = handle;
    _dragStartState = _state;
    _dragStartPosition = position;

    // Push current state to history before starting the gesture
    // This allows undo to restore the pre-gesture state
    if (historyEnabled && handle != TransformHandle.none) {
      _history.push(_state);
    }
  }

  /// Update an ongoing gesture.
  ///
  /// [position] Current position in canvas coordinates
  /// [shiftHeld] Whether shift key is pressed (affects behavior)
  /// [altHeld] Whether alt/option key is pressed (scale from center)
  void updateGesture(
    Offset position, {
    bool shiftHeld = false,
    bool altHeld = false,
  }) {
    if (_dragStartState == null || _dragStartPosition == null) return;

    TransformState newState;

    switch (_activeHandle) {
      case TransformHandle.body:
        // Drag to translate
        final delta = position - _dragStartPosition!;
        newState = TransformGestureHandler.applyDrag(_dragStartState!, delta);
        break;

      case TransformHandle.rotationHandle:
        // Rotate around image center
        newState = TransformGestureHandler.applyRotation(
          startState: _dragStartState!,
          startPosition: _dragStartPosition!,
          currentPosition: position,
          snapToAngles: shiftHeld || snapToAngles,
        );
        break;

      case TransformHandle.topLeft:
      case TransformHandle.topRight:
      case TransformHandle.bottomLeft:
      case TransformHandle.bottomRight:
      case TransformHandle.topCenter:
      case TransformHandle.bottomCenter:
      case TransformHandle.leftCenter:
      case TransformHandle.rightCenter:
        // Scale from handle
        final shouldMaintainAspect = _activeHandle.isCorner
            ? (shiftHeld ? !maintainAspectRatio : maintainAspectRatio)
            : (shiftHeld || maintainAspectRatio);

        newState = TransformGestureHandler.applyScale(
          state: _state,
          handle: _activeHandle,
          startPosition: _dragStartPosition!,
          currentPosition: position,
          startState: _dragStartState!,
          maintainAspectRatio: shouldMaintainAspect,
          scaleFromCenter: altHeld,
        );
        break;

      case TransformHandle.none:
        return;
    }

    _updateState(newState);
  }

  /// End the current gesture.
  void endGesture() {
    _activeHandle = TransformHandle.none;
    _dragStartState = null;
    _dragStartPosition = null;
  }

  /// Cancel the current gesture and revert to start state.
  void cancelGesture() {
    if (_dragStartState != null) {
      _updateState(_dragStartState!);
    }
    endGesture();
  }

  // ============ Direct Value Setters ============

  /// Set translation values directly
  void setTranslation(double x, double y) {
    _updateState(_state.copyWith(translateX: x, translateY: y));
  }

  /// Set scale value directly (as multiplier, not including base scale)
  void setScale(double scale) {
    _updateState(_state.copyWith(scale: scale.clamp(0.1, 10.0)));
  }

  /// Set scale factor directly (including base scale)
  void setScaleFactor(double scaleFactor) {
    setScale(scaleFactor / baseScale);
  }

  /// Set rotation value directly (in degrees)
  void setRotation(double degrees) {
    var normalized = degrees;
    while (normalized > 180) {
      normalized -= 360;
    }
    while (normalized < -180) {
      normalized += 360;
    }
    _updateState(_state.copyWith(rotation: normalized));
  }

  /// Set all transform values at once
  void setTransform({
    double? translateX,
    double? translateY,
    double? scale,
    double? rotation,
  }) {
    _updateState(_state.copyWith(
      translateX: translateX,
      translateY: translateY,
      scale: scale?.clamp(0.1, 10.0),
      rotation: rotation,
    ));
  }

  /// Set transform from database values
  void setFromDatabaseValues({
    required double translateX,
    required double translateY,
    required double scaleFactor,
    required double rotationDegrees,
  }) {
    _updateState(_state.copyWith(
      translateX: translateX,
      translateY: translateY,
      scale: (scaleFactor / baseScale).clamp(0.1, 10.0),
      rotation: rotationDegrees,
    ));
  }

  // ============ Keyboard Shortcuts ============

  /// Nudge position by pixels
  void nudge(double dx, double dy) {
    _updateState(TransformGestureHandler.nudge(_state, dx, dy));
  }

  /// Adjust rotation by degrees
  void adjustRotation(double deltaDegrees) {
    _updateState(TransformGestureHandler.adjustRotation(
      _state,
      deltaDegrees,
      snapToAngles: snapToAngles,
    ));
  }

  /// Adjust scale by percentage
  void adjustScale(double deltaPercent) {
    _updateState(TransformGestureHandler.adjustScale(_state, deltaPercent));
  }

  /// Reset to identity transform
  void reset() {
    _updateState(TransformGestureHandler.reset(_state));
  }

  /// Fit image to canvas
  void fitToCanvas() {
    _updateState(TransformGestureHandler.fitToCanvas(_state));
  }

  // ============ Hit Testing ============

  /// Determine which handle (if any) is at the given position.
  TransformHandle hitTest(Offset position) {
    // 1. Check rotation handle first
    final rotHandlePos =
        _state.getRotationHandlePosition(rotationHandleDistance);
    if ((position - rotHandlePos).distance <= handleHitRadius) {
      return TransformHandle.rotationHandle;
    }

    // 2. Check corner handles
    final corners = _state.corners;
    for (int i = 0; i < cornerHandles.length; i++) {
      if ((position - corners[i]).distance <= handleHitRadius) {
        return cornerHandles[i];
      }
    }

    // 3. Check edge handles
    final edges = _state.edgeMidpoints;
    for (int i = 0; i < edgeHandles.length; i++) {
      if ((position - edges[i]).distance <= handleHitRadius) {
        return edgeHandles[i];
      }
    }

    // 4. Check if inside image bounds (body drag)
    if (_state.containsPoint(position)) {
      return TransformHandle.body;
    }

    // 5. Check rotation zone (near corners but outside bounds)
    if (_isInRotationZone(position)) {
      return TransformHandle.rotationHandle;
    }

    return TransformHandle.none;
  }

  /// Check if position is in the rotation zone (near corners, outside bounds)
  bool _isInRotationZone(Offset position) {
    if (_state.containsPoint(position)) return false;

    for (final corner in _state.corners) {
      final distance = (position - corner).distance;
      if (distance <= rotationZoneRadius && distance > handleHitRadius) {
        return true;
      }
    }

    return false;
  }

  // ============ Export ============

  /// Convert current state to database values
  Map<String, double> toDatabaseValues() {
    return _state.toDatabaseValues(baseScale);
  }

  /// Get individual database values
  double get databaseTranslateX => _state.translateX;
  double get databaseTranslateY => _state.translateY;
  double get databaseScaleFactor => _state.scale * baseScale;
  double get databaseRotationDegrees => _state.rotation;

  // ============ Canvas/Image Size Updates ============

  /// Update canvas size (e.g., on window resize)
  void updateCanvasSize(Size newSize) {
    if (_state.canvasSize != newSize) {
      _updateState(_state.copyWith(
        canvasSize: newSize,
        pivot: Offset(newSize.width / 2, newSize.height / 2),
      ));
    }
  }

  /// Update image size
  void updateImageSize(Size newSize) {
    if (_state.imageSize != newSize) {
      _updateState(_state.copyWith(imageSize: newSize));
    }
  }
}
