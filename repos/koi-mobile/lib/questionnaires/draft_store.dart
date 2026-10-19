import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../chat/conversation_service.dart'
    show CryptoContextGetter, MessageCipher;
import 'questionnaire_models.dart';

/// Rows of `koi_questionnaire_drafts`: JSON strings keyed `{uid}::{attempt}`.
abstract class DraftBox {
  Iterable<String> get keys;
  String? get(String key);
  Future<void> put(String key, String row);
  Future<void> delete(String key);
}

class HiveDraftBox implements DraftBox {
  HiveDraftBox(this._box);

  static const String boxName = 'koi_questionnaire_drafts';
  final Box<String> _box;

  static Future<HiveDraftBox> open() async =>
      HiveDraftBox(await Hive.openBox<String>(boxName));

  @override
  Iterable<String> get keys => _box.keys.whereType<String>();
  @override
  String? get(String key) => _box.get(key);
  @override
  Future<void> put(String key, String row) => _box.put(key, row);
  @override
  Future<void> delete(String key) => _box.delete(key);
}

class MemoryDraftBox implements DraftBox {
  final Map<String, String> rows = {};

  @override
  Iterable<String> get keys => rows.keys;
  @override
  String? get(String key) => rows[key];
  @override
  Future<void> put(String key, String row) async => rows[key] = row;
  @override
  Future<void> delete(String key) async => rows.remove(key);
}

/// This device's copy of an unfinished attempt.
@immutable
class LocalDraft {
  const LocalDraft({
    required this.attemptId,
    required this.versionId,
    required this.baseRevision,
    required this.dirty,
    required this.answers,
    this.idempotencyKey,
  });

  final String attemptId;

  /// The version these answers belong to; never applied to another.
  final String versionId;

  /// The server revision these answers were based on.
  final int baseRevision;

  /// Edited here and not yet acknowledged by the server ("Offline / Not
  /// synced"). Never claimed to be on another device.
  final bool dirty;
  final Map<String, Answer> answers;

  /// Set before the first submit is sent, so a retry after a timeout or a
  /// restart of the app re-uses the SAME key.
  final String? idempotencyKey;

  LocalDraft copyWith({
    int? baseRevision,
    bool? dirty,
    Map<String, Answer>? answers,
    String? idempotencyKey,
  }) => LocalDraft(
    attemptId: attemptId,
    versionId: versionId,
    baseRevision: baseRevision ?? this.baseRevision,
    dirty: dirty ?? this.dirty,
    answers: answers ?? this.answers,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
  );
}

/// Local drafts, per uid. The answers are encrypted with the account's
/// Client-Side Encryption (CSE) at rest context (same path as check-ins);
/// only ids, revision and flags are plaintext. Drafts are deleted on
/// sign-out, on relationship removal and once an attempt is submitted.
///
/// Cross-device compatibility (MOB-2 note, no behaviour change; the
/// questionnaire realignment to contract v0.5.1 is a later batch):
/// - This device copy never leaves the phone. The web resumes a mobile
///   draft only from the SERVER copy written by autosave, never from this
///   box, so the box format is mobile-private.
/// - Assumption: every saved answer maps 1:1 to a contract v0.5.1 `Answer`
///   (`{question_id, type, value}`): `option_ids` of one id →
///   single_choice / likert / image_single_choice `value`; several →
///   multi_choice / image_multi_choice `value` array; `text` → short_text
///   `value`. yes_no is an option id here but a boolean in the contract,
///   so the realignment must convert it using the pinned version's options.
/// - `base_revision` is the contract's `expected_revision` of the next
///   PATCH; `version_id` must equal the assignment's
///   `questionnaire_version_id` or the draft is ignored (never merged across
///   versions).
/// - The contract freeze says "persistent protected offline caches are
///   disabled in the MVP": keeping this encrypted device draft is an open
///   question deferred with the realignment (decision A, 2026-10-19).
class DraftRepository {
  DraftRepository({
    required this.box,
    required this.cipher,
    required this.cryptoContext,
  });

  final DraftBox box;
  final MessageCipher cipher;
  final CryptoContextGetter cryptoContext;

  static String keyFor(String uid, String attemptId) => '$uid::$attemptId';

  Future<LocalDraft?> load(String uid, String attemptId) async {
    final raw = box.get(keyFor(uid, attemptId));
    if (raw == null) return null;
    try {
      final j = (jsonDecode(raw) as Map).cast<String, Object?>();
      if (j['uid'] != uid) return null;
      final ctx = await cryptoContext(uid);
      final answers = (jsonDecode(
        await cipher.decrypt(j['payload']! as String, ctx.secret),
      ) as Map).cast<String, Object?>();
      return LocalDraft(
        attemptId: attemptId,
        versionId: j['version_id']! as String,
        baseRevision: j['base_revision']! as int,
        dirty: j['dirty'] == true,
        idempotencyKey: j['idempotency_key'] as String?,
        answers: {
          for (final e in answers.entries)
            if (Answer.fromJson(e.value) != null)
              e.key: Answer.fromJson(e.value)!,
        },
      );
    } catch (e) {
      debugPrint('[KOI] questionnaire draft unreadable (${e.runtimeType})');
      return null;
    }
  }

  Future<void> save(String uid, LocalDraft d) async {
    final ctx = await cryptoContext(uid);
    await box.put(
      keyFor(uid, d.attemptId),
      jsonEncode({
        'uid': uid,
        'attempt_id': d.attemptId,
        'version_id': d.versionId,
        'base_revision': d.baseRevision,
        'dirty': d.dirty,
        if (d.idempotencyKey != null) 'idempotency_key': d.idempotencyKey,
        'payload': await cipher.encrypt(
          jsonEncode({
            for (final e in d.answers.entries) e.key: e.value.toJson(),
          }),
          ctx.secret,
          ctx.saltB64,
        ),
      }),
    );
  }

  Future<void> delete(String uid, String attemptId) =>
      box.delete(keyFor(uid, attemptId));

  /// Every draft of [uid] (sign-out, relationship removed).
  Future<void> deleteAllFor(String uid) async {
    for (final k in box.keys.where((k) => k.startsWith('$uid::')).toList()) {
      await box.delete(k);
    }
  }
}
