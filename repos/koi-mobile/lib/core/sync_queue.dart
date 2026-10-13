import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'key_value_store.dart';

/// Mirrors `SyncItem` in repos/koi-backend/nextjs_app/src/lib/firestore/sync.ts.
@immutable
class SyncItem {
  const SyncItem({
    required this.collection,
    required this.docId,
    required this.data,
    required this.priority,
    this.timestamp,
  });

  final String collection;
  final String docId;

  /// Must be JSON-encodable (it is persisted while queued).
  final Map<String, Object?> data;

  /// sync.ts: 1=crisis, 2=mood, 3=messages, 4=tasks/user
  final int priority;

  /// sync.ts sets this to Date.now() (ms) when an item is queued locally.
  final int? timestamp;

  SyncItem withTimestamp(int ms) => SyncItem(
    collection: collection,
    docId: docId,
    data: data,
    priority: priority,
    timestamp: ms,
  );

  Map<String, Object?> toJson() => {
    'collection': collection,
    'docId': docId,
    'data': data,
    'priority': priority,
    if (timestamp != null) 'timestamp': timestamp,
  };

  factory SyncItem.fromJson(Map<String, Object?> j) => SyncItem(
    collection: j['collection']! as String,
    docId: j['docId']! as String,
    data: (j['data']! as Map).cast<String, Object?>(),
    priority: j['priority']! as int,
    timestamp: j['timestamp'] as int?,
  );
}

abstract interface class SyncQueue {
  void enqueue(SyncItem item);
}

/// The remote side of the queue: `setDoc(doc(firestore, collection, docId),
/// data, { merge: true })`.
abstract interface class RemoteWriter {
  /// sync.ts isFirestoreReady().
  bool get isReady;

  Future<void> setMerge(
    String collection,
    String docId,
    Map<String, Object?> data,
  );
}

/// TODO(firebase): replace with a cloud_firestore writer once
/// google-services.json exists. Until then nothing is ever ready, so every
/// item stays queued locally, exactly like web when Firestore is not
/// initialised.
class FirestoreNotConnectedWriter implements RemoteWriter {
  const FirestoreNotConnectedWriter();
  @override
  bool get isReady => false;
  @override
  Future<void> setMerge(String c, String d, Map<String, Object?> data) =>
      Future.error(StateError('Firestore is not connected yet'));
}

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
  /// enqueue is fire-and-forget; tests await this).
  Future<void> enqueueAsync(SyncItem item) async {
    if (!remote.isReady) return _append(item);
    try {
      await remote.setMerge(item.collection, item.docId, item.data);
    } catch (_) {
      await _append(item);
    }
  }

  @override
  void enqueue(SyncItem item) => unawaited(enqueueAsync(item));

  /// sync.ts flushQueue().
  Future<void> flush() => _locked(() async {
    if (!remote.isReady) return;
    final items = _load()..sort((a, b) => a.priority.compareTo(b.priority));
    final remaining = <SyncItem>[];
    for (final item in items) {
      try {
        await remote.setMerge(item.collection, item.docId, item.data);
      } catch (_) {
        remaining.add(item);
      }
    }
    await _save(remaining);
  });

  /// sync.ts getPending().
  List<SyncItem> get pending => _load();

  /// sync.ts clearPending().
  Future<void> clearPending() => _locked(() => _save([]));

  Future<void> dispose() async => _sub?.cancel();
}
