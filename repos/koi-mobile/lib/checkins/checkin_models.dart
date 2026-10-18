import 'package:flutter/foundation.dart';

/// Daily check-ins (Prompt 28, SDS M7 DCW-2/3/9). Local only: web declares
/// `MoodEntryRecord` (lib/db.ts) but never writes it and has no Firestore
/// path for mood, so nothing here is synced.

/// The one-chip emotion of a morning check-in, with its calendar emoji.
enum CheckInEmotion {
  happy('happy', 'Happy', '😊'),
  sad('sad', 'Sad', '😢'),
  anxious('anxious', 'Anxious', '😟'),
  calm('calm', 'Calm', '😌'),
  neutral('neutral', 'Neutral', '😐');

  const CheckInEmotion(this.id, this.label, this.emoji);
  final String id;
  final String label;
  final String emoji;

  static CheckInEmotion? fromId(Object? id) {
    for (final e in values) {
      if (e.id == id) return e;
    }
    return null;
  }
}

/// A 1–5 rating; anything else is rejected before saving.
class InvalidRatingException implements Exception {
  const InvalidRatingException(this.field, this.value);
  final String field;
  final Object? value;

  @override
  String toString() => 'InvalidRatingException($field: $value)';
}

int _rating(String field, Object? v) {
  if (v is int && v >= 1 && v <= 5) return v;
  throw InvalidRatingException(field, v);
}

/// DCW-9: (6 − mood)×4 + (6 − connection)×4 + (6 − energy)×4.
///
/// With 1–5 ratings the real range is 12 (all 5) to 60 (all 1); SDS M7 says
/// 0–60, which these inputs cannot reach. Never shown on the check-in
/// screen.
int lonelinessScore({
  required int mood,
  required int connection,
  required int energy,
}) =>
    (6 - _rating('mood_rating', mood)) * 4 +
    (6 - _rating('connection_rating', connection)) * 4 +
    (6 - _rating('energy_rating', energy)) * 4;

/// The small activities (DCW-4/5/6), fixed list, gentle wording only.
enum CheckInActivity {
  rest('rest', 'You might enjoy a short rest or an early night.'),
  selfCare(
    'self-care',
    'Some people find it helpful to have a glass of water and a few slow '
        'breaths.',
  ),
  social(
    'social',
    'You might enjoy sending a short message to someone you like.',
  ),
  movement('movement', 'Some people find a 5-minute walk helpful.'),
  creative('creative', 'You might enjoy doodling or writing a few lines.');

  const CheckInActivity(this.id, this.text);
  final String id;
  final String text;

  static CheckInActivity? fromId(Object? id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// 1–2 suggestions from today's answers: low connection (≤2) → a small
/// social step; low energy (≤2) → rest, then self-care; otherwise movement
/// and creative.
List<CheckInActivity> suggestActivities({
  required int energy,
  required int connection,
}) {
  final out = <CheckInActivity>[
    if (connection <= 2) CheckInActivity.social,
    if (energy <= 2) ...[CheckInActivity.rest, CheckInActivity.selfCare],
  ];
  if (out.isEmpty) {
    out.addAll([CheckInActivity.movement, CheckInActivity.creative]);
  }
  return out.take(2).toList(growable: false);
}

/// The local calendar day, `yyyy-MM-dd`.
String dayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

DateTime dayOf(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Morning check-in (DCW-2), decrypted. Field names inside the encrypted
/// payload follow web's `MoodEntryRecord` (mood_rating, connection_rating,
/// energy_rating, loneliness_score) plus sleep_rating, emotion and
/// activity_done.
@immutable
class MorningCheckIn {
  MorningCheckIn({
    required this.day,
    required this.timestamp,
    required int sleep,
    required int mood,
    required int connection,
    required int energy,
    required this.emotion,
    this.activityDone,
  }) : sleep = _rating('sleep_rating', sleep),
       mood = _rating('mood_rating', mood),
       connection = _rating('connection_rating', connection),
       energy = _rating('energy_rating', energy);

  /// `yyyy-MM-dd`, local.
  final String day;
  final DateTime timestamp;
  final int sleep;
  final int mood;
  final int connection;
  final int energy;
  final CheckInEmotion emotion;
  final CheckInActivity? activityDone;

  int get loneliness =>
      lonelinessScore(mood: mood, connection: connection, energy: energy);

  List<CheckInActivity> get suggestions =>
      suggestActivities(energy: energy, connection: connection);

  MorningCheckIn withActivityDone(CheckInActivity a) => MorningCheckIn(
    day: day,
    timestamp: timestamp,
    sleep: sleep,
    mood: mood,
    connection: connection,
    energy: energy,
    emotion: emotion,
    activityDone: a,
  );

  Map<String, Object?> toPayload() => {
    'sleep_rating': sleep,
    'mood_rating': mood,
    'connection_rating': connection,
    'energy_rating': energy,
    'loneliness_score': loneliness,
    'emotion': emotion.id,
    'activity_done': activityDone?.id,
  };

  static MorningCheckIn fromPayload(
    Map<String, Object?> p, {
    required String day,
    required DateTime timestamp,
  }) {
    final emotion = CheckInEmotion.fromId(p['emotion']);
    if (emotion == null) throw FormatException('emotion ${p['emotion']}');
    return MorningCheckIn(
      day: day,
      timestamp: timestamp,
      sleep: p['sleep_rating'] as int,
      mood: p['mood_rating'] as int,
      connection: p['connection_rating'] as int,
      energy: p['energy_rating'] as int,
      emotion: emotion,
      activityDone: CheckInActivity.fromId(p['activity_done']),
    );
  }
}

/// Evening reflection (DCW-3), decrypted; [text] may be empty.
@immutable
class EveningReflection {
  const EveningReflection({
    required this.day,
    required this.timestamp,
    required this.text,
  });

  static const int maxLength = 280;

  final String day;
  final DateTime timestamp;
  final String text;

  Map<String, Object?> toPayload() => {'reflection': text};

  static EveningReflection fromPayload(
    Map<String, Object?> p, {
    required String day,
    required DateTime timestamp,
  }) => EveningReflection(
    day: day,
    timestamp: timestamp,
    text: (p['reflection'] as String?) ?? '',
  );
}

/// Everything one user has checked in, oldest first.
@immutable
class CheckInHistory {
  const CheckInHistory({this.mornings = const [], this.evenings = const []});

  static const CheckInHistory empty = CheckInHistory();

  final List<MorningCheckIn> mornings;
  final List<EveningReflection> evenings;

  MorningCheckIn? morningOn(String day) {
    for (final m in mornings) {
      if (m.day == day) return m;
    }
    return null;
  }

  EveningReflection? eveningOn(String day) {
    for (final e in evenings) {
      if (e.day == day) return e;
    }
    return null;
  }

  /// Days with any check-in (celebration count; never streaks).
  int get daysCheckedIn =>
      {...mornings.map((m) => m.day), ...evenings.map((e) => e.day)}.length;
}
