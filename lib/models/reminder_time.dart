/// The wall-clock time of a project's daily reminder.
///
/// Stored in the `daily_notification_time` project setting as `HH:MM`.
/// Installs before 2.8.0 stored the epoch milliseconds of "today at HH:MM"
/// in the device's zone at the time. Those still decode to the same HH:MM
/// (Dart applies the offset that was in force at that instant, so a DST
/// change does not move them) and are rewritten as `HH:MM` the next time the
/// user picks a time. Anything unreadable, including the `not set` default,
/// means [defaultTime].
class ReminderTime {
  const ReminderTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  final int hour;
  final int minute;

  /// 5 PM, the reminder every new project starts with.
  static const ReminderTime defaultTime = ReminderTime(17, 0);

  static final RegExp _wallClock = RegExp(r'^(\d{1,2}):(\d{2})$');

  /// Parses a stored value. Never throws; see the class doc for the formats.
  static ReminderTime parse(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return defaultTime;

    final match = _wallClock.firstMatch(value);
    if (match != null) {
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      if (hour < 24 && minute < 60) return ReminderTime(hour, minute);
      return defaultTime;
    }

    final epochMs = int.tryParse(value);
    if (epochMs != null) {
      try {
        final local = DateTime.fromMillisecondsSinceEpoch(epochMs);
        return ReminderTime(local.hour, local.minute);
      } on ArgumentError {
        return defaultTime;
      }
    }

    return defaultTime;
  }

  /// The stored form, `HH:MM`.
  String encode() => '${_two(hour)}:${_two(minute)}';

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => 'ReminderTime(${encode()})';
}
