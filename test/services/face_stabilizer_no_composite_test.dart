import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Paranoid regression guard for the v2.5.2 transparent-video alpha fix.
///
/// Before this fix, `saveStabilizedImage` composited transparent-project
/// stabilized PNGs onto black, destroying the alpha channel and silently
/// breaking ProRes 4444 / VP9 transparent video export. The fix removes the
/// composite call entirely because `stabilizeCV` already produces the
/// correct channel format (BGRA for transparent, BGR for opaque).
///
/// This test is a line-level guard: if anyone ever reintroduces a
/// `compositeBlackPngBytes` call inside `saveStabilizedImage`, this test
/// fails loudly on every `flutter test` run.
void main() {
  test('saveStabilizedImage does not composite transparent PNGs onto black',
      () {
    final src = File('lib/services/face_stabilizer.dart').readAsStringSync();

    final saveStart =
        src.indexOf('Future<(bool, Uint8List?)> saveStabilizedImage(');
    expect(
      saveStart,
      greaterThanOrEqualTo(0),
      reason:
          'saveStabilizedImage method not found — did the signature change? '
          'Update this regression guard to match.',
    );

    // Match the end of the method body: newline + two-space closing brace.
    final saveEnd = src.indexOf('\n  }\n', saveStart);
    expect(
      saveEnd,
      greaterThan(saveStart),
      reason: 'Could not locate end of saveStabilizedImage body.',
    );

    final saveBody = src.substring(saveStart, saveEnd);

    expect(
      saveBody.contains('compositeBlackPngBytes'),
      isFalse,
      reason: 'REGRESSION: saveStabilizedImage must not call '
          'compositeBlackPngBytes. Compositing a transparent BGRA PNG onto '
          'black destroys the alpha channel, which silently breaks ProRes '
          '4444 / VP9 transparent video export. See v2.5.2 fix for details.',
    );
  });
}
