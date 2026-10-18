import 'checkin_models.dart';

/// MLT-6 time filters. "Last N days" = today and the N − 1 days before it.
enum MoodRange {
  days7('Last 7 days', 7),
  days30('Last 30 days', 30),
  days90('Last 90 days', 90),
  all('All time', null);

  const MoodRange(this.label, this.days);
  final String label;
  final int? days;

  bool includes(String day, DateTime today) {
    final n = days;
    if (n == null) return true;
    final first = DateTime(today.year, today.month, today.day - (n - 1));
    final d = dayOf(day);
    return !d.isBefore(first) &&
        !d.isAfter(DateTime(today.year, today.month, today.day));
  }
}

/// Mornings in [range], optionally only those with [emotion] (MLT-8),
/// oldest first.
List<MorningCheckIn> moodPoints(
  List<MorningCheckIn> mornings, {
  required MoodRange range,
  required DateTime today,
  CheckInEmotion? emotion,
}) => [
  for (final m in mornings)
    if (range.includes(m.day, today) &&
        (emotion == null || m.emotion == emotion))
      m,
]..sort((a, b) => a.day.compareTo(b.day));

/// MLT-7: whole-number percentages per emotion that sum to exactly 100
/// (largest remainder); only emotions that occur. Empty input → {}.
Map<CheckInEmotion, int> emotionShares(List<MorningCheckIn> mornings) {
  if (mornings.isEmpty) return const {};
  final counts = <CheckInEmotion, int>{};
  for (final m in mornings) {
    counts[m.emotion] = (counts[m.emotion] ?? 0) + 1;
  }
  final total = mornings.length;
  final shares = <CheckInEmotion, int>{};
  final remainders = <CheckInEmotion, int>{};
  var used = 0;
  for (final MapEntry(key: e, value: c) in counts.entries) {
    shares[e] = c * 100 ~/ total;
    remainders[e] = c * 100 % total;
    used += shares[e]!;
  }
  final order = counts.keys.toList()
    ..sort((a, b) {
      final r = remainders[b]!.compareTo(remainders[a]!);
      return r != 0 ? r : a.index.compareTo(b.index);
    });
  for (var i = 0; used < 100; i++, used++) {
    final e = order[i % order.length];
    shares[e] = shares[e]! + 1;
  }
  return shares;
}

/// MLT-4: the last 3 check-ins all have mood_rating ≤ 2.
bool showsHeavyCard(List<MorningCheckIn> mornings) {
  if (mornings.length < 3) return false;
  final sorted = [...mornings]..sort((a, b) => a.day.compareTo(b.day));
  return sorted.skip(sorted.length - 3).every((m) => m.mood <= 2);
}

/// Avg Mood tile: mean mood_rating of the last 7 days, null without any.
double? averageMood7(List<MorningCheckIn> mornings, DateTime today) {
  final points = moodPoints(mornings, range: MoodRange.days7, today: today);
  if (points.isEmpty) return null;
  return points.map((m) => m.mood).reduce((a, b) => a + b) / points.length;
}

/// DCW-2 / DCW-3 entry: the morning check-in before 15:00, the evening
/// reflection from 15:00 (device time).
enum CheckInKind {
  morning('morning'),
  evening('evening');

  const CheckInKind(this.id);
  final String id;

  static const int eveningFromHour = 15;

  static CheckInKind at(DateTime t) =>
      t.hour < eveningFromHour ? morning : evening;

  static CheckInKind? fromId(Object? id) {
    for (final k in values) {
      if (k.id == id) return k;
    }
    return null;
  }
}
