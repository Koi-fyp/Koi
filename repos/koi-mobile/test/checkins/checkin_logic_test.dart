import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_flutter_lib/services/crypto_service.dart';
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/checkins/checkin_models.dart';
import 'package:koi_mobile/checkins/checkin_screen.dart';
import 'package:koi_mobile/checkins/checkin_stats.dart';
import 'package:koi_mobile/checkins/checkin_store.dart';
import 'package:koi_mobile/checkins/mood_dashboard.dart';
import 'package:koi_mobile/core/koi_cryptography.dart';

import '../support/chat_fakes.dart';

MorningCheckIn morning(
  String day, {
  int mood = 3,
  int sleep = 3,
  int connection = 3,
  int energy = 3,
  CheckInEmotion emotion = CheckInEmotion.calm,
}) => MorningCheckIn(
  day: day,
  timestamp: dayOf(day).add(const Duration(hours: 9)),
  sleep: sleep,
  mood: mood,
  connection: connection,
  energy: energy,
  emotion: emotion,
);

/// Every user-facing check-in / dashboard text.
final List<String> allTexts = [
  ...CheckInScreen.questions,
  CheckInTexts.emotion,
  CheckInTexts.scale,
  CheckInTexts.skip,
  CheckInTexts.evening,
  CheckInTexts.eveningHint,
  CheckInTexts.save,
  CheckInTexts.close,
  CheckInTexts.celebrate,
  CheckInTexts.thanks,
  CheckInTexts.markDone,
  CheckInTexts.done,
  CheckInTexts.saveFailed,
  for (final n in [1, 2, 30]) CheckInTexts.daysCount(n),
  for (final a in CheckInActivity.values) a.text,
  MoodTexts.title,
  MoodTexts.empty,
  MoodTexts.emptyFiltered,
  MoodTexts.emotions,
  MoodTexts.heavy,
  MoodTexts.talk,
  MoodTexts.breathe,
  MoodTexts.checkInTitle,
  MoodTexts.morningPrompt,
  MoodTexts.startMorning,
  MoodTexts.eveningTitle,
  MoodTexts.eveningPrompt,
  MoodTexts.startEvening,
  MoodTexts.calendar,
  for (final r in MoodRange.values) r.label,
];

void main() {
  test('ATC-M7-01 loneliness score: 3/3/3 → 36', () {
    expect(lonelinessScore(mood: 3, connection: 3, energy: 3), 36);
    expect(morning('2026-10-19').loneliness, 36);
  });

  test('ATC-M7-02 loneliness score range: all 5 → 12, all 1 → 60', () {
    expect(lonelinessScore(mood: 5, connection: 5, energy: 5), 12);
    expect(lonelinessScore(mood: 1, connection: 1, energy: 1), 60);
  });

  test(
    'ATC-M7-03 a rating of 0 or 6 is rejected and nothing is saved',
    () async {
      final box = MemoryCheckInBox();
      final repo = CheckInRepository(
        box: box,
        cipher: FakeCipher(),
        cryptoContext: (_) async => testCryptoContext,
      );
      for (final bad in [0, 6]) {
        for (final field in ['sleep', 'mood', 'connection', 'energy']) {
          await expectLater(
            repo.saveMorning(
              'u1',
              now: DateTime(2026, 10, 19, 9),
              sleep: field == 'sleep' ? bad : 3,
              mood: field == 'mood' ? bad : 3,
              connection: field == 'connection' ? bad : 3,
              energy: field == 'energy' ? bad : 3,
              emotion: CheckInEmotion.calm,
            ),
            throwsA(isA<InvalidRatingException>()),
            reason: '$field = $bad',
          );
        }
      }
      expect(box.rows, isEmpty);
      expect(
        () => lonelinessScore(mood: 0, connection: 3, energy: 3),
        throwsA(isA<InvalidRatingException>()),
      );
    },
  );

  group('real KoiCryptoService (same path as chat messages)', () {
    final original = Cryptography.instance;
    setUpAll(() => KoiCryptography.install(useNative: false));
    tearDownAll(() {
      Cryptography.instance = original;
      CachingPbkdf2.clear();
    });

    test(
      'ATC-M7-04 the saved record is encrypted and decrypts to the same values',
      () async {
        final box = MemoryCheckInBox();
        final cipher = KoiMessageCipher(KoiCryptoService());
        final repo = CheckInRepository(
          box: box,
          cipher: cipher,
          cryptoContext: (_) async => testCryptoContext,
        );
        final saved = await repo.saveMorning(
          'u1',
          now: DateTime(2026, 10, 19, 9, 30),
          sleep: 2,
          mood: 4,
          connection: 1,
          energy: 5,
          emotion: CheckInEmotion.anxious,
        );
        final raw = box.rows.values.single;
        final row = (jsonDecode(raw) as Map).cast<String, Object?>();
        expect(row.keys.toSet(), {
          'id',
          'userId',
          'kind',
          'day',
          'timestamp',
          'synced',
          'payload',
        });
        expect(row['payload'], startsWith('v1:PBKDF2:'));
        for (final secret in [
          'mood_rating',
          'sleep_rating',
          'connection_rating',
          'energy_rating',
          'loneliness_score',
          'anxious',
          'emotion',
        ]) {
          expect(raw, isNot(contains(secret)), reason: secret);
        }
        final payload = jsonDecode(
          await cipher.decrypt(
            row['payload']! as String,
            testCryptoContext.secret,
          ),
        );
        expect(payload, {
          'sleep_rating': 2,
          'mood_rating': 4,
          'connection_rating': 1,
          'energy_rating': 5,
          'loneliness_score': saved.loneliness,
          'emotion': 'anxious',
          'activity_done': null,
        });
        final back = (await repo.load('u1')).mornings.single;
        expect(
          (back.sleep, back.mood, back.connection, back.energy, back.emotion),
          (2, 4, 1, 5, CheckInEmotion.anxious),
        );
        expect(back.loneliness, (6 - 4) * 4 + (6 - 1) * 4 + (6 - 5) * 4);
        expect(await repo.load('u2'), same(CheckInHistory.empty));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'ATC-M7-07 evening reflection saved encrypted; empty is allowed',
      () async {
        final box = MemoryCheckInBox();
        final cipher = KoiMessageCipher(KoiCryptoService());
        final repo = CheckInRepository(
          box: box,
          cipher: cipher,
          cryptoContext: (_) async => testCryptoContext,
        );
        await repo.saveEvening(
          'u1',
          now: DateTime(2026, 10, 18, 20),
          text: 'Tea with my sister',
        );
        await repo.saveEvening('u1', now: DateTime(2026, 10, 19, 21), text: '');
        expect(box.rows, hasLength(2));
        for (final raw in box.rows.values) {
          expect(raw, isNot(contains('sister')));
          expect(raw, isNot(contains('reflection')));
          expect((jsonDecode(raw) as Map)['payload'], startsWith('v1:PBKDF2:'));
        }
        final evenings = (await repo.load('u1')).evenings;
        expect(evenings.map((e) => e.text), ['Tea with my sister', '']);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  test('ATC-M7-08 energy 1 → rest / self-care', () {
    final s = suggestActivities(energy: 1, connection: 4);
    expect(s, [CheckInActivity.rest, CheckInActivity.selfCare]);
    expect(morning('2026-10-19', energy: 1).suggestions, s);
  });

  test('ATC-M7-09 connection 1 → a small social step; never more than 2', () {
    expect(
      suggestActivities(energy: 4, connection: 1),
      contains(CheckInActivity.social),
    );
    final both = suggestActivities(energy: 1, connection: 1);
    expect(both, [CheckInActivity.social, CheckInActivity.rest]);
    for (var e = 1; e <= 5; e++) {
      for (var c = 1; c <= 5; c++) {
        final s = suggestActivities(energy: e, connection: c);
        expect(s.length, inInclusiveRange(1, 2));
      }
    }
  });

  test('ATC-M7-10 no suggestion or text contains should / must / have to', () {
    final banned = RegExp(
      r'\b(should|must|have to|need to)\b',
      caseSensitive: false,
    );
    for (final t in allTexts) {
      expect(banned.hasMatch(t), isFalse, reason: t);
    }
    for (final a in CheckInActivity.values) {
      expect(
        a.text.startsWith('You might enjoy') ||
            a.text.startsWith('Some people find'),
        isTrue,
        reason: a.text,
      );
    }
  });

  test('ATC-M7-11 no missed / broken / streak / negative markers', () {
    final banned = RegExp(
      r'missed|broken|streak|failed|behind|lost|only \d|didn.t|forgot|❌|⚠',
      caseSensitive: false,
    );
    for (final t in allTexts) {
      expect(banned.hasMatch(t), isFalse, reason: t);
    }
  });

  test('ATC-M7-13 14:59 → morning, 15:00 → evening', () {
    expect(
      CheckInKind.at(DateTime(2026, 10, 19, 14, 59, 59)),
      CheckInKind.morning,
    );
    expect(CheckInKind.at(DateTime(2026, 10, 19, 15)), CheckInKind.evening);
    expect(CheckInKind.at(DateTime(2026, 10, 19)), CheckInKind.morning);
    expect(CheckInKind.at(DateTime(2026, 10, 19, 23, 59)), CheckInKind.evening);
  });

  test('ATC-M11-01 Last 7 days includes day 7, excludes day 8', () {
    final today = DateTime(2026, 10, 19, 18);
    final list = [
      morning('2026-10-11'), // day 9
      morning('2026-10-12'), // day 8
      morning('2026-10-13'), // day 7
      morning('2026-10-19'), // day 1 (today)
    ];
    final days = moodPoints(
      list,
      range: MoodRange.days7,
      today: today,
    ).map((m) => m.day).toList();
    expect(days, ['2026-10-13', '2026-10-19']);
    expect(MoodRange.days30.includes('2026-09-20', today), isTrue);
    expect(MoodRange.days30.includes('2026-09-19', today), isFalse);
    expect(MoodRange.days90.includes('2026-07-22', today), isTrue);
    expect(MoodRange.days90.includes('2026-07-21', today), isFalse);
    expect(moodPoints(list, range: MoodRange.all, today: today), hasLength(4));
  });

  test('ATC-M11-02 the emotion pie sums to 100', () {
    final days = List.generate(7, (i) => '2026-10-${(10 + i)}');
    for (final mix in [
      [CheckInEmotion.happy, CheckInEmotion.sad, CheckInEmotion.calm],
      [
        CheckInEmotion.happy,
        CheckInEmotion.happy,
        CheckInEmotion.sad,
        CheckInEmotion.anxious,
        CheckInEmotion.calm,
        CheckInEmotion.neutral,
        CheckInEmotion.neutral,
      ],
      [CheckInEmotion.calm],
    ]) {
      final shares = emotionShares([
        for (var i = 0; i < mix.length; i++) morning(days[i], emotion: mix[i]),
      ]);
      expect(shares.values.reduce((a, b) => a + b), 100, reason: '$mix');
      expect(shares.keys.toSet(), mix.toSet());
    }
    expect(emotionShares(const []), isEmpty);
  });

  test('ATC-M11-03 the emotion filter keeps only that emotion', () {
    final today = DateTime(2026, 10, 19, 10);
    final list = [
      morning('2026-10-15', emotion: CheckInEmotion.sad, mood: 2),
      morning('2026-10-16', emotion: CheckInEmotion.happy, mood: 5),
      morning('2026-10-17', emotion: CheckInEmotion.sad, mood: 1),
    ];
    final sad = moodPoints(
      list,
      range: MoodRange.days7,
      today: today,
      emotion: CheckInEmotion.sad,
    );
    expect(sad.map((m) => m.day), ['2026-10-15', '2026-10-17']);
    expect(
      moodPoints(
        list,
        range: MoodRange.days7,
        today: today,
        emotion: CheckInEmotion.calm,
      ),
      isEmpty,
    );
  });

  test(
    'ATC-M11-04 heavy card: last 3 low → shown; 2 low → not; last = 3 → not',
    () {
      List<MorningCheckIn> moods(List<int> m) => [
        for (var i = 0; i < m.length; i++) morning('2026-10-1$i', mood: m[i]),
      ];
      expect(showsHeavyCard(moods([5, 2, 1, 2])), isTrue);
      expect(showsHeavyCard(moods([1, 2])), isFalse);
      expect(showsHeavyCard(moods([4, 2, 2])), isFalse);
      expect(showsHeavyCard(moods([1, 1, 3])), isFalse);
      expect(showsHeavyCard(moods([2, 1, 2, 3])), isFalse);
    },
  );

  test('ATC-M11-05 Avg Mood: last 7 days of real check-ins, none → null', () {
    final today = DateTime(2026, 10, 19, 10);
    expect(averageMood7(const [], today), isNull);
    expect(averageMood7([morning('2026-10-01', mood: 5)], today), isNull);
    expect(
      averageMood7([
        morning('2026-10-12', mood: 1), // day 8: out
        morning('2026-10-13', mood: 4),
        morning('2026-10-19', mood: 3),
      ], today),
      3.5,
    );
  });

  test('ATC-M7-14 the debug tools default to kDebugMode (off in release '
      'builds; tests run in debug, so the default is checked in source)', () {
    final src = File('lib/checkins/checkin_providers.dart').readAsStringSync();
    expect(
      src,
      contains(
        'final checkInDebugToolsProvider = Provider<bool>((ref) => kDebugMode);',
      ),
    );
  });
}
