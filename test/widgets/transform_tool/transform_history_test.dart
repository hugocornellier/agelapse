import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/transform_tool/transform_history.dart';
import 'package:agelapse/widgets/transform_tool/transform_state.dart';

void main() {
  // Helper function to create test states
  TransformState createState({double translateX = 0}) {
    return TransformState(
      translateX: translateX,
      translateY: 0,
      scale: 1.0,
      rotation: 0,
      pivot: const Offset(50, 50),
      imageSize: const Size(100, 100),
      canvasSize: const Size(100, 100),
    );
  }

  group('TransformHistory', () {
    group('constructor', () {
      test('creates instance with default max history size', () {
        final history = TransformHistory();

        expect(history.canUndo, isFalse);
        expect(history.canRedo, isFalse);
        expect(history.undoCount, equals(0));
        expect(history.redoCount, equals(0));
      });

      test('accepts custom max history size', () {
        final history = TransformHistory(maxHistorySize: 50);

        // Can't directly test maxHistorySize, but construction should succeed
        expect(history.canUndo, isFalse);
      });
    });

    group('push', () {
      test('adds state to undo stack', () {
        final history = TransformHistory();
        final state = createState(translateX: 10);

        history.push(state);

        expect(history.canUndo, isTrue);
        expect(history.undoCount, equals(1));
      });

      test('clears redo stack after push', () {
        final history = TransformHistory();
        final state1 = createState(translateX: 10);
        final state2 = createState(translateX: 20);
        final state3 = createState(translateX: 30);

        history.push(state1);
        history.push(state2);
        history.undo(state2); // Creates redo state

        expect(history.canRedo, isTrue);

        history.push(state3); // Should clear redo

        expect(history.canRedo, isFalse);
      });

      test('does not push duplicate consecutive states', () {
        final history = TransformHistory();
        final state = createState(translateX: 10);

        history.push(state);
        history.push(state); // Duplicate

        expect(history.undoCount, equals(1));
      });

      test('trims history when max size exceeded', () {
        final history = TransformHistory(maxHistorySize: 3);

        history.push(createState(translateX: 10));
        history.push(createState(translateX: 20));
        history.push(createState(translateX: 30));
        history.push(createState(translateX: 40)); // Should trim oldest

        expect(history.undoCount, equals(3));
      });
    });

    group('canUndo', () {
      test('returns false when stack is empty', () {
        final history = TransformHistory();
        expect(history.canUndo, isFalse);
      });

      test('returns true when stack has items', () {
        final history = TransformHistory();
        history.push(createState());
        expect(history.canUndo, isTrue);
      });
    });

    group('canRedo', () {
      test('returns false when redo stack is empty', () {
        final history = TransformHistory();
        expect(history.canRedo, isFalse);
      });

      test('returns true after undo', () {
        final history = TransformHistory();
        final state1 = createState(translateX: 10);
        final state2 = createState(translateX: 20);

        history.push(state1);
        history.undo(state2);

        expect(history.canRedo, isTrue);
      });
    });

    group('undo', () {
      test('returns null when nothing to undo', () {
        final history = TransformHistory();
        final result = history.undo(createState());

        expect(result, isNull);
      });

      test('returns previous state', () {
        final history = TransformHistory();
        final state1 = createState(translateX: 10);
        final state2 = createState(translateX: 20);

        history.push(state1);
        final result = history.undo(state2);

        expect(result, equals(state1));
      });

      test('pushes current state to redo stack', () {
        final history = TransformHistory();
        final state1 = createState(translateX: 10);
        final state2 = createState(translateX: 20);

        history.push(state1);
        history.undo(state2);

        expect(history.canRedo, isTrue);
        expect(history.redoCount, equals(1));
      });

      test('decrements undo count', () {
        final history = TransformHistory();
        history.push(createState(translateX: 10));
        history.push(createState(translateX: 20));

        expect(history.undoCount, equals(2));

        history.undo(createState(translateX: 30));

        expect(history.undoCount, equals(1));
      });
    });

    group('redo', () {
      test('returns null when nothing to redo', () {
        final history = TransformHistory();
        final result = history.redo(createState());

        expect(result, isNull);
      });

      test('returns next state after undo', () {
        final history = TransformHistory();
        final state1 = createState(translateX: 10);
        final state2 = createState(translateX: 20);

        history.push(state1);
        history.undo(state2); // state2 goes to redo stack

        final result = history.redo(state1);

        expect(result, equals(state2));
      });

      test('pushes current state to undo stack', () {
        final history = TransformHistory();
        final state1 = createState(translateX: 10);
        final state2 = createState(translateX: 20);

        history.push(state1);
        history.undo(state2);

        expect(history.undoCount, equals(0));

        history.redo(state1);

        expect(history.undoCount, equals(1));
      });

      test('decrements redo count', () {
        final history = TransformHistory();
        final state1 = createState(translateX: 10);
        final state2 = createState(translateX: 20);

        history.push(state1);
        history.undo(state2);

        expect(history.redoCount, equals(1));

        history.redo(state1);

        expect(history.redoCount, equals(0));
      });
    });

    group('clear', () {
      test('removes all undo and redo states', () {
        final history = TransformHistory();
        history.push(createState(translateX: 10));
        history.push(createState(translateX: 20));
        history.undo(createState(translateX: 30));

        expect(history.canUndo, isTrue);
        expect(history.canRedo, isTrue);

        history.clear();

        expect(history.canUndo, isFalse);
        expect(history.canRedo, isFalse);
        expect(history.undoCount, equals(0));
        expect(history.redoCount, equals(0));
      });
    });

    group('reset', () {
      test('clears all history', () {
        final history = TransformHistory();
        history.push(createState(translateX: 10));
        history.push(createState(translateX: 20));
        history.undo(createState(translateX: 30));

        history.reset(createState(translateX: 0));

        expect(history.canUndo, isFalse);
        expect(history.canRedo, isFalse);
      });
    });

    group('undoCount', () {
      test('returns 0 when empty', () {
        final history = TransformHistory();
        expect(history.undoCount, equals(0));
      });

      test('returns correct count after pushes', () {
        final history = TransformHistory();
        history.push(createState(translateX: 10));
        history.push(createState(translateX: 20));
        history.push(createState(translateX: 30));

        expect(history.undoCount, equals(3));
      });
    });

    group('redoCount', () {
      test('returns 0 when empty', () {
        final history = TransformHistory();
        expect(history.redoCount, equals(0));
      });

      test('returns correct count after undos', () {
        final history = TransformHistory();
        history.push(createState(translateX: 10));
        history.push(createState(translateX: 20));
        history.push(createState(translateX: 30));

        history.undo(createState(translateX: 40));
        history.undo(createState(translateX: 50));

        expect(history.redoCount, equals(2));
      });
    });

    group('complex undo/redo sequences', () {
      test('multiple undo then redo restores states correctly', () {
        final history = TransformHistory();
        final state1 = createState(translateX: 10);
        final state2 = createState(translateX: 20);
        final state3 = createState(translateX: 30);

        history.push(state1);
        history.push(state2);
        history.push(state3);

        // Undo twice
        final undone1 = history.undo(state3);
        expect(undone1, equals(state3));

        final undone2 = history.undo(state2);
        expect(undone2, equals(state2));

        // Redo twice
        final redone1 = history.redo(state1);
        expect(redone1, equals(state2));

        final redone2 = history.redo(state2);
        expect(redone2, equals(state3));
      });

      test('undo all then redo all', () {
        final history = TransformHistory();
        history.push(createState(translateX: 10));
        history.push(createState(translateX: 20));

        // Undo all
        history.undo(createState(translateX: 30));
        history.undo(createState(translateX: 40));

        expect(history.canUndo, isFalse);
        expect(history.redoCount, equals(2));

        // Redo all
        history.redo(createState(translateX: 0));
        history.redo(createState(translateX: 0));

        expect(history.canRedo, isFalse);
        expect(history.undoCount, equals(2));
      });
    });
  });
}
