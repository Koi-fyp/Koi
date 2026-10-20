import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../chat/conversation_service.dart'
    show CryptoContextGetter, MessageCipher;
import 'safety_plan_models.dart';

/// Rows of `koi_safety_plan`: one JSON string per uid, keyed by uid.
abstract class SafetyPlanBox {
  String? get(String uid);
  Iterable<String> get values;
  Future<void> put(String uid, String row);
  Future<void> delete(String uid);
}

/// Like `koi_checkins` (HiveCheckInBox): a plain `Box<String>` whose
/// sensitive part is already CSE-encrypted.
class HiveSafetyPlanBox implements SafetyPlanBox {
  HiveSafetyPlanBox(this._box);

  static const String boxName = 'koi_safety_plan';
  final Box<String> _box;

  static Future<HiveSafetyPlanBox> open() async =>
      HiveSafetyPlanBox(await Hive.openBox<String>(boxName));

  @override
  String? get(String uid) => _box.get(uid);

  @override
  Iterable<String> get values => _box.values;

  @override
  Future<void> put(String uid, String row) => _box.put(uid, row);

  @override
  Future<void> delete(String uid) => _box.delete(uid);
}

/// In memory (tests, and until main.dart overrides it).
class MemorySafetyPlanBox implements SafetyPlanBox {
  final Map<String, String> rows = {};

  @override
  String? get(String uid) => rows[uid];

  @override
  Iterable<String> get values => rows.values;

  @override
  Future<void> put(String uid, String row) async => rows[uid] = row;

  @override
  Future<void> delete(String uid) async => rows.remove(uid);
}

/// Saves and reads the personal safety plan, encrypted with the chat
/// messages' path (MessageCipher + the user's crypto context:
/// v1:PBKDF2:salt:nonce:ct), exactly like check-ins.
///
/// Row: `id` (= uid), `userId`, `updatedAt` and `payload` = the encrypted
/// JSON of every item. Nothing the user wrote is stored in plaintext.
///
/// ON THIS DEVICE ONLY: nothing here is queued for Firestore, sent to the
/// chat / crisis / speech services, the platform backend or the
/// psychologist. This file must never import a network client.
class SafetyPlanRepository {
  SafetyPlanRepository({
    required this.box,
    required this.cipher,
    required this.cryptoContext,
  });

  final SafetyPlanBox box;
  final MessageCipher cipher;
  final CryptoContextGetter cryptoContext;

  static Map<String, Object?>? _row(String? raw) {
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }

  /// True when [uid] has a stored plan row (without decrypting it).
  bool hasRow(String uid) => _row(box.get(uid))?['userId'] == uid;

  /// [uid]'s plan, or null when there is none. A row that cannot be
  /// decrypted is treated as no plan (never shown half-read).
  Future<SafetyPlan?> load(String uid) async {
    final row = _row(box.get(uid));
    if (row == null || row['userId'] != uid) return null;
    try {
      final ctx = await cryptoContext(uid);
      final payload = (jsonDecode(
        await cipher.decrypt(row['payload']! as String, ctx.secret),
      ) as Map).cast<String, Object?>();
      final at = row['updatedAt'];
      return SafetyPlan.fromPayload(
        payload,
        updatedAt: at is String ? DateTime.tryParse(at) : null,
      );
    } catch (e) {
      debugPrint('KOI: safety plan not readable: ${e.runtimeType}');
      return null;
    }
  }

  /// Saves [plan] for [uid]. An empty plan removes the row, so the crisis
  /// screen never offers an empty plan.
  Future<SafetyPlan> save(String uid, SafetyPlan plan, DateTime now) async {
    if (plan.isEmpty) {
      await box.delete(uid);
      return SafetyPlan.empty;
    }
    final ctx = await cryptoContext(uid);
    final saved = plan.withUpdatedAt(now);
    await box.put(
      uid,
      jsonEncode({
        'id': uid,
        'userId': uid,
        'updatedAt': now.toIso8601String(),
        'payload': await cipher.encrypt(
          jsonEncode(saved.toPayload()),
          ctx.secret,
          ctx.saltB64,
        ),
      }),
    );
    return saved;
  }

  Future<void> clear(String uid) => box.delete(uid);

  /// Debug builds only: an obviously fake plan, encrypted like a real one.
  Future<SafetyPlan> fillDemo(String uid, DateTime now) {
    SafetyPlanItem item(String id, String text, [String? phone]) =>
        SafetyPlanItem(id: id, text: text, phone: phone);
    return save(
      uid,
      SafetyPlan(
        items: {
          SafetyPlanSection.warningSigns: [
            item('d1', '[Demo] Not sleeping well for a few nights'),
            item('d2', '[Demo] Staying in my room all day'),
          ],
          SafetyPlanSection.copingAlone: [
            item('d3', '[Demo] Slow breathing for a few minutes'),
            item('d4', '[Demo] A short walk outside'),
          ],
          SafetyPlanSection.distractions: [
            item('d5', '[Demo] Tea at the corner café'),
          ],
          SafetyPlanSection.peopleToAsk: [
            item('d6', '[Demo] A friend', '0300 0000000'),
          ],
          SafetyPlanSection.professionals: [
            item('d7', '[Demo] My clinic', '042 0000000'),
          ],
          SafetyPlanSection.saferSurroundings: [
            item('d8', '[Demo] Spend the evening with family'),
          ],
          SafetyPlanSection.reasons: [
            item('d9', '[Demo] My family'),
            item('d10', '[Demo] Things I still want to see'),
          ],
        },
      ),
      now,
    );
  }

  /// Account linking / claim (CseMigration): re-encrypts [from]'s plan in
  /// [box] for [to] with [encrypt]. Returns (moved, alreadyDone,
  /// unreadable).
  ///
  /// - Same uid (link): [plaintextToMove] returns null when the row already
  ///   opens with the new secret (an earlier run did it).
  /// - Claim: copied only when [to] has no plan of its own (the account's
  ///   plan wins). The source row stays, hidden under the old uid.
  static Future<(int, int, int)> move(
    SafetyPlanBox box, {
    required String from,
    required String to,
    required Future<String?> Function(String payload) plaintextToMove,
    required Future<String> Function(String plaintext) encrypt,
  }) async {
    final row = _row(box.get(from));
    if (row == null || row['userId'] != from) return (0, 0, 0);
    if (from != to && _row(box.get(to))?['userId'] == to) return (0, 1, 0);
    try {
      final plain = await plaintextToMove(row['payload']! as String);
      if (plain == null) return (0, 1, 0);
      await box.put(
        to,
        jsonEncode({
          ...row,
          'id': to,
          'userId': to,
          'payload': await encrypt(plain),
        }),
      );
      return (1, 0, 0);
    } catch (_) {
      return (0, 0, 1);
    }
  }
}
