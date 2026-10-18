import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/core/emotion.dart';
import 'package:koi_mobile/progress/progress_stats.dart';

MessageRecord msg(DateTime t, {String sender = 'user', String id = ''}) =>
    MessageRecord(
      id: id.isEmpty ? '${t.microsecondsSinceEpoch}$sender' : id,
      conversationId: 'u1',
      sender: sender,
      content: 'v1:ENCRYPTED',
      timestamp: t,
      emotion: Emotion.neutral,
      emotionConfidence: 1,
      synced: false,
    );

void main() {
  // Wednesday 14 Oct 2026, 15:00 local.
  final now = DateTime(2026, 10, 14, 15);
  DateTime day(int offset, [int hour = 10]) =>
      DateTime(2026, 10, 14 + offset, hour);

  test('ATC-M0-18 no messages → all zero, empty heatmap rows', () {
    final s = ProgressStats.from(const [], now);
    expect(s.daysActive, 0);
    expect(s.sessions, 0);
    expect(s.currentStreak, 0);
    expect(s.longestStreak, 0);
    expect(s.messagesSent, 0);
    expect(s.heatmap.length, 7);
    expect(
      s.heatmap.every((r) => r.length == 8 && r.every((c) => c == 0)),
      isTrue,
    );
  });

  test('ATC-M0-18 only the user\'s messages count; AI replies are ignored', () {
    final s = ProgressStats.from([
      msg(day(0)),
      msg(day(0, 11), sender: 'ai'),
      msg(day(-1), sender: 'ai'),
    ], now);
    expect(s.messagesSent, 1);
    expect(s.daysActive, 1);
  });

  test('ATC-M0-18 days active / sessions = distinct local days', () {
    final s = ProgressStats.from([
      msg(day(0, 9)),
      msg(day(0, 20)),
      msg(day(-3)),
      msg(day(-10)),
    ], now);
    expect(s.daysActive, 3);
    expect(s.sessions, 3);
  });

  test('ATC-M0-19 current streak ends today', () {
    final s = ProgressStats.from([
      msg(day(0)),
      msg(day(-1)),
      msg(day(-2)),
      msg(day(-4)),
    ], now);
    expect(s.currentStreak, 3);
    expect(s.longestStreak, 3);
  });

  test('ATC-M0-19 no message yet today → streak still counts up to yesterday', () {
    final s = ProgressStats.from([msg(day(-1)), msg(day(-2))], now);
    expect(s.currentStreak, 2);
  });

  test('ATC-M0-19 a gap of a whole day breaks the current streak', () {
    final s = ProgressStats.from([msg(day(-2)), msg(day(-3))], now);
    expect(s.currentStreak, 0);
    expect(s.longestStreak, 2);
  });

  test('ATC-M0-19 longest streak across months', () {
    final s = ProgressStats.from([
      for (var i = 0; i < 9; i++) msg(DateTime(2026, 9, 26 + i, 12)),
      msg(day(0)),
    ], now);
    // 26 Sep … 4 Oct = 9 days.
    expect(s.longestStreak, 9);
    expect(s.currentStreak, 1);
  });

  test('ATC-M0-20 heatmap: rows Mon→Sun, last column = this week, capped at 4', () {
    final s = ProgressStats.from([
      for (var i = 0; i < 6; i++) msg(day(0, 8 + i)), // Wed: 6 messages
      msg(day(-2)), // Mon this week: 1
      msg(day(-7)), // Wed last week: 1
      msg(day(-7 * 7 - 2)), // Mon, oldest column
      msg(day(-7 * 8)), // too old: not shown
    ], now);
    expect(s.heatmap[2][7], 4); // Wed, this week (6 capped to 4)
    expect(s.heatmap[0][7], 1); // Mon, this week
    expect(s.heatmap[2][6], 1); // Wed, last week
    expect(s.heatmap[0][0], 1); // Mon, 7 weeks ago
    expect(s.heatmap[3][7], 0); // Thu this week is in the future
    final total = s.heatmap.expand((r) => r).fold<int>(0, (a, b) => a + b);
    expect(total, 4 + 1 + 1 + 1);
  });

  test('ATC-M0-20 UTC timestamps are bucketed by local day', () {
    final t = DateTime(2026, 10, 13, 23, 30); // local, yesterday
    final s = ProgressStats.from([msg(t.toUtc())], now);
    expect(s.currentStreak, 1);
    expect(s.heatmap[1][7], 1); // Tuesday
  });
}
