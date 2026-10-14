import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// An integration test must not start work on a fixed timer right after
/// launching the app: on a cold CI runner the app can still be starting up
/// when the timer runs out, and those fixed pumps have been a source of
/// flaky failures (see pumpUntilAppReady in integration_test/test_utils.dart).
/// `launchApp` there waits for the app to be ready; this test keeps every
/// suite on it.
void main() {
  test('integration tests launch the app with launchApp, not a fixed pump', () {
    final dir = Directory('integration_test');
    expect(dir.existsSync(), isTrue, reason: 'run from the package root');

    final fixedPump = RegExp(r'^\s*await tester\.pump\(const Duration\(');
    final offenders = <String>[];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('test_utils.dart'));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('app.main()')) continue;
        // The first statement after the launch.
        for (var j = i + 1; j < lines.length && j <= i + 3; j++) {
          final next = lines[j].trim();
          if (next.isEmpty || next.startsWith('//')) continue;
          if (fixedPump.hasMatch(lines[j])) {
            offenders.add('${file.path}:${j + 1}');
          }
          break;
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These launch the app and then wait a fixed time. Replace the two '
          'lines with `await launchApp(tester);` from test_utils.dart:\n'
          '${offenders.join('\n')}',
    );
  });
}
