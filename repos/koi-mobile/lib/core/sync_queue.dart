import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'key_value_store.dart';

/// How the remote writer applies a [SyncItem].
enum SyncOp {
  /// sync.ts: `setDoc(doc(firestore, collection, docId), data, {merge: true})`.
  merge('merge'),

  /// Mobile-only: write users/{uid}.public_crypto_metadata.salt only if
  /// Firestore has none (a transaction). Never overwrites.
  saltCreateOnce('saltCreateOnce');

  const SyncOp(this.wire);
  final String wire;

  static SyncOp fromWire(Object? v) =>
      values.firstWhere((o) => o.wire == v, orElse: () => merge);
}

/// Mirrors `SyncItem` in repos/koi-backend/nextjs_app/src/lib/firestore/sync.ts.
@immutable
class SyncItem {
  const SyncItem({
    required this.collection,
    required this.docId,
    required this.data,
    required this.priority,
    this.timestamp,
    this.op = SyncOp.merge,
    this.timestampFields = const [],
    this.attempts = 0,
    this.retryAfter,
  });

  /// The queued create-once salt write (priority 4, like sync.ts tasks/user).
  factory SyncItem.saltCreateOnce(String uid, String saltB64) => SyncItem(
    collection: 'users',
    docId: uid,
    data: {
      'public_crypto_metadata': {'salt': saltB64},
    },
    priority: 4,
    op: SyncOp.saltCreateOnce,
  );

  final String collection;
  final String docId;

  /// Must be JSON-encodable (it is persisted while queued).
  final Map<String, Object?> data;

  /// sync.ts: 1=crisis, 2=mood, 3=messages, 4=tasks/user
  final int priority;

  /// sync.ts sets this to Date.now() (ms) when an item is queued locally.
  final int? timestamp;

  final SyncOp op;

  /// Top-level keys of [data] that hold ISO-8601 strings while queued and
  /// are written to Firestore as a `Timestamp` (web writes a JS Date).
  final List<String> timestampFields;

  /// `failed-precondition` answers so far (see [maxBackoffAttempts]).
  final int attempts;

  /// Not retried before this time (ms since epoch); null = any time.
  final int? retryAfter;

  /// The uid this item belongs to: the segment after `users/` in its path,
  /// or null when the path is not under users/{uid}.
  String? get ownerUid {
    final segments = [...collection.split('/'), docId];
    return segments.length >= 2 && segments.first == 'users'
        ? segments[1]
        : null;
  }

  SyncItem withTimestamp(int ms) => SyncItem(
    collection: collection,
    docId: docId,
    data: data,
    priority: priority,
    timestamp: ms,
    op: op,
    timestampFields: timestampFields,
    attempts: attempts,
    retryAfter: retryAfter,
  );

  /// One more `failed-precondition`: wait [syncBackoff] before the next try.
  SyncItem backedOff(int nowMs) => SyncItem(
    collection: collection,
    docId: docId,
    data: data,
    priority: priority,
    timestamp: timestamp,
    op: op,
    timestampFields: timestampFields,
    attempts: attempts + 1,
    retryAfter: nowMs + syncBackoff(attempts + 1).inMilliseconds,
  );

  Map<String, Object?> toJson() => {
    'collection': collection,
    'docId': docId,
    'data': data,
    'priority': priority,
    if (timestamp != null) 'timestamp': timestamp,
    if (op != SyncOp.merge) 'op': op.wire,
    if (timestampFields.isNotEmpty) 'timestampFields': timestampFields,
    if (attempts > 0) 'attempts': attempts,
    if (retryAfter != null) 'retryAfter': retryAfter,
  };

  factory SyncItem.fromJson(Map<String, Object?> j) => SyncItem(
    collection: j['collection']! as String,
    docId: j['docId']! as String,
    data: (j['data']! as Map).cast<String, Object?>(),
    priority: j['priority']! as int,
    timestamp: j['timestamp'] as int?,
    op: SyncOp.fromWire(j['op']),
    timestampFields: [
      for (final f in (j['timestampFields'] as List?) ?? const []) f as String,
    ],
    attempts: (j['attempts'] as int?) ?? 0,
    retryAfter: j['retryAfter'] as int?,
  );
}

/// Firestore answers a retry can never fix (live rules 2026-10-20): the
/// item is dropped for good. Its local record stays; only a count and the
/// code are kept ([PersistentSyncQueue.rejectedKey]).
const Set<String> terminalSyncCodes = {'permission-denied', 'invalid-argument'};

/// Retried with [syncBackoff], at most [maxBackoffAttempts] times, then
/// dropped like [terminalSyncCodes].
const String backoffSyncCode = 'failed-precondition';
const int maxBackoffAttempts = 5;

/// Wait after the [attempt]-th `failed-precondition`: 30 s, 1, 2, 4 min.
Duration syncBackoff(int attempt) =>
    Duration(seconds: 30 * (1 << (attempt - 1).clamp(0, 10)));

/// Thrown by a [RemoteWriter] for an item the live rules would deny
/// (core/firestore/live_rules.dart): it is never sent. [reason] is a short
/// code, never data.
class SyncPrecheckFailed implements Exception {
  const SyncPrecheckFailed(this.reason);
  final String reason;
  @override
  String toString() => 'SyncPrecheckFailed($reason)';
}

/// Thrown by [PersistentSyncQueue.writeNow] when the item was dropped for
/// good (see [terminalSyncCodes]). [code] is the [syncFailureReason].
class SyncRejected implements Exception {
  const SyncRejected(this.code);
  final String code;
  @override
  String toString() => 'SyncRejected($code)';
}

enum _FailureKind { retry, backoff, terminal }

_FailureKind _failureKind(Object e) => switch (e) {
  SyncPrecheckFailed() => _FailureKind.terminal,
  FirebaseException(:final code) when terminalSyncCodes.contains(code) =>
    _FailureKind.terminal,
  FirebaseException(code: backoffSyncCode) => _FailureKind.backoff,
  _ => _FailureKind.retry,
};

abstract interface class SyncQueue {
  void enqueue(SyncItem item);
}

/// The remote side of the queue (core/firestore/firestore_remote_writer.dart).
abstract interface class RemoteWriter {
  /// sync.ts isFirestoreReady(). Mobile: Firebase is set up and signed in.
  bool get isReady;

  /// True when [item] is under the signed-in user's users/{uid}. Items for
  /// another uid (e.g. an old debug uid) are kept queued, never written.
  bool owns(SyncItem item);

  /// Applies [item] as its [SyncItem.op] says. Throws on any failure.
  Future<void> write(SyncItem item);
}

/// Used when there is no Firebase config (debug builds only). Nothing is
/// ever ready, so every item stays queued locally, exactly like web when
/// Firestore is not initialised.
class FirestoreNotConnectedWriter implements RemoteWriter {
  const FirestoreNotConnectedWriter();
  @override
  bool get isReady => false;
  @override
  bool owns(SyncItem item) => false;
  @override
  Future<void> write(SyncItem item) =>
      Future.error(StateError('Firestore is not connected'));
}

/// A short, non-sensitive reason for a failed write: the Firebase error code
/// (e.g. `permission-denied` while the rules are not deployed), `timeout`,
/// or the error type. Never the item data.
String syncFailureReason(Object e) => switch (e) {
  FirebaseException(:final code) => code,
  SyncPrecheckFailed(:final reason) => 'precheck-$reason',
  TimeoutException() => 'timeout',
  _ => e.runtimeType.toString(),
};

/// Mirrors sync.ts `syncQueue`: write straight through when Firestore is
/// ready, otherwise (or on failure) persist locally with a timestamp; flush in
/// priority order (1 first) when the device comes back online, keeping
/// whatever still fails.
///
/// Persistence: web uses localStorage key 'koi_sync_queue'; mobile uses the
/// same key in a plain local Hive box. Items only ever hold ENCRYPTED message
/// content (see conversation_service.dart). Never log item data.
class PersistentSyncQueue implements SyncQueue {
  PersistentSyncQueue({
    required this.store,
    required this.remote,
    Stream<bool>? onlineChanges,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch) {
    // window.addEventListener('online', () => void flushQueue())
    _sub = onlineChanges?.where((online) => online).listen((_) => flush());
  }

  static const String boxName = 'koi_sync';
  static const String queueKey = 'koi_sync_queue'; // sync.ts QUEUE_KEY

  final KeyValueStore store;
  final RemoteWriter remote;
  final int Function() _now;
  StreamSubscription<bool>? _sub;

  /// Serialises queue read-modify-write so concurrent enqueues don't race.
  Future<void> _lock = Future.value();

  Future<T> _locked<T>(Future<T> Function() body) {
    final result = _lock.then((_) => body());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  List<SyncItem> _load() {
    try {
      final raw = store.get(queueKey);
      if (raw == null) return [];
      return [
        for (final e in jsonDecode(raw) as List)
          SyncItem.fromJson((e as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      return []; // web: JSON.parse failure → []
    }
  }

  Future<void> _save(List<SyncItem> items) =>
      store.put(queueKey, jsonEncode([for (final i in items) i.toJson()]));

  Future<void> _append(SyncItem item) => _locked(() async {
    final queue = _load()..add(item.withTimestamp(_now()));
    await _save(queue);
  });

  /// Per-code counts of items dropped for good, JSON `{code: count}` under
  /// this key of [store] (diagnostics only: codes, never data).
  static const String rejectedKey = 'koi_sync_rejected';

  Map<String, int> get rejectedCounts {
    try {
      final raw = store.get(rejectedKey);
      if (raw == null) return const {};
      return (jsonDecode(raw) as Map).cast<String, int>();
    } catch (_) {
      return const {};
    }
  }

  Future<void> _countRejected(String code) => store.put(
    rejectedKey,
    jsonEncode(
      {...rejectedCounts}..update(code, (n) => n + 1, ifAbsent: () => 1),
    ),
  );

  /// What a failed write of [item] leaves to queue: the item again (retry
  /// as before), the item backed off (`failed-precondition`), or null when
  /// it is dropped for good and counted (live rules: permission-denied,
  /// invalid-argument, pre-check failures, or the last back-off attempt).
  /// The local record (message store) is never touched.
  Future<SyncItem?> _afterFailure(SyncItem item, Object e) async {
    final kind = _failureKind(e);
    if (kind == _FailureKind.retry) return item;
    if (kind == _FailureKind.backoff &&
        item.attempts + 1 < maxBackoffAttempts) {
      return item.backedOff(_now());
    }
    await _countRejected(syncFailureReason(e));
    return null;
  }

  /// Completes when the item is either written, persisted locally, or
  /// dropped for good (web's enqueue is fire-and-forget; tests await this).
  /// A failure that a retry can fix (offline, timeout) is kept queued.
  Future<void> enqueueAsync(SyncItem item) async {
    if (!remote.isReady || !remote.owns(item)) return _append(item);
    try {
      await remote.write(item);
    } catch (e) {
      final reason = syncFailureReason(e);
      final keep = await _afterFailure(item, e);
      if (keep == null) {
        debugPrint('[KOI] sync: 1 write rejected for good ($reason)');
        return;
      }
      debugPrint('[KOI] sync: write kept queued ($reason)');
      await _append(keep);
    }
  }

  @override
  void enqueue(SyncItem item) => unawaited(enqueueAsync(item));

  /// sync.ts flushQueue(). Priority order (1 first); items of equal priority
  /// keep their queue order, so a later profile merge still lands after an
  /// earlier one. Items for another uid are skipped and kept.
  Future<void> flush() => _locked(() async {
    if (!remote.isReady) return;
    final loaded = _load();
    final order = List<int>.generate(loaded.length, (i) => i)
      ..sort((a, b) {
        final byPriority = loaded[a].priority.compareTo(loaded[b].priority);
        return byPriority != 0 ? byPriority : a.compareTo(b);
      });
    final remaining = <SyncItem>[];
    var failed = 0, rejected = 0;
    String? reason, rejectedReason;
    final now = _now();
    for (final item in [for (final i in order) loaded[i]]) {
      final waiting = item.retryAfter != null && item.retryAfter! > now;
      if (!remote.owns(item) || waiting) {
        remaining.add(item);
        continue;
      }
      try {
        await remote.write(item);
      } catch (e) {
        final keep = await _afterFailure(item, e);
        if (keep == null) {
          rejected++;
          rejectedReason ??= syncFailureReason(e);
        } else {
          failed++;
          reason ??= syncFailureReason(e);
          remaining.add(keep);
        }
      }
    }
    if (failed > 0) {
      debugPrint('[KOI] sync: $failed write(s) kept queued ($reason)');
    }
    if (rejected > 0) {
      debugPrint(
        '[KOI] sync: $rejected write(s) rejected for good ($rejectedReason)',
      );
    }
    await _save(remaining);
  });

  /// MOB-1 migration: writes [item] now and reports whether the server
  /// confirmed it (true). On a failure a retry can fix (or not ready /
  /// another uid) it is kept queued like [enqueueAsync] and false is
  /// returned. Dropped for good → throws [SyncRejected].
  Future<bool> writeNow(SyncItem item) async {
    if (!remote.isReady || !remote.owns(item)) {
      await _append(item);
      return false;
    }
    try {
      await remote.write(item);
      return true;
    } catch (e) {
      final reason = syncFailureReason(e);
      final keep = await _afterFailure(item, e);
      if (keep == null) {
        debugPrint('[KOI] sync: 1 write rejected for good ($reason)');
        throw SyncRejected(reason);
      }
      debugPrint('[KOI] sync: write kept queued ($reason)');
      await _append(keep);
      return false;
    }
  }

  /// MOB-1 migration: drops queued items matching [test] (e.g. an old
  /// ciphertext of a re-encrypted message, so it can never overwrite the
  /// new one), and returns how many were dropped.
  Future<int> removeWhere(bool Function(SyncItem item) test) =>
      _locked(() async {
        final loaded = _load();
        final kept = [
          for (final i in loaded)
            if (!test(i)) i,
        ];
        await _save(kept);
        return loaded.length - kept.length;
      });

  /// sync.ts getPending().
  List<SyncItem> get pending => _load();

  /// sync.ts clearPending().
  Future<void> clearPending() => _locked(() => _save([]));

  Future<void> dispose() async => _sub?.cancel();
}
