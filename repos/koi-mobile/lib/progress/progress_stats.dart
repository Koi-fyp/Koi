import 'package:flutter/foundation.dart';

import '../chat/message_record.dart';

/// Real numbers for the Progress page, from the local chat history
/// (decision 2026-10-14). Web's progress/page.tsx hard-codes every value;
/// see WEB_BUGS_FOUND_DURING_MOBILE.md.
///
/// Only the user's own messages count (`sender == 'user'`). Days are local
/// calendar days. Timestamps are stored unencrypted next to the encrypted
/// `content`, so nothing is decrypted here.
@immutable
class ProgressStats {
  const ProgressStats({
    required this.daysActive,
    required this.currentStreak,
    required this.longestStreak,
    required this.heatmap,
    required this.messagesSent,
  });

  /// Distinct days with at least one message from the user.
  final int daysActive;

  /// "Total Sessions": one session per active day (decision 2026-10-14).
  int get sessions => daysActive;

  /// Consecutive active days ending today, or ending yesterday when the
  /// user has not chatted yet today.
  final int currentStreak;
  final int longestStreak;

  /// 7 rows (Mon→Sun) × 8 columns (oldest→newest week; the last column is
  /// the current week). Each cell is the user's message count that day,
  /// capped at [maxIntensity] (web's intensity 0–4). Days after today are 0.
  final List<List<int>> heatmap;

  final int messagesSent;

  static const int weeks = 8;
  static const int maxIntensity = 4;

  static const ProgressStats empty = ProgressStats(
    daysActive: 0,
    currentStreak: 0,
    longestStreak: 0,
    heatmap: [],
    messagesSent: 0,
  );

  factory ProgressStats.from(Iterable<MessageRecord> records, DateTime now) {
    final perDay = <DateTime, int>{};
    var sent = 0;
    for (final r in records) {
      if (r.sender != 'user') continue;
      sent++;
      final d = _day(r.timestamp.toLocal());
      perDay[d] = (perDay[d] ?? 0) + 1;
    }

    final today = _day(now);
    final days = perDay.keys.toList()..sort();

    var longest = 0;
    var run = 0;
    DateTime? prev;
    for (final d in days) {
      run = (prev != null && _addDays(prev, 1) == d) ? run + 1 : 1;
      if (run > longest) longest = run;
      prev = d;
    }

    var current = 0;
    var cursor = perDay.containsKey(today) ? today : _addDays(today, -1);
    while (perDay.containsKey(cursor)) {
      current++;
      cursor = _addDays(cursor, -1);
    }

    // Monday of the oldest week shown.
    final thisMonday = _addDays(today, -(today.weekday - DateTime.monday));
    final firstMonday = _addDays(thisMonday, -7 * (weeks - 1));
    final heatmap = [
      for (var row = 0; row < 7; row++)
        [
          for (var col = 0; col < weeks; col++)
            _cap(perDay[_addDays(firstMonday, col * 7 + row)] ?? 0),
        ],
    ];

    return ProgressStats(
      daysActive: perDay.length,
      currentStreak: current,
      longestStreak: longest,
      heatmap: heatmap,
      messagesSent: sent,
    );
  }

  static int _cap(int n) => n > maxIntensity ? maxIntensity : n;

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  /// Calendar arithmetic (safe across DST changes, unlike adding hours).
  static DateTime _addDays(DateTime d, int n) =>
      DateTime(d.year, d.month, d.day + n);
}
