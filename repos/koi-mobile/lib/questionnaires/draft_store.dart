import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../chat/conversation_service.dart'
    show CryptoContextGetter, MessageCipher;
import 'questionnaire_models.dart';
import 'questionnaire_wire.dart';

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
    this.answerIds = const {},
    this.idempotencyKey,
  });

  final String attemptId;

  /// The assignment's `questionnaire_version_id`; never applied to another.
  final String versionId;

  /// The server revision these answers were based on (the next PATCH's
  /// `expected_revision`).
  final int baseRevision;

  /// Edited here and not yet acknowledged by the server ("Offline – not
  /// synced"). Never claimed to be on another device.
  final bool dirty;
  final Map<String, Answer> answers;

  /// question id → answer id, including questions answered before a
  /// Restart: the same question keeps the same answer id.
  final Map<String, String> answerIds;

  /// Set before the first submit is sent, so a retry after a timeout or a
  /// restart of the app re-uses the SAME key.
  final String? idempotencyKey;
}

/// Local drafts, per uid. The answers and answer ids are encrypted with the
/// account's Client-Side Encryption (CSE) at rest context (same path as
/// check-ins); only ids, revision and flags are plaintext. Drafts are
/// deleted on sign-out, on relationship removal and once an attempt is
/// submitted.
///
/// [enabled] is `kQuestionnaireLocalDrafts` (questionnaire_flags.dart): when
/// false nothing is read or written, only deleted.
///
/// The box format is mobile-private: the web resumes from the SERVER copy
/// written by autosave, never from this box. A MOB-1 draft (older payload
/// format) does not parse and is ignored.
class DraftRepository {
  DraftRepository({
    required this.box,
    required this.cipher,
    required this.cryptoContext,
    this.enabled = true,
  });

  final DraftBox box;
  final MessageCipher cipher;
  final CryptoContextGetter cryptoContext;
  final bool enabled;

  static String keyFor(String uid, String attemptId) => '$uid::$attemptId';

  Future<LocalDraft?> load(String uid, String attemptId) async {
    if (!enabled) return null;
    final raw = box.get(keyFor(uid, attemptId));
    if (raw == null) return null;
    try {
      final j = (jsonDecode(raw) as Map).cast<String, Object?>();
      if (j['uid'] != uid) return null;
      final ctx = await cryptoContext(uid);
      final payload = (jsonDecode(
        await cipher.decrypt(j['payload']! as String, ctx.secret),
      ) as Map).cast<String, Object?>();
      final answers = <String, Answer>{
        for (final a
            in (payload['answers']! as List).map(decodeAnswer).nonNulls)
          a.questionId: a,
      };
      final ids = (payload['answer_ids']! as Map).cast<String, Object?>();
      return LocalDraft(
        attemptId: attemptId,
        versionId: j['version_id']! as String,
        baseRevision: j['base_revision']! as int,
        dirty: j['dirty'] == true,
        idempotencyKey: j['idempotency_key'] as String?,
        answers: answers,
        answerIds: {
          for (final e in ids.entries)
            if (isQuestionnaireId(e.key) && isQuestionnaireId(e.value))
              e.key: e.value! as String,
        },
      );
    } catch (e) {
      debugPrint('[KOI] questionnaire draft unreadable (${e.runtimeType})');
      return null;
    }
  }

  Future<void> save(String uid, LocalDraft d) async {
    if (!enabled) return;
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
            'answers': [for (final a in d.answers.values) encodeAnswer(a)],
            'answer_ids': d.answerIds,
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
