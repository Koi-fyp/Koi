import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../chat/conversation_service.dart'
    show ConversationService, MessageCipher;
import '../chat/message_record.dart';
import '../checkins/checkin_store.dart';
import '../core/crypto_context.dart';
import '../core/key_value_store.dart';
import '../core/sync_queue.dart';
import '../safety_plan/safety_plan_store.dart';

/// The upload side a migration needs: write now and say whether the server
/// confirmed it, and drop stale queued copies. [PersistentSyncQueue] is it.
abstract interface class MigrationUploader {
  /// true = the server acknowledged the write; false = kept queued.
  /// Throws [SyncRejected] when the server refused it for good.
  Future<bool> writeNow(SyncItem item);

  /// Drops queued items matching [test].
  Future<int> removeWhere(bool Function(SyncItem item) test);
}

class SyncQueueMigrationUploader implements MigrationUploader {
  SyncQueueMigrationUploader(this.queue);
  final PersistentSyncQueue queue;

  @override
  Future<bool> writeNow(SyncItem item) => queue.writeNow(item);

  @override
  Future<int> removeWhere(bool Function(SyncItem item) test) =>
      queue.removeWhere(test);
}

/// Where a migration stands. Stored as JSON under [CseMigration.linkKey] /
/// [CseMigration.claimKey] in the local prefs box, so an interrupted run
/// resumes instead of starting over.
enum MigrationState {
  /// Local records still need re-encrypting: the app waits (KoiLoader).
  pending,

  /// Every local record is re-encrypted; some server copies are not
  /// acknowledged yet. The app runs; the old secret / source rows stay.
  awaitingAck,

  /// Re-encrypted and acknowledged. For a claim the source rows are gone.
  done,

  /// Claim only: the user chose "Leave it". Source rows stay hidden.
  left;

  static MigrationState? fromName(Object? v) =>
      values.where((s) => s.name == v).firstOrNull;
}

@immutable
class MigrationMarker {
  const MigrationMarker({
    required this.state,
    this.source,
    this.acked = const {},
    this.serverStale = const {},
  });

  final MigrationState state;

  /// Claim only: the anonymous uid whose records are brought across.
  final String? source;

  /// Message ids whose new copy the server acknowledged.
  final Set<String> acked;

  /// Message ids whose new copy the server refused for good (live rules:
  /// an existing message can't be changed, so a server copy written before
  /// a link keeps its OLD ciphertext). Never retried. While any exists the
  /// anonymous secret is kept, so that old copy can still be opened.
  final Set<String> serverStale;

  MigrationMarker copyWith({
    MigrationState? state,
    Set<String>? acked,
    Set<String>? serverStale,
  }) => MigrationMarker(
    state: state ?? this.state,
    source: source,
    acked: acked ?? this.acked,
    serverStale: serverStale ?? this.serverStale,
  );

  String encode() => jsonEncode({
    'state': state.name,
    if (source != null) 'source': source,
    'acked': acked.toList()..sort(),
    if (serverStale.isNotEmpty) 'serverStale': serverStale.toList()..sort(),
  });

  static MigrationMarker? decode(String? raw) {
    if (raw == null) return null;
    try {
      final j = (jsonDecode(raw) as Map).cast<String, Object?>();
      final state = MigrationState.fromName(j['state']);
      if (state == null) return null;
      return MigrationMarker(
        state: state,
        source: j['source'] as String?,
        acked: {for (final a in (j['acked'] as List?) ?? const []) a as String},
        serverStale: {
          for (final a in (j['serverStale'] as List?) ?? const []) a as String,
        },
      );
    } catch (_) {
      return null;
    }
  }
}

@immutable
class MigrationReport {
  const MigrationReport({
    required this.state,
    this.reencrypted = 0,
    this.alreadyDone = 0,
    this.unreadable = 0,
    this.uploaded = 0,
    this.serverStale = 0,
  });

  final MigrationState state;

  /// Server copies refused for good, in total ([MigrationMarker.serverStale]).
  final int serverStale;

  /// Records re-encrypted by this run.
  final int reencrypted;

  /// Records a previous (interrupted) run had already finished.
  final int alreadyDone;

  /// Records neither secret could open; left untouched, never shown.
  final int unreadable;

  /// Server copies acknowledged by this run.
  final int uploaded;
}

/// Client-Side Encryption (CSE) at rest, moving records to a new secret
/// (Blueprint §3.1 two-phase secret). Mirrors web crypto.ts
/// reencryptOnLinking(payloads, anonSecret, newSecret, newSalt): each
/// payload is decrypted with the anonymous secret and encrypted again with
/// the new secret and the account's salt. The server only ever receives
/// ciphertext; nothing here assumes it can read a chat.
///
/// Idempotent and resumable:
/// - a record that already opens with the NEW secret is skipped (an earlier
///   run finished it), so ids never change and nothing is encrypted twice;
/// - each acknowledged upload is recorded in the marker and never sent
///   again (no duplicate uploads);
/// - queued writes holding the OLD ciphertext of a migrated message are
///   dropped, so a late flush can never overwrite the new copy;
/// - source records (claim) and the anonymous secret are removed only when
///   every new message copy has been acknowledged by the server.
///
/// Never logs content, secrets or ids.
class CseMigration {
  CseMigration({
    required this.messages,
    required this.checkIns,
    required this.cipher,
    required this.uploader,
    required this.markers,
    this.safetyPlans,
  });

  final MessageStore messages;
  final CheckInBox checkIns;

  /// The on-device safety plan (local only, like check-ins: never uploaded).
  final SafetyPlanBox? safetyPlans;
  final MessageCipher cipher;
  final MigrationUploader uploader;
  final KeyValueStore markers;

  /// The id of [target]'s copy of a claimed message: derived, so every
  /// re-run finds the same copy (no duplicates), and distinct from the
  /// source id, so the source row stays until its copy is acknowledged
  /// (the local stores are keyed by id).
  static String claimedId(String sourceId, String target) =>
      '${sourceId}_$target';

  static String linkKey(String uid) => 'koi_cse_link_$uid';
  static String claimKey(String targetUid) => 'koi_cse_claim_$targetUid';

  MigrationMarker? linkMarker(String uid) =>
      MigrationMarker.decode(markers.get(linkKey(uid)));
  MigrationMarker? claimMarker(String target) =>
      MigrationMarker.decode(markers.get(claimKey(target)));

  /// Marks [uid] as linked-but-not-migrated BEFORE anything else happens,
  /// so a crash right after linking resumes the migration on next start.
  Future<void> beginLink(String uid) async {
    if (linkMarker(uid) == null) {
      await markers.put(
        linkKey(uid),
        const MigrationMarker(state: MigrationState.pending).encode(),
      );
    }
  }

  /// Records that [target] may claim [source]'s records (set right before
  /// signing in to [target] from the anonymous account [source]).
  Future<void> offerClaim({required String source, required String target}) =>
      markers.put(
        claimKey(target),
        MigrationMarker(state: MigrationState.pending, source: source).encode(),
      );

  Future<void> leaveClaim(String target) async {
    final m = claimMarker(target);
    if (m == null) return;
    await markers.put(
      claimKey(target),
      m.copyWith(state: MigrationState.left).encode(),
    );
  }

  /// Opens [payload] with [to] (already migrated → null) or [from]
  /// (returns the plaintext). Throws when neither works.
  Future<String?> _plaintextToMove(
    String payload,
    String from,
    CryptoContext to,
  ) async {
    try {
      await cipher.decrypt(payload, to.secret);
      return null;
    } catch (_) {}
    return cipher.decrypt(payload, from);
  }

  SyncItem _messageItem(String uid, MessageRecord encrypted) => SyncItem(
    collection: ConversationService.messagesCollection(
      uid,
      encrypted.conversationId,
    ),
    docId: encrypted.id,
    data: encrypted.toJson(),
    priority: 3,
    timestampFields: const ['timestamp'],
  );

  /// Link (same uid): every message, check-in and the safety plan of [uid]
  /// moves from the anonymous secret [fromSecret] to [to] (password + the
  /// uid's salt).
  Future<MigrationReport> runLink({
    required String uid,
    required String fromSecret,
    required CryptoContext to,
  }) async {
    var marker =
        linkMarker(uid) ?? const MigrationMarker(state: MigrationState.pending);
    if (marker.state == MigrationState.done) {
      return MigrationReport(
        state: MigrationState.done,
        serverStale: marker.serverStale.length,
      );
    }
    var reencrypted = 0, already = 0, unreadable = 0;

    final rows = await messages.byConversation(uid);
    for (final r in rows) {
      try {
        final plain = await _plaintextToMove(r.content, fromSecret, to);
        if (plain == null) {
          already++;
          continue;
        }
        await messages.put(
          r.copyWith(
            content: await cipher.encrypt(plain, to.secret, to.saltB64),
          ),
        );
        reencrypted++;
      } catch (_) {
        unreadable++;
      }
    }
    final c = await _moveCheckIns(
      from: uid,
      to: uid,
      fromSecret: fromSecret,
      ctx: to,
    );
    reencrypted += c.$1;
    already += c.$2;
    unreadable += c.$3;
    final p = await _moveSafetyPlan(
      from: uid,
      to: uid,
      fromSecret: fromSecret,
      ctx: to,
    );
    reencrypted += p.$1;
    already += p.$2;
    unreadable += p.$3;

    // Old-ciphertext copies of these messages must never be written.
    final ids = {for (final r in rows) r.id};
    final messagesPath = ConversationService.messagesCollection(uid, uid);
    await uploader.removeWhere(
      (i) => i.collection == messagesPath && ids.contains(i.docId),
    );
    marker = marker.copyWith(state: MigrationState.awaitingAck);
    await markers.put(linkKey(uid), marker.encode());

    final uploaded = await _upload(uid, linkKey(uid), marker, ids);
    final after = linkMarker(uid)!;
    final finalState = after.state;
    debugPrint(
      '[KOI] account: link migration ${finalState.name} '
      '($reencrypted new, $already done, $unreadable unreadable)',
    );
    return MigrationReport(
      state: finalState,
      reencrypted: reencrypted,
      alreadyDone: already,
      unreadable: unreadable,
      uploaded: uploaded,
      serverStale: after.serverStale.length,
    );
  }

  /// Claim: [source]'s (anonymous, this device) records are copied to
  /// [target] under [to]. Copies get stable derived ids ([claimedId]), so a
  /// re-run never duplicates.
  /// Source message rows are deleted only after every target copy is
  /// acknowledged. Check-ins have no server path, so their source rows are
  /// never deleted (they stay hidden under the source uid).
  Future<MigrationReport> runClaim({
    required String target,
    required String fromSecret,
    required CryptoContext to,
  }) async {
    var marker = claimMarker(target);
    final source = marker?.source;
    if (marker == null || source == null) {
      throw StateError('No claim was offered for this account');
    }
    if (marker.state == MigrationState.done ||
        marker.state == MigrationState.left) {
      return MigrationReport(state: marker.state);
    }
    var copied = 0, already = 0, unreadable = 0;
    final existing = {
      for (final r in await messages.byConversation(target)) r.id: r,
    };
    final sourceRows = await messages.byConversation(source);
    for (final r in sourceRows) {
      final copyId = claimedId(r.id, target);
      if (existing.containsKey(copyId)) {
        already++;
        continue;
      }
      try {
        final plain = await cipher.decrypt(r.content, fromSecret);
        await messages.put(
          MessageRecord(
            id: copyId,
            conversationId: target,
            sender: r.sender,
            content: await cipher.encrypt(plain, to.secret, to.saltB64),
            timestamp: r.timestamp,
            emotion: r.emotion,
            emotionConfidence: r.emotionConfidence,
            synced: false,
          ),
        );
        copied++;
      } catch (_) {
        unreadable++;
      }
    }
    final c = await _moveCheckIns(
      from: source,
      to: target,
      fromSecret: fromSecret,
      ctx: to,
    );
    copied += c.$1;
    already += c.$2;
    unreadable += c.$3;
    final p = await _moveSafetyPlan(
      from: source,
      to: target,
      fromSecret: fromSecret,
      ctx: to,
    );
    copied += p.$1;
    already += p.$2;
    unreadable += p.$3;

    marker = marker.copyWith(state: MigrationState.awaitingAck);
    await markers.put(claimKey(target), marker.encode());
    // Copies made by an earlier, interrupted run still need their ack.
    final ids = {for (final r in sourceRows) claimedId(r.id, target)};
    final uploaded = await _upload(target, claimKey(target), marker, ids);
    final after = claimMarker(target)!;
    if (after.state == MigrationState.done) {
      // Only rows whose copy the server acknowledged; an unreadable row
      // (no copy) stays.
      for (final r in sourceRows) {
        if (after.acked.contains(claimedId(r.id, target))) {
          await messages.delete(r.id);
        }
      }
    }
    debugPrint(
      '[KOI] account: claim ${after.state.name} '
      '($copied new, $already done, $unreadable unreadable)',
    );
    return MigrationReport(
      state: after.state,
      reencrypted: copied,
      alreadyDone: already,
      unreadable: unreadable,
      uploaded: uploaded,
      serverStale: after.serverStale.length,
    );
  }

  /// Uploads the [uid] copies of [ids] that are not acknowledged (or
  /// refused for good) yet. Marks the migration done when none is left;
  /// refused ids ([MigrationMarker.serverStale]) don't hold it back.
  Future<int> _upload(
    String uid,
    String key,
    MigrationMarker marker,
    Set<String> ids,
  ) async {
    final current = {
      for (final r in await messages.byConversation(uid)) r.id: r,
    };
    final acked = {...marker.acked};
    final stale = {...marker.serverStale};
    var uploaded = 0;
    for (final id in ids) {
      if (acked.contains(id) || stale.contains(id)) continue;
      final record = current[id];
      if (record == null) continue; // unreadable source: nothing to send
      try {
        if (await uploader.writeNow(_messageItem(uid, record))) {
          acked.add(id);
          uploaded++;
        } else {
          continue;
        }
      } on SyncRejected {
        stale.add(id);
      }
      await markers.put(
        key,
        marker.copyWith(acked: acked, serverStale: stale).encode(),
      );
    }
    final pendingIds = ids.where(
      (id) =>
          current.containsKey(id) && !acked.contains(id) && !stale.contains(id),
    );
    final done = pendingIds.isEmpty;
    await markers.put(
      key,
      marker
          .copyWith(
            acked: acked,
            serverStale: stale,
            state: done ? MigrationState.done : MigrationState.awaitingAck,
          )
          .encode(),
    );
    return uploaded;
  }

  /// Re-encrypts (link) or copies (claim, only when the account has none)
  /// the safety plan. Returns (moved, alreadyDone, unreadable).
  Future<(int, int, int)> _moveSafetyPlan({
    required String from,
    required String to,
    required String fromSecret,
    required CryptoContext ctx,
  }) async {
    final box = safetyPlans;
    if (box == null) return (0, 0, 0);
    return SafetyPlanRepository.move(
      box,
      from: from,
      to: to,
      plaintextToMove: (payload) => from == to
          ? _plaintextToMove(payload, fromSecret, ctx)
          : cipher.decrypt(payload, fromSecret),
      encrypt: (plain) => cipher.encrypt(plain, ctx.secret, ctx.saltB64),
    );
  }

  /// Re-encrypts (from == to) or copies (claim) check-in rows. Returns
  /// (moved, alreadyDone, unreadable).
  Future<(int, int, int)> _moveCheckIns({
    required String from,
    required String to,
    required String fromSecret,
    required CryptoContext ctx,
  }) async {
    var moved = 0, already = 0, unreadable = 0;
    final rows = <Map<String, Object?>>[];
    final targetIds = <String>{};
    for (final raw in checkIns.values) {
      try {
        final row = (jsonDecode(raw) as Map).cast<String, Object?>();
        if (row['userId'] == from) rows.add(row);
        if (row['userId'] == to) targetIds.add(row['id']! as String);
      } catch (_) {}
    }
    for (final row in rows) {
      try {
        final payload = row['payload']! as String;
        final id = from == to
            ? row['id']! as String
            : '${to}_${row['day']}_${row['kind']}';
        if (from != to && targetIds.contains(id)) {
          already++; // the account's own check-in for that day wins
          continue;
        }
        final plain = from == to
            ? await _plaintextToMove(payload, fromSecret, ctx)
            : await cipher.decrypt(payload, fromSecret);
        if (plain == null) {
          already++;
          continue;
        }
        await checkIns.put(
          id,
          jsonEncode({
            ...row,
            'id': id,
            'userId': to,
            'payload': await cipher.encrypt(plain, ctx.secret, ctx.saltB64),
          }),
        );
        moved++;
      } catch (_) {
        unreadable++;
      }
    }
    return (moved, already, unreadable);
  }
}
