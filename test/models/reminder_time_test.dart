import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/models/reminder_time.dart';

void main() {
  group('ReminderTime.parse', () {
    test('reads HH:MM', () {
      expect(ReminderTime.parse('17:00'), const ReminderTime(17, 0));
      expect(ReminderTime.parse('00:00'), const ReminderTime(0, 0));
      expect(ReminderTime.parse('23:59'), const ReminderTime(23, 59));
    });

    test('reads a one-digit hour', () {
      expect(ReminderTime.parse('9:05'), const ReminderTime(9, 5));
    });

    test('ignores surrounding whitespace', () {
      expect(ReminderTime.parse(' 08:30 '), const ReminderTime(8, 30));
    });

    test('falls back to 17:00 for out-of-range wall clock values', () {
      expect(ReminderTime.parse('24:00'), ReminderTime.defaultTime);
      expect(ReminderTime.parse('17:60'), ReminderTime.defaultTime);
    });

    test('falls back to 17:00 for the legacy default and garbage', () {
      expect(ReminderTime.parse('not set'), ReminderTime.defaultTime);
      expect(ReminderTime.parse('not_set'), ReminderTime.defaultTime);
      expect(ReminderTime.parse(''), ReminderTime.defaultTime);
      expect(ReminderTime.parse(null), ReminderTime.defaultTime);
      expect(ReminderTime.parse('five pm'), ReminderTime.defaultTime);
      expect(ReminderTime.parse('17:00:00'), ReminderTime.defaultTime);
    });

    test('decodes legacy epoch milliseconds in the local zone', () {
      // "Today at HH:MM" as the old code stored it, in two DST phases.
      final winter = DateTime(2026, 1, 15, 17, 0).millisecondsSinceEpoch;
      final summer = DateTime(2026, 6, 1, 6, 45).millisecondsSinceEpoch;
      expect(ReminderTime.parse('$winter'), const ReminderTime(17, 0));
      expect(ReminderTime.parse('$summer'), const ReminderTime(6, 45));
    });

    test('falls back to 17:00 for an epoch value Dart cannot represent', () {
      expect(ReminderTime.parse('99999999999999999'), ReminderTime.defaultTime);
    });
  });

  group('ReminderTime.encode', () {
    test('zero-pads both fields', () {
      expect(const ReminderTime(7, 5).encode(), '07:05');
      expect(const ReminderTime(17, 0).encode(), '17:00');
    });

    test('round-trips through parse', () {
      for (final time in const [
        ReminderTime(0, 0),
        ReminderTime(9, 30),
        ReminderTime(23, 59),
      ]) {
        expect(ReminderTime.parse(time.encode()), time);
      }
    });
  });

  group('ReminderTime equality', () {
    test('compares by value', () {
      expect(const ReminderTime(17, 0), const ReminderTime(17, 0));
      expect(
        const ReminderTime(17, 0).hashCode,
        const ReminderTime(17, 0).hashCode,
      );
      expect(const ReminderTime(17, 0), isNot(const ReminderTime(17, 1)));
    });

    test('defaultTime is 5 PM', () {
      expect(ReminderTime.defaultTime, const ReminderTime(17, 0));
      expect(ReminderTime.defaultTime.encode(), '17:00');
    });
  });
}
