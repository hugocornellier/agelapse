import 'transform_state.dart';

/// Manages undo/redo history for transform operations.
///
/// Uses a linear history stack pattern:
/// - Undo moves backward through history, pushing current state to redo stack
/// - Redo moves forward, pushing current state to undo stack
/// - New actions clear the redo stack
///
/// This is the industry-standard approach used by Pixelmator, Photoshop,
/// Figma, and other professional graphics software.
class TransformHistory {
  final List<TransformState> _undoStack = [];
  final List<TransformState> _redoStack = [];

  /// Maximum number of history states to keep (memory management)
  final int maxHistorySize;

  TransformHistory({this.maxHistorySize = 100});

  /// Whether there are states available to undo
  bool get canUndo => _undoStack.isNotEmpty;

  /// Whether there are states available to redo
  bool get canRedo => _redoStack.isNotEmpty;

  /// Number of undo steps available
  int get undoCount => _undoStack.length;

  /// Number of redo steps available
  int get redoCount => _redoStack.length;

  /// Push a new state onto the history stack.
  ///
  /// This should be called when a gesture ends or a discrete action completes.
  /// Clears the redo stack (standard behavior - you can't redo after new action).
  void push(TransformState state) {
    // Don't push duplicate states
    if (_undoStack.isNotEmpty && _undoStack.last == state) {
      return;
    }

    _undoStack.add(state);
    _redoStack.clear();

    // Trim history if it exceeds max size
    if (_undoStack.length > maxHistorySize) {
      _undoStack.removeAt(0);
    }
  }

  /// Undo: returns the previous state, or null if nothing to undo.
  ///
  /// [currentState] is pushed to the redo stack before returning.
  TransformState? undo(TransformState currentState) {
    if (!canUndo) return null;

    // Push current state to redo stack
    _redoStack.add(currentState);

    // Pop and return previous state
    return _undoStack.removeLast();
  }

  /// Redo: returns the next state, or null if nothing to redo.
  ///
  /// [currentState] is pushed to the undo stack before returning.
  TransformState? redo(TransformState currentState) {
    if (!canRedo) return null;

    // Push current state to undo stack
    _undoStack.add(currentState);

    // Pop and return next state
    return _redoStack.removeLast();
  }

  /// Clear all history (both undo and redo stacks)
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }

  /// Replace the entire history with a new initial state.
  ///
  /// Useful when loading a new image or resetting the tool.
  void reset(TransformState initialState) {
    clear();
    // Don't push initial state - it will be pushed on first change
  }
}
