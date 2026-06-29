import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/ordered_reveal_gate.dart';

/// Unit tests for [OrderedRevealGate].
///
/// The gate turns the stabilizer's out-of-order completion stream into an
/// in-order reveal stream: a photo is only released once every earlier photo in
/// the batch has finished. These tests assert that contract, including the
/// "straggler flush" burst and the no-deadlock guarantee for failed photos.
void main() {
  group('OrderedRevealGate', () {
    test('in-order completion releases each photo immediately', () {
      final gate = OrderedRevealGate(['100', '101', '102']);

      expect(gate.complete('100'), ['100']);
      expect(gate.complete('101'), ['101']);
      expect(gate.complete('102'), ['102']);
      expect(gate.isDrained, isTrue);
    });

    test("user's scenario: 101 finishes before 100, revealed in order", () {
      final gate = OrderedRevealGate(['100', '101']);

      // Day 101 finishes first: held back, nothing revealed yet.
      expect(gate.complete('101'), isEmpty);

      // Day 100 lands: both flush, oldest first.
      expect(gate.complete('100'), ['100', '101']);
      expect(gate.isDrained, isTrue);
    });

    test('a straggling earliest photo flushes the whole buffered run in order',
        () {
      final gate = OrderedRevealGate(['1', '2', '3', '4', '5']);

      // Everything finishes except the earliest, in arbitrary order.
      expect(gate.complete('3'), isEmpty);
      expect(gate.complete('5'), isEmpty);
      expect(gate.complete('2'), isEmpty);
      expect(gate.complete('4'), isEmpty);

      // The earliest finally lands: contiguous prefix flushes ascending.
      expect(gate.complete('1'), ['1', '2', '3', '4', '5']);
      expect(gate.isDrained, isTrue);
    });

    test('partial flush only releases the contiguous ready prefix', () {
      final gate = OrderedRevealGate(['1', '2', '3', '4']);

      expect(gate.complete('2'), isEmpty); // waits on 1
      expect(gate.complete('4'), isEmpty); // waits on 3
      // 1 lands -> 1 and 2 flush, but 3 is still missing so 4 stays buffered.
      expect(gate.complete('1'), ['1', '2']);
      // 3 lands -> 3 and the buffered 4 flush.
      expect(gate.complete('3'), ['3', '4']);
      expect(gate.isDrained, isTrue);
    });

    test('reverse-order completion buffers until the first, then full flush',
        () {
      final gate = OrderedRevealGate(['10', '20', '30']);

      expect(gate.complete('30'), isEmpty);
      expect(gate.complete('20'), isEmpty);
      expect(gate.complete('10'), ['10', '20', '30']);
    });

    test('a failed/no-faces photo still advances the cursor (no deadlock)', () {
      // The gate does not distinguish success from failure: every photo reports
      // exactly once, so completing the "failed" earliest photo must release the
      // photos buffered behind it rather than stalling forever.
      final gate = OrderedRevealGate(['1', '2', '3']);

      expect(gate.complete('2'), isEmpty);
      expect(gate.complete('3'), isEmpty);
      // '1' failed to stabilize but still completes -> buffer flushes.
      expect(gate.complete('1'), ['1', '2', '3']);
    });

    test('duplicate completion of an already-released photo releases nothing',
        () {
      final gate = OrderedRevealGate(['1', '2']);

      expect(gate.complete('1'), ['1']);
      expect(gate.complete('1'), isEmpty); // idempotent, no double reveal
      expect(gate.complete('2'), ['2']);
    });

    test('an unknown timestamp does not break ordering', () {
      final gate = OrderedRevealGate(['1', '2']);

      // A stray timestamp not in the batch releases nothing and does not
      // corrupt the cursor.
      expect(gate.complete('999'), isEmpty);
      expect(gate.complete('1'), ['1']);
      expect(gate.complete('2'), ['2']);
    });

    test('single-photo batch', () {
      final gate = OrderedRevealGate(['42']);
      expect(gate.isDrained, isFalse);
      expect(gate.complete('42'), ['42']);
      expect(gate.isDrained, isTrue);
    });

    test('empty batch is drained immediately', () {
      final gate = OrderedRevealGate(<String>[]);
      expect(gate.isDrained, isTrue);
      expect(gate.complete('1'), isEmpty);
    });

    test('relies on constructor order, not numeric value', () {
      // The gate trusts the caller to pass reveal order; it must not re-sort.
      // Here the batch order is intentionally not ascending, and the gate
      // should release strictly in the given order.
      final gate = OrderedRevealGate(['300', '100', '200']);

      expect(gate.complete('100'), isEmpty); // 100 is second in batch order
      expect(gate.complete('300'), ['300', '100']);
      expect(gate.complete('200'), ['200']);
    });

    test('many photos completing in scrambled order reveal fully in order', () {
      final order = [for (var i = 0; i < 50; i++) '$i'];
      final gate = OrderedRevealGate(order);

      // Complete in a scrambled but deterministic order (seeded Random).
      final scrambled = [...order]..shuffle(Random(42));
      final revealed = <String>[];
      for (final ts in scrambled) {
        revealed.addAll(gate.complete(ts));
      }

      expect(revealed, order); // every photo revealed exactly once, in order
      expect(gate.isDrained, isTrue);
    });
  });
}
