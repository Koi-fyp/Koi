/// Mirrors `SyncItem` / `syncQueue.enqueue` in
/// repos/koi-backend/nextjs_app/src/lib/firestore/sync.ts.
///
/// Only the interface exists so far. The real queue (priority ordering,
/// local persistence, flush on reconnect, merge writes) is built in playbook
/// Prompt 6 by mirroring sync.ts.
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
  final Map<String, Object?> data;

  /// sync.ts: 1=crisis, 2=mood, 3=messages, 4=tasks/user
  final int priority;

  /// sync.ts sets this to Date.now() (ms) when an item is queued locally.
  final int? timestamp;
}

abstract interface class SyncQueue {
  void enqueue(SyncItem item);
}
