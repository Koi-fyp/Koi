import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../chat/conversation_service.dart'
    show CryptoContextGetter, MessageCipher;
import 'checkin_models.dart';
import 'checkin_stats.dart';

/// Rows of `koi_checkins`: JSON strings keyed by id.
abstract class CheckInBox {
  Iterable<String> get values;
  Future<void> put(String id, String row);
  Future<void> delete(String id);
}

/// Like `koi_messages` (HiveMessageStore): a plain `Box<String>` whose
/// sensitive part is already CSE-encrypted.
class HiveCheckInBox implements CheckInBox {
  HiveCheckInBox(this._box);

  static const String boxName = 'koi_checkins';
  final Box<String> _box;

  static Future<HiveCheckInBox> open() async =>
      HiveCheckInBox(await Hive.openBox<String>(boxName));

  @override
  Iterable<String> get values => _box.values;

  @override
  Future<void> put(String id, String row) => _box.put(id, row);

  @override
  Future<void> delete(String id) => _box.delete(id);
}

/// In memory (tests, and until main.dart overrides it).
class MemoryCheckInBox implements CheckInBox {
  final Map<String, String> rows = {};

  @override
  Iterable<String> get values => rows.values;

  @override
  Future<void> put(String id, String row) async => rows[id] = row;

  @override
  Future<void> delete(String id) async => rows.remove(id);
}

/// Saves and reads check-ins, encrypted with the chat messages' path
/// (MessageCipher + the user's crypto context: v1:PBKDF2:salt:nonce:ct).
///
/// Row (plaintext only what the calendar and one-per-day need): `id`,
/// `userId`, `kind`, `day`, `timestamp`, `synced: false`, and `payload` =
/// the encrypted JSON of the ratings / emotion / loneliness score /
/// reflection. One morning and one evening per day: id =
/// `{uid}_{day}_{kind}`, so a redo replaces it. Nothing is queued for
/// Firestore (web has no mood path).
class CheckInRepository {
  CheckInRepository({
    required this.box,
    required this.cipher,
    required this.cryptoContext,
  });

  final CheckInBox box;
  final MessageCipher cipher;
  final CryptoContextGetter cryptoContext;

  static String idFor(String uid, String day, CheckInKind kind) =>
      '${uid}_${day}_${kind.id}';

  Future<void> _put(
    String uid,
    CheckInKind kind,
    String day,
    DateTime timestamp,
    Map<String, Object?> payload,
  ) async {
    final ctx = await cryptoContext(uid);
    final id = idFor(uid, day, kind);
    await box.put(
      id,
      jsonEncode({
        'id': id,
        'userId': uid,
        'kind': kind.id,
        'day': day,
        'timestamp': timestamp.toIso8601String(),
        'synced': false,
        'payload': await cipher.encrypt(
          jsonEncode(payload),
          ctx.secret,
          ctx.saltB64,
        ),
      }),
    );
  }

  /// Validates first: an out-of-range rating throws and nothing is saved.
  Future<MorningCheckIn> saveMorning(
    String uid, {
    required DateTime now,
    required int sleep,
    required int mood,
    required int connection,
    required int energy,
    required CheckInEmotion emotion,
  }) async {
    final m = MorningCheckIn(
      day: dayKey(now),
      timestamp: now,
      sleep: sleep,
      mood: mood,
      connection: connection,
      energy: energy,
      emotion: emotion,
    );
    await saveMorningRecord(uid, m);
    return m;
  }

  Future<void> saveMorningRecord(String uid, MorningCheckIn m) =>
      _put(uid, CheckInKind.morning, m.day, m.timestamp, m.toPayload());

  Future<EveningReflection> saveEvening(
    String uid, {
    required DateTime now,
    required String text,
  }) async {
    final trimmed = text.trim();
    final e = EveningReflection(
      day: dayKey(now),
      timestamp: now,
      text: trimmed.length > EveningReflection.maxLength
          ? trimmed.substring(0, EveningReflection.maxLength)
          : trimmed,
    );
    await _put(uid, CheckInKind.evening, e.day, e.timestamp, e.toPayload());
    return e;
  }

  /// Decrypts every row of [uid]; rows that fail are skipped, never shown.
  Future<CheckInHistory> load(String uid) async {
    final mine = <Map<String, Object?>>[];
    for (final raw in box.values) {
      try {
        final row = (jsonDecode(raw) as Map).cast<String, Object?>();
        if (row['userId'] == uid) mine.add(row);
      } catch (_) {}
    }
    if (mine.isEmpty) return CheckInHistory.empty;
    final ctx = await cryptoContext(uid);
    final mornings = <MorningCheckIn>[];
    final evenings = <EveningReflection>[];
    for (final row in mine) {
      try {
        final day = row['day']! as String;
        final ts = DateTime.parse(row['timestamp']! as String);
        final payload = (jsonDecode(
          await cipher.decrypt(row['payload']! as String, ctx.secret),
        ) as Map).cast<String, Object?>();
        switch (CheckInKind.fromId(row['kind'])) {
          case CheckInKind.morning:
            mornings.add(
              MorningCheckIn.fromPayload(payload, day: day, timestamp: ts),
            );
          case CheckInKind.evening:
            evenings.add(
              EveningReflection.fromPayload(payload, day: day, timestamp: ts),
            );
          case null:
            break;
        }
      } catch (e) {
        debugPrint('KOI: check-in row skipped: ${e.runtimeType}');
      }
    }
    mornings.sort((a, b) => a.day.compareTo(b.day));
    evenings.sort((a, b) => a.day.compareTo(b.day));
    return CheckInHistory(
      mornings: List.unmodifiable(mornings),
      evenings: List.unmodifiable(evenings),
    );
  }

  /// Debug builds only: every check-in of [uid].
  Future<void> clear(String uid) async {
    final ids = <String>[];
    for (final raw in box.values) {
      try {
        final row = (jsonDecode(raw) as Map).cast<String, Object?>();
        if (row['userId'] == uid) ids.add(row['id']! as String);
      } catch (_) {}
    }
    for (final id in ids) {
      await box.delete(id);
    }
  }

  /// Debug builds only: ~20 of the last 30 days, encrypted like real ones.
  Future<void> addSamples(String uid, DateTime now, {Random? random}) async {
    final r = random ?? Random(7);
    for (var i = 29; i >= 0; i--) {
      if (r.nextInt(3) == 0) continue;
      final t = DateTime(now.year, now.month, now.day - i, 9);
      await saveMorningRecord(
        uid,
        MorningCheckIn(
          day: dayKey(t),
          timestamp: t,
          sleep: 1 + r.nextInt(5),
          mood: 1 + r.nextInt(5),
          connection: 1 + r.nextInt(5),
          energy: 1 + r.nextInt(5),
          emotion: CheckInEmotion.values[r.nextInt(5)],
        ),
      );
    }
  }
}
