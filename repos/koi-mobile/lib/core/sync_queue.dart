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
  );

  Map<String, Object?> toJson() => {
    'collection': collection,
    'docId': docId,
    'data': data,
    'priority': priority,
    if (timestamp != null) 'timestamp': timestamp,
    if (op != SyncOp.merge) 'op': op.wire,
    if (timestampFields.isNotEmpty) 'timestampFields': timestampFields,
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
  );
}

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

  /// Completes when the item is either written or persisted locally (web's
  /// enqueue is fire-and-forget; tests await this). A failed write (e.g.
  /// permission-denied while the rules are not deployed) is kept queued.
  Future<void> enqueueAsync(SyncItem item) async {
    if (!remote.isReady || !remote.owns(item)) return _append(item);
    try {
      await remote.write(item);
    } catch (e) {
      debugPrint('[KOI] sync: write kept queued (${syncFailureReason(e)})');
      await _append(item);
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
    var failed = 0;
    String? reason;
    for (final item in [for (final i in order) loaded[i]]) {
      if (!remote.owns(item)) {
        remaining.add(item);
        continue;
      }
      try {
        await remote.write(item);
      } catch (e) {
        failed++;
        reason ??= syncFailureReason(e);
        remaining.add(item);
      }
    }
    if (failed > 0) {
      debugPrint('[KOI] sync: $failed write(s) kept queued ($reason)');
    }
    await _save(remaining);
  });

  /// sync.ts getPending().
  List<SyncItem> get pending => _load();

  /// sync.ts clearPending().
  Future<void> clearPending() => _locked(() => _save([]));

  Future<void> dispose() async => _sub?.cancel();
}
