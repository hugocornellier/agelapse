import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/stab_update_event.dart';

/// Unit tests for StabUpdateEvent and StabUpdateType.
/// Tests event types, factory constructors, and properties.
void main() {
  group('StabUpdateType Enum', () {
    test('StabUpdateType has photoStabilized value', () {
      expect(StabUpdateType.photoStabilized, isNotNull);
    });

    test('StabUpdateType has stabilizationComplete value', () {
      expect(StabUpdateType.stabilizationComplete, isNotNull);
    });

    test('StabUpdateType has videoComplete value', () {
      expect(StabUpdateType.videoComplete, isNotNull);
    });

    test('StabUpdateType has cancelled value', () {
      expect(StabUpdateType.cancelled, isNotNull);
    });

    test('StabUpdateType has error value', () {
      expect(StabUpdateType.error, isNotNull);
    });

    test('StabUpdateType has 5 values', () {
      expect(StabUpdateType.values.length, 5);
    });

    test('all StabUpdateType values are unique', () {
      final values = StabUpdateType.values;
      final uniqueValues = values.toSet();
      expect(uniqueValues.length, values.length);
    });
  });

  group('StabUpdateEvent.photoStabilized', () {
    test('creates event with photoStabilized type', () {
      final event = StabUpdateEvent.photoStabilized(5);
      expect(event.type, StabUpdateType.photoStabilized);
    });

    test('stores photoIndex correctly', () {
      final event = StabUpdateEvent.photoStabilized(42);
      expect(event.photoIndex, 42);
    });

    test('handles zero photoIndex', () {
      final event = StabUpdateEvent.photoStabilized(0);
      expect(event.photoIndex, 0);
    });

    test('handles large photoIndex', () {
      final event = StabUpdateEvent.photoStabilized(10000);
      expect(event.photoIndex, 10000);
    });

    test('isCompletionEvent is false', () {
      final event = StabUpdateEvent.photoStabilized(1);
      expect(event.isCompletionEvent, isFalse);
    });
  });

  group('StabUpdateEvent.stabilizationComplete', () {
    test('creates event with stabilizationComplete type', () {
      final event = StabUpdateEvent.stabilizationComplete();
      expect(event.type, StabUpdateType.stabilizationComplete);
    });

    test('photoIndex is null', () {
      final event = StabUpdateEvent.stabilizationComplete();
      expect(event.photoIndex, isNull);
    });

    test('isCompletionEvent is true', () {
      final event = StabUpdateEvent.stabilizationComplete();
      expect(event.isCompletionEvent, isTrue);
    });
  });

  group('StabUpdateEvent.videoComplete', () {
    test('creates event with videoComplete type', () {
      final event = StabUpdateEvent.videoComplete();
      expect(event.type, StabUpdateType.videoComplete);
    });

    test('photoIndex is null', () {
      final event = StabUpdateEvent.videoComplete();
      expect(event.photoIndex, isNull);
    });

    test('isCompletionEvent is true', () {
      final event = StabUpdateEvent.videoComplete();
      expect(event.isCompletionEvent, isTrue);
    });
  });

  group('StabUpdateEvent.cancelled', () {
    test('creates event with cancelled type', () {
      final event = StabUpdateEvent.cancelled();
      expect(event.type, StabUpdateType.cancelled);
    });

    test('photoIndex is null', () {
      final event = StabUpdateEvent.cancelled();
      expect(event.photoIndex, isNull);
    });

    test('isCompletionEvent is true', () {
      final event = StabUpdateEvent.cancelled();
      expect(event.isCompletionEvent, isTrue);
    });
  });

  group('StabUpdateEvent.error', () {
    test('creates event with error type', () {
      final event = StabUpdateEvent.error();
      expect(event.type, StabUpdateType.error);
    });

    test('photoIndex is null', () {
      final event = StabUpdateEvent.error();
      expect(event.photoIndex, isNull);
    });

    test('isCompletionEvent is true', () {
      final event = StabUpdateEvent.error();
      expect(event.isCompletionEvent, isTrue);
    });
  });

  group('StabUpdateEvent.isCompletionEvent', () {
    test('photoStabilized is not a completion event', () {
      expect(StabUpdateEvent.photoStabilized(0).isCompletionEvent, isFalse);
    });

    test('stabilizationComplete is a completion event', () {
      expect(StabUpdateEvent.stabilizationComplete().isCompletionEvent, isTrue);
    });

    test('videoComplete is a completion event', () {
      expect(StabUpdateEvent.videoComplete().isCompletionEvent, isTrue);
    });

    test('cancelled is a completion event', () {
      expect(StabUpdateEvent.cancelled().isCompletionEvent, isTrue);
    });

    test('error is a completion event', () {
      expect(StabUpdateEvent.error().isCompletionEvent, isTrue);
    });
  });

  group('StabUpdateEvent.toString', () {
    test('toString for photoStabilized includes type and index', () {
      final event = StabUpdateEvent.photoStabilized(5);
      final str = event.toString();
      expect(str, contains('StabUpdateEvent'));
      expect(str, contains('photoStabilized'));
      expect(str, contains('5'));
    });

    test('toString for stabilizationComplete includes type', () {
      final event = StabUpdateEvent.stabilizationComplete();
      final str = event.toString();
      expect(str, contains('StabUpdateEvent'));
      expect(str, contains('stabilizationComplete'));
    });

    test('toString for videoComplete includes type', () {
      final event = StabUpdateEvent.videoComplete();
      final str = event.toString();
      expect(str, contains('videoComplete'));
    });

    test('toString for cancelled includes type', () {
      final event = StabUpdateEvent.cancelled();
      final str = event.toString();
      expect(str, contains('cancelled'));
    });

    test('toString for error includes type', () {
      final event = StabUpdateEvent.error();
      final str = event.toString();
      expect(str, contains('error'));
    });

    test('toString for events without photoIndex shows null', () {
      final event = StabUpdateEvent.stabilizationComplete();
      final str = event.toString();
      expect(str, contains('null'));
    });
  });

  group('StabUpdateEvent Type Property', () {
    test('type property is accessible', () {
      final event = StabUpdateEvent.photoStabilized(1);
      expect(event.type, isA<StabUpdateType>());
    });

    test('type property matches factory used', () {
      expect(StabUpdateEvent.photoStabilized(0).type,
          StabUpdateType.photoStabilized);
      expect(StabUpdateEvent.stabilizationComplete().type,
          StabUpdateType.stabilizationComplete);
      expect(
          StabUpdateEvent.videoComplete().type, StabUpdateType.videoComplete);
      expect(StabUpdateEvent.cancelled().type, StabUpdateType.cancelled);
      expect(StabUpdateEvent.error().type, StabUpdateType.error);
    });
  });
}
